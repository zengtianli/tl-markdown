#!/bin/bash
# Shared, noninteractive acceptance setup. No installed app or user state is used.
set -euo pipefail
ACCEPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ACCEPT_ROOT"
: "${ACCEPT_NAME:?Set ACCEPT_NAME before sourcing _common.sh}"
case "$ACCEPT_NAME" in functionality|recovery|privacy|native_ui) ;; *) exit 64 ;; esac
export SOP_OUT_DIR="${SOP_OUT_DIR:-$ACCEPT_ROOT/perf/acceptance}"
mkdir -p "$ACCEPT_ROOT/build/accept/$ACCEPT_NAME" "$SOP_OUT_DIR"
ACCEPT_WORK="$(mktemp -d "$ACCEPT_ROOT/build/accept/$ACCEPT_NAME/run.XXXXXX")"
export TL_MARKDOWN_STATE_DIR="$ACCEPT_WORK/state"
export FOLIO_BACKGROUND=1
unset TL_MARKDOWN_OPEN TL_MARKDOWN_BENCHMARK MDINDEX_DB
source /Users/tianli/Dev/tools/dev/lib/tools/macapp/xcode_env.sh
xcode_env_use macosx

# Tests compile the actual production I/O, store, and bridge, not a reimplementation.
accept_compile_store() {
  xcrun swiftc -parse-as-library Sources/Models.swift Sources/ViewModel.swift Sources/BackendClient.swift "$1" -o "$ACCEPT_WORK/check"
}

# Only an acceptor's detail is written here; Chapter owns delivery-evidence.json.
accept_detail() {
  python3 - "$SOP_OUT_DIR/$ACCEPT_NAME.detail.json" "$1" <<'PY'
import json, pathlib, sys
pathlib.Path(sys.argv[1]).write_text(json.dumps({"summary": sys.argv[2], "environment": "isolated synthetic data; no input synthesis"}, ensure_ascii=False, indent=2) + "\n")
PY
}
