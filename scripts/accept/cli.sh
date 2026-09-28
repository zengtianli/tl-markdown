#!/bin/bash
set -euo pipefail
if [ -z "${ACCEPT_WORK:-}" ]; then
  ACCEPT_NAME="${ACCEPT_NAME:-functionality}"
  source "$(dirname "$0")/_common.sh"
fi
bash "$ACCEPT_ROOT/scripts/build-cli.sh" "$ACCEPT_WORK/folio"
export FOLIO_GRAPH_TEMPLATE="$ACCEPT_ROOT/Resources/graph-view.html"
python3 "$ACCEPT_ROOT/scripts/accept/cli_cases.py" "$ACCEPT_WORK/folio" "$ACCEPT_WORK/cli" "${1:-functionality}"
if [ "${1:-functionality}" = recovery ]; then
  xcrun swiftc -parse-as-library Sources/IndexEngine.swift Tests/IndexEngineTests.swift -o "$ACCEPT_WORK/index-recovery"
  "$ACCEPT_WORK/index-recovery"
fi
