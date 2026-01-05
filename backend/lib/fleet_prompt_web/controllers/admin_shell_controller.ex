defmodule FleetPromptWeb.AdminShellController do
  @moduledoc """
  Admin "shell" page that wraps AshAdmin (LiveView) in an iframe.

  This controller exists because AshAdmin mounts via its own LiveView routing and
  uses its own root layout by default. If you want consistent navigation between
  Admin and the rest of the app (shared header, "Back to app", tenant context),
  you can render a normal controller page and embed AshAdmin at `/admin/ui`.

  Template:
  - `AdminShellHTML.index/1` (template: `admin_shell_html/index.html.heex`)

  Expected assigns provided to the template:
  - `:iframe_src` (string)
  - `:tenant_label` (string; "public" or `org_*`)
  """

  use FleetPromptWeb, :controller

  # Render this page with the normal app HTML shell (assets, meta tags, etc),
  # but without extra server-rendered chrome. The template itself provides the
  # admin header + iframe.
  plug(:put_root_layout, html: {FleetPromptWeb.Layouts, :root})
  plug(:put_layout, html: {FleetPromptWeb.Layouts, :inertia})

  @ash_admin_iframe_path "/admin/ui"

  def index(conn, _params) do
    conn = Plug.Conn.fetch_query_params(conn)

    # Preserve query string so `/admin?tenant=demo` can set tenant (via plugs) and
    # the iframe can carry any additional params if you ever add them.
    iframe_src =
      case conn.query_string do
        "" -> @ash_admin_iframe_path
        qs -> @ash_admin_iframe_path <> "?" <> qs
      end

    # Best-effort: surface tenant context in the shell header.
    tenant =
      conn.assigns[:ash_tenant] ||
        get_session(conn, "tenant") ||
        (conn.req_cookies && conn.req_cookies["tenant"])

    tenant_label =
      case tenant do
        nil -> "public"
        "" -> "public"
        "public" -> "public"
        "none" -> "public"
        other -> other
      end

    render(conn, :index, iframe_src: iframe_src, tenant_label: tenant_label)
  end
end
