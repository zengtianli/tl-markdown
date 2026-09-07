#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
source /Users/tianli/Dev/tools/dev/lib/tools/macapp/xcode_env.sh
xcode_env_use macosx
/opt/homebrew/bin/python3 /Users/tianli/Dev/tools/dev/lib/tools/macapp/check_codingkeys.py "$DIR"
DISPLAY_NAME="$(/Users/tianli/Dev/.venv/bin/python3 -c 'import yaml; print(yaml.safe_load(open("catalog.yaml"))["display_name"])')"
if [ ! -f icon/AppIcon.icns ]; then
  /Users/tianli/Dev/.venv/bin/python3 - <<'PY'
import yaml, subprocess
c=yaml.safe_load(open('catalog.yaml'))
subprocess.run(['/opt/homebrew/bin/python3','/Users/tianli/Dev/tools/dev/lib/tools/macapp/make_icon.py','--glyph',c['icon']['glyph'],'--color',c['icon']['color'],'--out','icon/AppIcon','--badge',c['icon'].get('badge',''),'--icns'],check=True)
PY
fi
(cd "$DIR/Editor" && npm run build)
mkdir -p build
xcodebuild -project TLMarkdown.xcodeproj -scheme TLMarkdown -configuration Release -derivedDataPath "$DIR/build/DerivedData" CODE_SIGNING_ALLOWED=NO build > "$DIR/build/xcodebuild.log" 2>&1 || { tail -100 "$DIR/build/xcodebuild.log"; exit 1; }
APP="$DIR/build/DerivedData/Build/Products/Release/TLMarkdown.app"
test -d "$APP"
plutil -replace CFBundleDisplayName -string "$DISPLAY_NAME" "$APP/Contents/Info.plist"
plutil -replace CFBundleName -string "$DISPLAY_NAME" "$APP/Contents/Info.plist"
plutil -replace CFBundleIconFile -string AppIcon "$APP/Contents/Info.plist"
VERSION=1
if git rev-parse --verify HEAD >/dev/null 2>&1; then VERSION="$(git rev-list --count HEAD)"; fi
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
ditto "$DIR/Resources" "$APP/Contents/Resources"
cp "$DIR/icon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
python3 "$DIR/scripts/test_file_open.py" "$APP"
if [ "${1:-}" = "--install" ]; then
  DEST="/Applications/$DISPLAY_NAME.app"
  if [ -e "$DEST" ]; then
    ARCHIVE="$HOME/.Trash/folio-previous-$(date +%s)"
    mkdir -p "$ARCHIVE"
    mv "$DEST" "$ARCHIVE/"
  fi
  ditto "$APP" "$DEST"
  echo "Installed: $DEST"
else
  echo "Built: $APP"
fi
