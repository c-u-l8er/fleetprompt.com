defmodule FleetPromptWeb.AdminShellHTML do
  @moduledoc """
  HEEx templates for the Admin "shell" pages (controller-rendered).

  This module is intended to back templates placed under:

      lib/fleet_prompt_web/controllers/admin_shell_html/

  Example usage from a controller:

      render(conn, :index, assigns)
  """

  use FleetPromptWeb, :html

  embed_templates("admin_shell_html/*")
end
