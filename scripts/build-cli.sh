#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:-$ROOT/build/folio}"
mkdir -p "$(dirname "$OUT")"
if [ -z "${DEVELOPER_DIR:-}" ]; then
  source "$HOME/Dev/tools/dev/lib/tools/macapp/xcode_env.sh"
  xcode_env_use macosx
fi
xcrun swiftc -Osize -whole-module-optimization -parse-as-library \
  -target arm64-apple-macosx15.0 \
  Sources/IndexEngine.swift Sources/GraphEngine.swift CLI/main.swift -o "$OUT"
xcrun strip -x "$OUT"
test "$(stat -f %z "$OUT")" -le 2000000
codesign --force --sign - --identifier cyou.tianli.TLMarkdown.cli "$OUT"
codesign --verify --strict "$OUT"
