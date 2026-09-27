#!/bin/bash
set -euo pipefail
ACCEPT_NAME=native_ui
source "$(dirname "$0")/_common.sh"
# Reuse the normal build pipeline; it does not install or launch windows.
bash "$ACCEPT_ROOT/build.sh" --build-only > "$ACCEPT_WORK/build.log" 2>&1 || { tail -80 "$ACCEPT_WORK/build.log"; exit 1; }
APP="${FOLIO_DERIVED_DATA:-$ACCEPT_ROOT/build/DerivedData}/Build/Products/Release/TLMarkdown.app"
python3 - "$APP/Contents/MacOS/TLMarkdown" "$SOP_OUT_DIR/native_ui.result.json" <<'PY'
import json, pathlib, subprocess, sys
result = subprocess.run([sys.argv[1], '--ui-self-test'], capture_output=True, text=True, timeout=45)
if result.returncode:
    sys.stderr.write(result.stderr)
    sys.exit(result.returncode)
data = json.loads(result.stdout)
assert data.get('ok') and data.get('checks') and all(data['checks'].values()), data
pathlib.Path(sys.argv[2]).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(data, ensure_ascii=False))
PY
accept_detail "进程内离屏真实 ContentView / EditorSurface：源码切换、新建与标签切换、重新载入、关闭与空态；截图尺寸/字节断言；全程无可见窗口、激活或输入合成。"
