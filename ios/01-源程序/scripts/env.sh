#!/bin/bash
set -euo pipefail
FOLIO_COMPONENT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export FOLIO_FAMILY_ROOT="${FOLIO_FAMILY_ROOT:-$(cd "$FOLIO_COMPONENT_ROOT/../.." && pwd)}"
test -f "$FOLIO_FAMILY_ROOT/Sources/Models.swift"
test -f "$FOLIO_FAMILY_ROOT/Sources/IndexEngine.swift"
test -f "$FOLIO_FAMILY_ROOT/Resources/Editor/index.html"
