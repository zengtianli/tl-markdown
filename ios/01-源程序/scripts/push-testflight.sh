#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
exec bash "$HOME/Dev/tools/dev/lib/tools/macapp/ios/push-testflight.sh" --testflight-only "$FOLIO_COMPONENT_ROOT"
