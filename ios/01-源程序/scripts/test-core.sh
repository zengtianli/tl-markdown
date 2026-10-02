#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
python3 "$FOLIO_COMPONENT_ROOT/Tests/static_check.py"
source "$HOME/Dev/tools/dev/lib/tools/macapp/xcode_env.sh"
xcode_env_use macosx
scratch="$(mktemp -d "${TMPDIR:-/tmp}/folio-mobile-core.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
xcrun swiftc -swift-version 5 -O -lsqlite3 \
  "$FOLIO_FAMILY_ROOT/Sources/Models.swift" "$FOLIO_FAMILY_ROOT/Sources/IndexEngine.swift" \
  "$FOLIO_COMPONENT_ROOT/Sources/DocumentWorkspace.swift" "$FOLIO_COMPONENT_ROOT/Tests/CoreTests.swift" -o "$scratch/core-tests"
"$scratch/core-tests"
xcrun swiftc -swift-version 5 -O -lsqlite3 \
  "$FOLIO_FAMILY_ROOT/Sources/Models.swift" "$FOLIO_FAMILY_ROOT/Sources/IndexEngine.swift" \
  "$FOLIO_COMPONENT_ROOT/Sources/DocumentWorkspace.swift" "$FOLIO_COMPONENT_ROOT/CLI/main.swift" -o "$scratch/folio-mobile"
"$scratch/folio-mobile" --help
