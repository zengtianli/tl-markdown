#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
MODE="${1:---verify}"
case "$MODE" in
  --build-only|--verify|--install|--install-local) ;;
  *) echo "Usage: bash build.sh [--build-only|--verify|--install|--install-local]" >&2; exit 2 ;;
esac
# --install produces the one release grade (scripts/release_grade.py): Developer ID + hardened runtime +
# secure timestamp, notarized by Apple, ticket stapled. --build-only / --verify sign ad hoc: trial builds
# that stay in build/ and that the installer refuses. Fail before the long build when this session cannot sign.
#
# Compiling does not need the certificate. FOLIO_PREBUILT=<TLMarkdown-…-trial.zip | TLMarkdown.app> makes
# --install adopt a --build-only product of this same commit and sources (made on the Mac with idle cores)
# and do only what needs the signing Mac: sign, test the signed bundle, notarize, staple, package, install.
IDENTITY="Developer ID Application: tianli Zeng (B9LJH93LA4)"
NOTARIZE="$HOME/Apps/mackit/scripts/notarize.py"
PREBUILT="${FOLIO_PREBUILT:-}"
if [ "$MODE" = "--install" ] || { [ "$MODE" = "--install-local" ] && [ -z "$PREBUILT" ]; }; then
  security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$IDENTITY\"" || {
    echo "build.sh --install 要用 ${IDENTITY} 签名，这台 Mac 的钥匙串里没有。" >&2
    echo "在有证书的 Mac 的登录会话里跑它；其他 Mac 装它出的同一份包：python3 scripts/release_grade.py install build/release/Folio-<版本>-<构建>-arm64.zip" >&2
    exit 1; }
  if [ "$MODE" = "--install" ]; then test -f "$NOTARIZE" || { echo "找不到公证入口 ${NOTARIZE}" >&2; exit 1; }; fi
fi
if [ -n "$PREBUILT" ] && [ "$MODE" != "--install" ] && [ "$MODE" != "--install-local" ]; then echo "FOLIO_PREBUILT 只用于安装" >&2; exit 2; fi
if [ "$MODE" = "--install-local" ] && [ -n "$PREBUILT" ]; then
  python3 "$DIR/scripts/release_grade.py" check-local "$PREBUILT" > /dev/null
fi
source /Users/tianli/Dev/tools/dev/lib/tools/macapp/xcode_env.sh
xcode_env_use macosx
source /Users/tianli/Dev/tools/dev/lib/tools/macapp/scrub_env.sh
DISPLAY_NAME="$(/Users/tianli/Dev/.venv/bin/python3 -c 'import yaml; print(yaml.safe_load(open("project.yaml"))["name_en"])')"
VERSION=1
if git rev-parse --verify HEAD >/dev/null 2>&1; then VERSION="$(git rev-list --count HEAD)"; fi
DEST="/Applications/$DISPLAY_NAME.app"
if [ "$MODE" = "--install" ] && [ -d "$DEST" ]; then
  # A rebuilt package needs a new build number (the commit count): one version + build is one content.
  SHORT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DIR/Info.plist")"
  if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DEST/Contents/Info.plist"))" = "$SHORT ($VERSION)" ]; then
    echo "${DEST} 已经是 ${SHORT} (${VERSION})。重出包先提交（构建号 = 提交数），不用同一个构建号装不同内容。" >&2; exit 1
  fi
fi
# FOLIO_DERIVED_DATA / FOLIO_BUILD_LOG redirect the Xcode products and log for trial builds
# (use with --build-only); package-release.py packages the default build/DerivedData.
DD="${FOLIO_DERIVED_DATA:-$DIR/build/DerivedData}"
LOG="${FOLIO_BUILD_LOG:-$DIR/build/xcodebuild.log}"
mkdir -p build "$DD" "$(dirname "$LOG")"
DD="$(cd "$DD" && pwd)"
APP="$DD/Build/Products/Release/TLMarkdown.app"
if [ -n "$PREBUILT" ]; then
  # Adopt the other Mac's --build-only product; package-release.py --adopt refuses one from another
  # commit, other sources or another build number.
  rm -rf "$APP"; mkdir -p "$(dirname "$APP")"
  case "$PREBUILT" in
    *.zip) ditto -x -k "$PREBUILT" "$(dirname "$APP")" ;;
    *) ditto "$PREBUILT" "$APP" ;;
  esac
  test -d "$APP"
  codesign --verify --deep --strict "$APP"
  python3 "$DIR/scripts/package-release.py" --app "$APP" --adopt
else
# A shell profile's Homebrew llvm overrides (CC=/opt/homebrew/opt/llvm/bin/clang …) make Xcode probe a
# compiler that a Mac without that formula does not have; this build uses Xcode's own toolchain.
unset CC CXX CPPFLAGS CFLAGS LDFLAGS LIBRARY_PATH
/opt/homebrew/bin/python3 /Users/tianli/Dev/tools/dev/lib/tools/macapp/check_codingkeys.py "$DIR"
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
# Release strip (strip -D -x) runs after Xcode writes the dSYM next to the product, so crash
# symbolication still works: it removes the executable's local symbols and its debug map (object
# paths). STRIP_SWIFT_SYMBOLS=NO: Xcode's default adds -T, which leaves ~1,300 local symbols.
scrub_env_run xcodebuild -project TLMarkdown.xcodeproj -scheme TLMarkdown -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO \
  DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES STRIP_STYLE=non-global STRIP_SWIFT_SYMBOLS=NO \
  build > "$LOG" 2>&1 || { tail -100 "$LOG"; exit 1; }
