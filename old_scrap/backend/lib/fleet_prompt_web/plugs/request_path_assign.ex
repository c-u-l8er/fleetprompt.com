defmodule FleetPromptWeb.Plugs.RequestPathAssign do
  @moduledoc """
  Assigns request path metadata onto `conn.assigns` for use in layouts/templates.

  Why:
  - Some layouts (notably `root.html.heex`) may want to conditionally render
    navigation chrome based on the current request path.
  - Relying on `@conn.request_path` is usually fine, but templates/components
    sometimes receive assigns without a full conn struct (or you may want a
    stable, explicit assign).

  What it assigns:
  - `:request_path`       -> `conn.request_path`
  - `:request_full_path`  -> `conn.request_path <> "?" <> conn.query_string` (if present)

  Safe to use in any pipeline.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    full_path =
      case conn.query_string do
        "" -> conn.request_path
        qs -> conn.request_path <> "?" <> qs
      end

    conn
    |> assign(:request_path, conn.request_path)
    |> assign(:request_full_path, full_path)
  end
end
