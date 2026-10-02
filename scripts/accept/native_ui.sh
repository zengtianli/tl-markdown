#!/bin/bash
set -euo pipefail
ACCEPT_NAME=native_ui
source "$(dirname "$0")/_common.sh"
# Explicit reuse never falls back to building a missing/stale package.
if [ "${SOP_FOLIO_REUSE_APP+x}" = x ]; then
  [ -n "$SOP_FOLIO_REUSE_APP" ] || { echo "SOP_FOLIO_REUSE_APP must name a receipt-bound .app" >&2; exit 64; }
  APP="$SOP_FOLIO_REUSE_APP"
  RUN_PYTHON=/Users/tianli/Dev/.venv/bin/python
else
  # Preserve the normal build pipeline; it does not install or launch windows.
  bash "$ACCEPT_ROOT/build.sh" --build-only > "$ACCEPT_WORK/build.log" 2>&1 || { tail -80 "$ACCEPT_WORK/build.log"; exit 1; }
  APP="${FOLIO_DERIVED_DATA:-$ACCEPT_ROOT/build/DerivedData}/Build/Products/Release/TLMarkdown.app"
  RUN_PYTHON=python3
fi
"$RUN_PYTHON" - "$APP" "$SOP_OUT_DIR/native_ui.result.json" <<'PY'
import hashlib, json, os, pathlib, shutil, subprocess, sys

app_path = pathlib.Path(sys.argv[1]).resolve(strict=True)
reuse = 'SOP_FOLIO_REUSE_APP' in os.environ
clone_work = None
proc = None
facts = None
try:
    if reuse:
        import yaml
        root = pathlib.Path(os.environ['ACCEPT_ROOT']).resolve()
        tools = root.parents[1] / 'Dev/tools/dev/lib/tools'
        # _common.sh already isolated HOME; locate shared code from the known
        # product owner rather than importing another user's/fake home tree.
        sys.path[:0] = [str(root.parent / 'chapter/engine'), str(tools / 'macapp'),
                        str(tools / 'report'), str(tools / 'macapp/ios')]
        import app_sop
        import sim_lane
        meta = yaml.safe_load((root / 'project.yaml').read_text())
        app = {'id': 'folio-mac', 'repo': root, 'form': 'mac',
               'bundle_id': meta['bundle_id'], 'sop': meta['sop']}
        receipt_path = root / 'perf/build-receipt.json'
        receipt_bytes = receipt_path.read_bytes()
        receipt = json.loads(receipt_bytes)
        if app_path.suffix != '.app' or not receipt.get('artifact', {}).get('icon'):
            raise ValueError('Reuse requires a .app and an explicit icon-bound build receipt')
        valid, detail = app_sop.verify_build_receipt(app, app_path)
        if not valid:
            raise ValueError('Cannot reuse Folio: ' + detail)
        source = app_sop.app_source_snapshot(app, receipt['source']['input_globs'])
        original = app_sop.artifact_snapshot(app_path)
        owned_copy_root = pathlib.Path(os.environ['ACCEPT_WORK']) / 'uielement-copy'
        owned_copy_root.mkdir()
        clone_work = owned_copy_root
        clone = sim_lane.uielement_copy(app_path, clone_work)
        run_info = sim_lane.bundle_info(clone)
        if run_info['bundle_id'] == original['bundle_id'] or run_info['info'].get('LSUIElement') is not True:
            raise ValueError('Shared test copy is not an isolated UIElement')
        executable = pathlib.Path(run_info['executable'])
        facts = {'mode': 'verified_reuse', 'original_app': str(app_path),
                 'receipt': str(receipt_path),
                 'receipt_sha256': hashlib.sha256(receipt_bytes).hexdigest(),
                 'receipt_source': receipt['source'], 'current_source': source,
                 'original_artifact': original, 'clone_app': str(clone),
                 'run_bundle_id': run_info['bundle_id'], 'LSUIElement': True,
                 'clone_executable_sha256': hashlib.sha256(executable.read_bytes()).hexdigest(),
                 'clone_plist_sha256': hashlib.sha256((clone / 'Contents/Info.plist').read_bytes()).hexdigest(),
                 'shared_copy_api': 'sim_lane.uielement_copy',
                 'shared_tool_sha256': hashlib.sha256(pathlib.Path(sim_lane.__file__).read_bytes()).hexdigest(),
                 'state_directory': os.environ['TL_MARKDOWN_STATE_DIR']}
        facts_path = pathlib.Path(os.environ['SOP_OUT_DIR']) / 'native_ui.reuse.json'
        facts_path.write_text(json.dumps(facts, ensure_ascii=False, indent=2) + '\n')
    else:
        executable = app_path / 'Contents/MacOS/TLMarkdown'
    proc = subprocess.Popen([str(executable), '--ui-self-test'], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)
    stdout, stderr = proc.communicate(timeout=45)
    if proc.returncode:
        sys.stderr.write(stderr)
        raise SystemExit(proc.returncode)
    data = json.loads(stdout)
    assert data.get('ok') and data.get('checks') and all(data['checks'].values()), data
    if reuse:
        valid, detail = app_sop.verify_build_receipt(app, app_path)
        after_source = app_sop.app_source_snapshot(app, receipt['source']['input_globs'])
        if (not valid or after_source['sha256'] != source['sha256']
                or receipt_path.read_bytes() != receipt_bytes
                or app_sop.artifact_snapshot(app_path) != original):
            raise ValueError('Receipt/source/original package changed during self-test: ' + detail)
        facts.update(pid=proc.pid, exit_code=proc.returncode, input_stable=True)
        data['reuse'] = facts
    pathlib.Path(sys.argv[2]).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(data, ensure_ascii=False))
finally:
    # Only our direct child PID and the copy in our mktemp ACCEPT_WORK are owned.
    try:
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.wait(timeout=5)
    finally:
        if clone_work is not None:
            shutil.rmtree(clone_work)
        if facts is not None:
            facts.update(clone_removed=not clone_work.exists(),
                         pid=proc.pid if proc is not None else None,
                         exit_code=proc.returncode if proc is not None else None)
            facts_path.write_text(json.dumps(facts, ensure_ascii=False, indent=2) + '\n')
PY
accept_detail "进程内离屏真实 ContentView / EditorSurface / 设置页：源码切换、标签、刷新与关闭；无索引空态、文件夹增删与更新索引、查询行号、生成目录图谱菜单代码路径及防覆盖；六张截图尺寸/字节断言；全程无可见窗口、激活或输入合成。"
