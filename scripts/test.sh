#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"
source /Users/tianli/Dev/tools/dev/lib/tools/macapp/xcode_env.sh
xcode_env_use macosx
mkdir -p build
xcrun swiftc Sources/Models.swift Tests/DocumentIOTests.swift -o build/document-io-tests
build/document-io-tests build/io-tests | tee build/io-test-results.txt
xcrun swiftc -parse-as-library Sources/Models.swift Sources/ViewModel.swift Sources/BackendClient.swift Tests/StoreTests.swift -o build/store-tests
build/store-tests build/store-tests-data | tee build/store-test-results.txt
xcrun swiftc -parse-as-library Sources/Models.swift Sources/ViewModel.swift Sources/BackendClient.swift Tests/NativeEditorTests.swift -o build/native-editor-tests
build/native-editor-tests | tee build/native-editor-test-results.txt
# The optional full preview still uses these bundled components; these are not native editor tests.
(cd Editor && npm run build && npm test)