test -d "$APP"
plutil -replace CFBundleDisplayName -string "$DISPLAY_NAME" "$APP/Contents/Info.plist"
plutil -replace CFBundleName -string "$DISPLAY_NAME" "$APP/Contents/Info.plist"
ICON_NAME="AppIcon-$(shasum -a 256 "$DIR/icon/AppIcon.icns" | cut -c 1-16)"
plutil -replace CFBundleIconFile -string "$ICON_NAME" "$APP/Contents/Info.plist"
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
bash "$DIR/scripts/build-cli.sh" "$APP/Contents/Resources/bin/folio"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
# Fail closed if the release executable keeps local symbols (nm type t/d/b/s) or debug entries
# (type '-', except strip's own radr://5614542 marker); nm puts the type letter in column 18.
LEFT="$(nm -a "$APP/Contents/MacOS/$EXECUTABLE_NAME" | awk 'substr($0,17,1)==" " && substr($0,19,1)==" " { t=substr($0,18,1); if (t ~ /[tdbs]/ || (t=="-" && $0 !~ /radr:\/\/5614542/)) n++ } END { print n+0 }')"
[ "$LEFT" = 0 ] || { echo "Release executable still has $LEFT local/debug symbols" >&2; exit 1; }
python3 "$DIR/scripts/package-release.py" --app "$APP" --stamp
fi
if [ "$MODE" = "--install" ] || { [ "$MODE" = "--install-local" ] && [ -z "$PREBUILT" ]; }; then
  # Every Mach-O in the bundle gets the Developer ID, the hardened runtime and a secure timestamp: the
  # bundled command first (the build stamp records its signed digest), then the app that seals it.
  # Over SSH codesign answers errSecInternalComponent: the private key only unlocks in the login session.
  codesign --force --options runtime --timestamp --sign "$IDENTITY" --identifier cyou.tianli.TLMarkdown.cli "$APP/Contents/Resources/bin/folio"
  python3 "$DIR/scripts/package-release.py" --app "$APP" --stamp-cli
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
elif [ "$MODE" != "--install-local" ]; then
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
if [ "$MODE" = "--install-local" ]; then
  # Explicitly authorized local iteration: stable Developer ID, original hidden product suite,
  # atomic installation with rollback. No public packaging, notarization or update-source writes.
  python3 "$DIR/scripts/release_grade.py" check-local "$APP" > "$DIR/build/local-signature.json"
  bash "$DIR/scripts/accept/lifecycle.sh" "$APP"
  python3 "$DIR/scripts/release_grade.py" install-local "$APP" > "$DIR/build/local-install.json"
  echo "Installed local iteration without launch/notarization: $DEST"
  exit 0
fi
if [ "$MODE" = "--build-only" ]; then
  # The hand-off for FOLIO_PREBUILT on the signing Mac (build/ is not synced between the Macs).
  TRIAL="$DIR/build/trial/TLMarkdown-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")-$VERSION-trial.zip"
  rm -rf "$DIR/build/trial"; mkdir -p "$DIR/build/trial"
  ditto -c -k --keepParent "$APP" "$TRIAL"
  echo "Built without launching an app: $APP"
  echo "Trial build (ad hoc, not installable): $TRIAL"
  echo "Production editor/file-open verification is pending; run --verify for isolated checks."
  exit 0
fi
bash "$DIR/scripts/test.sh" --main-editor "$APP/Contents/Resources"
python3 "$DIR/scripts/test_file_open.py" "$APP"
if [ "$MODE" = "--install" ]; then
  # Apple notarization of the exact tested bundle, then the stapled ticket. Submitting is not publishing.
  NOTARY="$DIR/build/notary"
  rm -rf "$NOTARY"; mkdir -p "$NOTARY"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$NOTARY/submission.zip"
  /Users/tianli/Dev/.venv/bin/python3 "$NOTARIZE" "$NOTARY/submission.zip" "$NOTARY/notary.json"
  xcrun stapler staple "$APP"
  python3 "$DIR/scripts/release_grade.py" check "$APP" > "$NOTARY/grade.json"
  # The ZIP is the one package: this Mac installs it, and so does every other Mac.
  python3 "$DIR/scripts/package-release.py" --app "$APP" > "$NOTARY/package.log"
  PACKAGE="$DIR/build/release/$(/Users/tianli/Dev/.venv/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["filename"])' "$DIR/build/release/release.json")"
  python3 "$DIR/scripts/release_grade.py" install "$PACKAGE"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DEST/Contents/Info.plist"
  echo "Installed: $DEST (Developer ID, notarized, stapled)"
  echo "Package for the other Mac: $PACKAGE  →  python3 scripts/release_grade.py install <that zip>"
  echo "Existing user sessions were not stopped or restarted. For a source-bound receipt, use python3 scripts/verify-install.py."
else
  echo "Built: $APP"
fi
