#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"
source /Users/tianli/Dev/tools/dev/lib/tools/macapp/xcode_env.sh
xcode_env_use macosx
mkdir -p build
main_editor_checks() {
  local resources="$1"
  local test_app="$DIR/build/MainEditorTests.app"
  test -f "$resources/Editor/index.html"
  mkdir -p "$test_app/Contents/MacOS" "$test_app/Contents/Resources"
  ditto "$resources/Editor" "$test_app/Contents/Resources/Editor"
  /usr/libexec/PlistBuddy -c 'Clear dict' "$test_app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Add CFBundleExecutable string MainEditorTests' "$test_app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Add CFBundleIdentifier string cyou.tianli.Folio.MainEditorTests' "$test_app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Add CFBundlePackageType string APPL' "$test_app/Contents/Info.plist"
  xcrun swiftc -parse-as-library Sources/Models.swift Sources/ViewModel.swift Sources/BackendClient.swift Tests/MainEditorTests.swift -o "$test_app/Contents/MacOS/MainEditorTests"
  "$test_app/Contents/MacOS/MainEditorTests" "$DIR/build/main-editor-tests-data" | tee "$DIR/build/main-editor-test-results.txt"
}
if [ "${1:-}" = "--main-editor" ]; then
  main_editor_checks "${2:?Provide the built application Resources directory}"
  exit 0
fi
xcrun swiftc Sources/Models.swift Tests/DocumentIOTests.swift -o build/document-io-tests
build/document-io-tests build/io-tests | tee build/io-test-results.txt
xcrun swiftc -parse-as-library Sources/Models.swift Sources/ViewModel.swift Sources/BackendClient.swift Tests/StoreTests.swift -o build/store-tests
build/store-tests build/store-tests-data | tee build/store-test-results.txt
if [ "${1:-}" = "--core-only" ]; then
  echo "Production I/O and store checks passed; no windows, clipboard or browser tests run."
  exit 0
fi
xcrun swiftc -parse-as-library Sources/Models.swift Sources/ViewModel.swift Sources/BackendClient.swift Tests/NativeEditorTests.swift -o build/native-editor-tests
build/native-editor-tests | tee build/native-editor-test-results.txt
# These components power the main single-pane editor and the optional preview.
(cd Editor && npm run build && npm test)
main_editor_checks "$DIR/Resources"
