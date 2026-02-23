defmodule FleetPrompt.Chat.SettingsTest do
  use ExUnit.Case, async: false

  alias FleetPrompt.Chat.Settings

  setup do
    original_env = System.get_env("CHAT_TOOL_LOOP_MAX_ROUNDS")
    original_app = Application.get_env(:fleet_prompt, :chat)

    on_exit(fn ->
      case original_env do
        nil -> System.delete_env("CHAT_TOOL_LOOP_MAX_ROUNDS")
        v -> System.put_env("CHAT_TOOL_LOOP_MAX_ROUNDS", v)
      end

      case original_app do
        nil -> Application.delete_env(:fleet_prompt, :chat)
        v -> Application.put_env(:fleet_prompt, :chat, v)
      end
    end)

    :ok
  end

  test "uses app env when CHAT_TOOL_LOOP_MAX_ROUNDS is not set" do
    System.delete_env("CHAT_TOOL_LOOP_MAX_ROUNDS")
    Application.put_env(:fleet_prompt, :chat, tool_loop_max_rounds: 7)

    assert Settings.tool_loop_max_rounds() == 7
  end

  test "CHAT_TOOL_LOOP_MAX_ROUNDS overrides app env" do
    Application.put_env(:fleet_prompt, :chat, tool_loop_max_rounds: 7)
    System.put_env("CHAT_TOOL_LOOP_MAX_ROUNDS", "9")

    assert Settings.tool_loop_max_rounds() == 9
  end

  test "invalid CHAT_TOOL_LOOP_MAX_ROUNDS falls back to app env" do
    Application.put_env(:fleet_prompt, :chat, tool_loop_max_rounds: 7)
    System.put_env("CHAT_TOOL_LOOP_MAX_ROUNDS", "nope")

    assert Settings.tool_loop_max_rounds() == 7
  end
end
