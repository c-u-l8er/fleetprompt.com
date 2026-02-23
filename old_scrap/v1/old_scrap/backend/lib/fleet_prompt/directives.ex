defmodule FleetPrompt.Directives do
  @moduledoc """
  Ash domain for **Directives** (Phase 2B).

  Directives are tenant-scoped, auditable commands (controlled intent) that are
  the only allowed path to side effects.

  This module is intentionally introduced early so it can be included in
  `:ash_domains` before the underlying directive resources are implemented.

  Planned (Phase 2B):
  - `FleetPrompt.Directives.Directive` (tenant-scoped)
  - an Oban runner to execute directives safely + idempotently
  """

  use Ash.Domain, extensions: [AshAdmin.Domain]

  admin do
    show?(true)
    name("Directives")
  end

  resources do
    resource(FleetPrompt.Directives.Directive)
  end
end
