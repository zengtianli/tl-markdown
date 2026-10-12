#!/bin/bash
# Build identical Editor sources into this variant's own generated resources, never ../Resources.
set -euo pipefail
STORE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$STORE/.." && pwd)"
WORK="$STORE/Generated/work"
NODE=/opt/homebrew/bin/node
test -x "$NODE"
test -d "$ROOT/Editor/node_modules" || { echo 'Editor dependencies missing; prepare Editor/node_modules before building.' >&2; exit 1; }
mkdir -p "$WORK/Editor" "$WORK/Resources"
cp "$ROOT/Editor/build.mjs" "$ROOT/Editor/package.json" "$ROOT/Editor/package-lock.json" "$WORK/Editor/"
/usr/bin/ditto "$ROOT/Editor/src" "$WORK/Editor/src"
if [ ! -L "$WORK/Editor/node_modules" ]; then ln -s "$ROOT/Editor/node_modules" "$WORK/Editor/node_modules"; fi
cd "$WORK/Editor"
/usr/bin/env -i HOME="$HOME" PATH=/opt/homebrew/bin:/usr/bin:/bin "$NODE" build.mjs
/usr/bin/ditto "$WORK/Resources/Editor" "$STORE/Generated/Editor"
cp "$WORK/Resources/THIRD-PARTY-NOTICES.txt" "$STORE/Generated/THIRD-PARTY-NOTICES.txt"
"$HOME/Dev/.venv/bin/python" "$STORE/check.py" --stamp-editor
