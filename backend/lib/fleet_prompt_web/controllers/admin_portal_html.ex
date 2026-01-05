defmodule FleetPromptWeb.AdminPortalHTML do
  @moduledoc """
  HTML view module for the Admin Portal.

  This is intended to be a controller-rendered "landing page" for admin UX
  that can provide branding, tenant context, shortcuts, and onboarding guidance
  before sending the user into AshAdmin (LiveView).

  Templates live under `admin_portal_html/` and are embedded at compile time.
  """

  use FleetPromptWeb, :html

  embed_templates("admin_portal_html/*")
end
