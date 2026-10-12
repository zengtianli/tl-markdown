#!/bin/bash
# Execute the unchanged original core suite in a throwaway tree so its build/ outputs stay out of the repository.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/store/Generated/core-tests"
mkdir -p "$WORK/scripts/accept" "$WORK/Resources"
for directory in Sources Tests CLI; do /usr/bin/ditto "$ROOT/$directory" "$WORK/$directory"; done
cp "$ROOT/scripts/test.sh" "$ROOT/scripts/build-cli.sh" "$WORK/scripts/"
cp "$ROOT/scripts/accept/cli_cases.py" "$WORK/scripts/accept/"
cp "$ROOT/Resources/graph-view.html" "$ROOT/Resources/欢迎使用.md" "$WORK/Resources/"
if [ ! -L "$WORK/Editor" ]; then ln -s "$ROOT/Editor" "$WORK/Editor"; fi
cmp "$ROOT/scripts/test.sh" "$WORK/scripts/test.sh"
/bin/bash "$WORK/scripts/test.sh" --core-only
