#!/bin/bash
set -euo pipefail
if [ -z "${ACCEPT_WORK:-}" ]; then
  ACCEPT_NAME="${ACCEPT_NAME:-functionality}"
  source "$(dirname "$0")/_common.sh"
fi
bash "$ACCEPT_ROOT/scripts/build-cli.sh" "$ACCEPT_WORK/folio"
export FOLIO_GRAPH_TEMPLATE="$ACCEPT_ROOT/Resources/graph-view.html"
python3 "$ACCEPT_ROOT/scripts/accept/cli_cases.py" "$ACCEPT_WORK/folio" "$ACCEPT_WORK/cli" "${1:-functionality}"
if [ "${1:-functionality}" = functionality ]; then
  # Installed layout, started through PATH without the template override:
  # argv[0] is then just "folio", which must still resolve the enclosing .app.
  bundle="$ACCEPT_WORK/Folio.app/Contents"
  mkdir -p "$bundle/Resources/bin" "$ACCEPT_WORK/path" "$ACCEPT_WORK/graph-root"
  cp "$ACCEPT_WORK/folio" "$bundle/Resources/bin/folio"
  cp "$ACCEPT_ROOT/Resources/graph-view.html" "$bundle/Resources/graph-view.html"
  plutil -create xml1 "$bundle/Info.plist"
  plutil -insert CFBundleShortVersionString -string 9.8.7 "$bundle/Info.plist"
  plutil -insert CFBundleVersion -string 65 "$bundle/Info.plist"
  ln -s "$bundle/Resources/bin/folio" "$ACCEPT_WORK/path/folio"
  printf '# Probe\n' > "$ACCEPT_WORK/graph-root/probe.md"
  printf '{"roots": []}\n' > "$ACCEPT_WORK/graph-root.json"
  root="$(cd "$ACCEPT_WORK/graph-root" && pwd -P)"
  test "$(cd "$ACCEPT_WORK" && env -u FOLIO_GRAPH_TEMPLATE PATH="$ACCEPT_WORK/path:/usr/bin:/bin" folio --version)" = "folio 9.8.7 (65)"
  (cd "$ACCEPT_WORK" && env -u FOLIO_GRAPH_TEMPLATE PATH="$ACCEPT_WORK/path:/usr/bin:/bin" folio graph "$root" -n --config "$ACCEPT_WORK/graph-root.json" >/dev/null)
  grep -q 'folio-folder-graph-v1' "$root/知识图谱.html"
  echo "PASS PATH-invoked installed layout reports bundle version and finds graph template"
fi
if [ "${1:-functionality}" = recovery ]; then
  xcrun swiftc -parse-as-library Sources/IndexEngine.swift Tests/IndexEngineTests.swift -o "$ACCEPT_WORK/index-recovery"
  "$ACCEPT_WORK/index-recovery"
fi
