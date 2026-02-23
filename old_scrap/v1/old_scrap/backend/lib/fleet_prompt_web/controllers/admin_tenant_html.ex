defmodule FleetPromptWeb.AdminTenantHTML do
  @moduledoc """
  HTML view module for the admin tenant selector.

  Templates live under `admin_tenant_html/` and are embedded at compile time.
  """

  use FleetPromptWeb, :html

  embed_templates("admin_tenant_html/*")
end
