#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
platform="${1:-iphone}"
case "$platform" in
  iphone|ipad|vision) scheme=FolioMobile ;;
  *) echo "usage: bash scripts/build.sh iphone|ipad|vision" >&2; exit 2 ;;
esac
python3 "$HOME/Dev/tools/dev/lib/tools/macapp/ios/sim_lane.py" build \
  --project-dir "$FOLIO_COMPONENT_ROOT" --platform "$platform" --scheme "$scheme" --configuration Release --json
