#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
exec "$HOME/Dev/.venv/bin/python" \
  "$HOME/Apps/.claude/skills/app-lightweight/scripts/platform_measure.py" \
  --app folio --repo "$FOLIO_COMPONENT_ROOT" --platform all --sync-ios "$@"
