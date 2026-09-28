#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
MODE="${1:---verify}"
case "$MODE" in
  --build-only|--verify|--install) ;;
  *) echo "Usage: bash build.sh [--build-only|--verify|--install]" >&2; exit 2 ;;
esac
source /Users/tianli/Dev/tools/dev/lib/tools/macapp/xcode_env.sh
xcode_env_use macosx
source /Users/tianli/Dev/tools/dev/lib/tools/macapp/scrub_env.sh
/opt/homebrew/bin/python3 /Users/tianli/Dev/tools/dev/lib/tools/macapp/check_codingkeys.py "$DIR"
DISPLAY_NAME="$(/Users/tianli/Dev/.venv/bin/python3 -c 'import yaml; print(yaml.safe_load(open("project.yaml"))["name_en"])')"
# Derive every build from catalog's source; an existing ICNS may be stale.
/Users/tianli/Dev/.venv/bin/python3 - <<'PY'
import yaml, subprocess, sys
from pathlib import Path
c=yaml.safe_load(open('project.yaml'))
if c.get('icon_png'):
    sys.path.insert(0, '/Users/tianli/Dev/tools/dev/lib/tools/macapp')
    from make_icon import to_icns
    to_icns(Path(c['icon_png']))
elif c.get('icon'):
    subprocess.run(['/opt/homebrew/bin/python3','/Users/tianli/Dev/tools/dev/lib/tools/macapp/make_icon.py','--glyph',c['icon']['glyph'],'--color',c['icon']['color'],'--out','icon/AppIcon','--badge',c['icon'].get('badge',''),'--icns'],check=True)
elif not Path('icon/AppIcon.icns').is_file():
    sys.exit('project.yaml has no icon source and icon/AppIcon.icns is missing')
PY
(cd "$DIR/Editor" && npm run build)
# FOLIO_DERIVED_DATA / FOLIO_BUILD_LOG redirect the Xcode products and log for trial builds
# (use with --build-only); package-release.py packages the default build/DerivedData.
DD="${FOLIO_DERIVED_DATA:-$DIR/build/DerivedData}"
LOG="${FOLIO_BUILD_LOG:-$DIR/build/xcodebuild.log}"
mkdir -p build "$DD" "$(dirname "$LOG")"
DD="$(cd "$DD" && pwd)"
# Release strip (strip -D -x) runs after Xcode writes the dSYM next to the product, so crash
# symbolication still works: it removes the executable's local symbols and its debug map (object
# paths). STRIP_SWIFT_SYMBOLS=NO: Xcode's default adds -T, which leaves ~1,300 local symbols.
scrub_env_run xcodebuild -project TLMarkdown.xcodeproj -scheme TLMarkdown -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO \
  DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES STRIP_STYLE=non-global STRIP_SWIFT_SYMBOLS=NO \
  build > "$LOG" 2>&1 || { tail -100 "$LOG"; exit 1; }
APP="$DD/Build/Products/Release/TLMarkdown.app"
test -d "$APP"
plutil -replace CFBundleDisplayName -string "$DISPLAY_NAME" "$APP/Contents/Info.plist"
plutil -replace CFBundleName -string "$DISPLAY_NAME" "$APP/Contents/Info.plist"
ICON_NAME="AppIcon-$(shasum -a 256 "$DIR/icon/AppIcon.icns" | cut -c 1-16)"
plutil -replace CFBundleIconFile -string "$ICON_NAME" "$APP/Contents/Info.plist"
VERSION=1
if git rev-parse --verify HEAD >/dev/null 2>&1; then VERSION="$(git rev-list --count HEAD)"; fi
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
# ditto merges: clear the generated editor bundle so files a previous build
# emitted (old hashed fonts) never linger in the app.
rm -rf "$APP/Contents/Resources/Editor"
ditto "$DIR/Resources" "$APP/Contents/Resources"
# Ship the icon once, under the content-hashed name Info.plist points to (it
# busts the Finder/Dock icon cache). Xcode's plain AppIcon.icns copy is unused.
cp "$DIR/icon/AppIcon.icns" "$APP/Contents/Resources/$ICON_NAME.icns"
rm -f "$APP/Contents/Resources/AppIcon.icns"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
# Fail closed if the release executable keeps local symbols (nm type t/d/b/s) or debug entries
# (type '-', except strip's own radr://5614542 marker); nm puts the type letter in column 18.
LEFT="$(nm -a "$APP/Contents/MacOS/$EXECUTABLE_NAME" | awk 'substr($0,17,1)==" " && substr($0,19,1)==" " { t=substr($0,18,1); if (t ~ /[tdbs]/ || (t=="-" && $0 !~ /radr:\/\/5614542/)) n++ } END { print n+0 }')"
[ "$LEFT" = 0 ] || { echo "Release executable still has $LEFT local/debug symbols" >&2; exit 1; }
python3 "$DIR/scripts/package-release.py" --app "$APP" --stamp
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
if [ "$MODE" = "--build-only" ]; then
  echo "Built without launching an app: $APP"
  echo "Production editor/file-open verification is pending; run --verify for isolated checks."
  exit 0
fi
bash "$DIR/scripts/test.sh" --main-editor "$APP/Contents/Resources"
python3 "$DIR/scripts/test_file_open.py" "$APP"
if [ "$MODE" = "--install" ]; then
  DEST="/Applications/$DISPLAY_NAME.app"
  if [ -e "$DEST" ]; then
    ARCHIVE="$HOME/.Trash/folio-previous-$(date +%s)"
    mkdir -p "$ARCHIVE"
    mv "$DEST" "$ARCHIVE/"
  fi
  ditto "$APP" "$DEST"
  codesign --verify --deep --strict "$DEST"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DEST/Contents/Info.plist"
  echo "Installed: $DEST"
  echo "Existing user sessions were not stopped or restarted. For a source-bound receipt, use python3 scripts/verify-install.py."
else
  echo "Built: $APP"
fi
