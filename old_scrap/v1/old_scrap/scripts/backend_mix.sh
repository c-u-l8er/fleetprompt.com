#!/usr/bin/env sh
set -eu

# Run Mix tasks against the Phoenix backend from the monorepo root.
#
# Usage:
#   ./scripts/backend_mix.sh deps.get
#   ./scripts/backend_mix.sh test
#   ./scripts/backend_mix.sh ecto.create
#   ./scripts/backend_mix.sh phx.server
#
# You can also pass environment variables:
#   MIX_ENV=test ./scripts/backend_mix.sh test

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"

if [ ! -d "$BACKEND_DIR" ]; then
  echo "error: backend directory not found at: $BACKEND_DIR" >&2
  exit 1
fi

if [ $# -lt 1 ]; then
  echo "usage: $0 <mix-task> [args...]" >&2
  echo "example: $0 test" >&2
  exit 2
fi

# Execute in backend project directory so Mix finds mix.exs/app config normally.
cd "$BACKEND_DIR"
exec mix "$@"
