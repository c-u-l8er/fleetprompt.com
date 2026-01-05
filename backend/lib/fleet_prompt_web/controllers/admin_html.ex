defmodule FleetPromptWeb.AdminHTML do
  @moduledoc """
  HEEx templates for Admin-related controller pages.

  This module is used by controller modules that render templates under
  `admin_html/`.
  """

  use FleetPromptWeb, :html

  embed_templates("admin_html/*")
end
