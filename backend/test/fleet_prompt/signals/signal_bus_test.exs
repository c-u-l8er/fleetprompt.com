defmodule FleetPrompt.Signals.SignalBusTest do
  use FleetPrompt.DataCase, async: false

  require Ash.Query

  alias FleetPrompt.Accounts.{Organization, User}
  alias FleetPrompt.Jobs.SignalFanout
  alias FleetPrompt.Signals.{Signal, SignalBus}

  # Simple handler that reports invocation back to the test process.
  defmodule TestHandler do
    def handle_signal(%Signal{} = signal, context) when is_map(context) do
      opts = Map.get(context, :handler_opts, [])
      test_pid = Keyword.get(opts, :test_pid)

      if is_pid(test_pid) do
        send(test_pid, {:handled_signal, signal.id, signal.name, context})
      end

      :ok
    end
  end

  defmodule ErrorHandler do
    def handle_signal(%Signal{} = _signal, _context) do
      {:error, "handler_failed"}
    end
  end

  setup do
    uniq = System.unique_integer([:positive])

    {:ok, org} =
      Organization
      |> Ash.Changeset.for_create(:create, %{
        name: "Signals Test Org #{uniq}",
        slug: "signals-test-#{uniq}",
        tier: :pro
      })
      |> Ash.create()

    {:ok, user} =
      User
      |> Ash.Changeset.for_create(:create, %{
        email: "signals-test-#{uniq}@example.com",
        name: "Signals Test User #{uniq}",
        password: "password123",
        organization_id: org.id,
        role: :admin
      })
      |> Ash.create()

    tenant = "org_#{org.slug}"

    %{org: org, user: user, tenant: tenant}
  end

  test "SignalBus is idempotent by dedupe_key (created then existing)", %{tenant: tenant} do
    dedupe_key = "test:signalbus:dedupe:#{System.unique_integer([:positive])}"

    {:ok, %Signal{} = s1, :created} =
      SignalBus.emit(
        tenant,
        "test.signal.emitted",
        %{"hello" => "world"},
        metadata: %{"request_id" => "req_1"},
        dedupe_key: dedupe_key,
        source: "test",
        enqueue_fanout?: false
      )

    {:ok, %Signal{} = s2, :existing} =
      SignalBus.emit(
        tenant,
        "test.signal.emitted",
        %{"hello" => "world"},
        metadata: %{"request_id" => "req_2"},
        dedupe_key: dedupe_key,
        source: "test",
        enqueue_fanout?: false
      )

    assert s1.id == s2.id
    assert s1.dedupe_key == dedupe_key
    assert s1.name == "test.signal.emitted"

    # Ensure it is actually persisted and retrievable via read action
    query =
      Signal
      |> Ash.Query.for_read(:by_dedupe_key, %{dedupe_key: dedupe_key})

    assert {:ok, %Signal{} = fetched} = Ash.read_one(query, tenant: tenant)
    assert fetched.id == s1.id
  end

  test "SignalBus emits a new row each time when dedupe_key is nil", %{tenant: tenant} do
    {:ok, %Signal{} = s1, :created} =
      SignalBus.emit(
        tenant,
        "test.signal.nondeduped",
        %{"n" => 1},
        source: "test",
        enqueue_fanout?: false
      )

    {:ok, %Signal{} = s2, :created} =
      SignalBus.emit(
        tenant,
        "test.signal.nondeduped",
        %{"n" => 2},
        source: "test",
        enqueue_fanout?: false
      )

    assert s1.id != s2.id
    assert s1.dedupe_key == nil
    assert s2.dedupe_key == nil
  end

  test "SignalFanout invokes configured handlers and passes context", %{tenant: tenant} do
    prev_handlers = Application.get_env(:fleet_prompt, :signal_handlers, [])
    test_pid = self()

    Application.put_env(:fleet_prompt, :signal_handlers, [{TestHandler, test_pid: test_pid}])

    on_exit(fn ->
      Application.put_env(:fleet_prompt, :signal_handlers, prev_handlers)
    end)

    {:ok, %Signal{} = signal, :created} =
      SignalBus.emit(
        tenant,
        "test.signal.fanout",
        %{"fanout" => true},
        metadata: %{"k" => "v"},
        dedupe_key: "test:fanout:#{System.unique_integer([:positive])}",
        source: "test",
        enqueue_fanout?: false
      )

    job = %Oban.Job{args: %{"signal_id" => signal.id, "tenant" => tenant}}

    assert :ok = SignalFanout.perform(job)

    signal_id = signal.id
    assert_receive {:handled_signal, ^signal_id, "test.signal.fanout", context}, 1_000

    assert is_map(context)
    assert Map.get(context, :tenant) == tenant
    assert Map.get(context, :signal_id) == signal.id
    assert Map.get(context, :signal_name) == "test.signal.fanout"

    # We called perform/1 directly with a stub %Oban.Job{}, so these fields may be nil,
    # but the keys should exist in the context map.
    assert is_map(Map.get(context, :oban))
    assert is_map(Map.get(context, :args))
  end

  test "SignalFanout returns error when a handler returns {:error, _}", %{tenant: tenant} do
    prev_handlers = Application.get_env(:fleet_prompt, :signal_handlers, [])
    Application.put_env(:fleet_prompt, :signal_handlers, [ErrorHandler])

    on_exit(fn ->
      Application.put_env(:fleet_prompt, :signal_handlers, prev_handlers)
    end)

    {:ok, %Signal{} = signal, :created} =
      SignalBus.emit(
        tenant,
        "test.signal.handler_error",
        %{"x" => 1},
        dedupe_key: "test:fanout:error:#{System.unique_integer([:positive])}",
        source: "test",
        enqueue_fanout?: false
      )

    job = %Oban.Job{args: %{"signal_id" => signal.id, "tenant" => tenant}}

    assert {:error, msg} = SignalFanout.perform(job)
    assert is_binary(msg)
  end
end
