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
  APP="${FOLIO_DERIVED_DATA:-$ACCEPT_ROOT/build/DerivedData}/Build/Products/Release/TLMarkdown.app"
  RUN_PYTHON=/Users/tianli/Dev/.venv/bin/python
  # The fixed producer owns cache selection, including when an automatic worker
  # claimed the job before a terminal worker's optional environment arrived.
  if "$RUN_PYTHON" - "$ACCEPT_ROOT" "$APP" > "$ACCEPT_WORK/cache-check.json" <<'CACHE'
import hashlib, json, pathlib, sys
import yaml

def cache_check(root, package, verifier, receipt_path=None):
    root = pathlib.Path(root).resolve()
    try:
        meta = yaml.safe_load((root / 'project.yaml').read_text())
        app = {'id': 'folio-mac', 'repo': root, 'form': 'mac',
               'bundle_id': meta['bundle_id'], 'sop': meta['sop']}
        receipt = pathlib.Path(receipt_path) if receipt_path else root / 'perf/build-receipt.json'
        data = receipt.read_bytes()
        if not json.loads(data).get('artifact', {}).get('icon'):
            raise ValueError('Current Release receipt must declare its actual icon')
        valid, reason = verifier(app, pathlib.Path(package).resolve(), receipt_path)
        return {'valid': bool(valid), 'reason': reason, 'receipt': str(receipt),
                'receipt_sha256': hashlib.sha256(data).hexdigest()}
    except (OSError, ValueError) as error:
        return {'valid': False, 'reason': str(error)}

root = pathlib.Path(sys.argv[1]).resolve()
sys.path.insert(0, str(root.parent / 'chapter/engine'))
import app_sop
check = cache_check(root, sys.argv[2], app_sop.verify_build_receipt,
                    root / 'build/accept/native_ui/build-receipt.json')
if not check['valid']:
    check = cache_check(root, sys.argv[2], app_sop.verify_build_receipt)
print(json.dumps(check, ensure_ascii=False))
sys.exit(0 if check['valid'] else 1)
CACHE
  then
    # The same full verifier runs again before and after the actual self-test.
    SOP_FOLIO_REUSE_RECEIPT="$($RUN_PYTHON -c 'import json,sys; print(json.load(open(sys.argv[1]))["receipt"])' "$ACCEPT_WORK/cache-check.json")"
  else
    # Only a genuinely missing/stale package requires the normal build pipeline.
    "$RUN_PYTHON" - "$ACCEPT_ROOT" "$APP" "$ACCEPT_WORK/build.log" > "$ACCEPT_WORK/build-receipt-command.json" <<'BUILD'
import json, pathlib, shlex, sys
import yaml
root = pathlib.Path(sys.argv[1]).resolve()
sys.path.insert(0, str(root.parent / 'chapter/engine'))
import app_sop
meta = yaml.safe_load((root / 'project.yaml').read_text())
app = {'id': 'folio-mac', 'repo': root, 'form': 'mac',
       'bundle_id': meta['bundle_id'], 'sop': meta['sop']}
receipt = app_sop.build_receipt(app, pathlib.Path(sys.argv[2]), meta['sop']['source'],
                              'bash build.sh --build-only > ' + shlex.quote(sys.argv[3]) + ' 2>&1',
                              output_path=root / 'build/accept/native_ui/build-receipt.json')
print(json.dumps(receipt, ensure_ascii=False))
BUILD
    SOP_FOLIO_REUSE_RECEIPT="$ACCEPT_ROOT/build/accept/native_ui/build-receipt.json"
  fi
  export SOP_FOLIO_REUSE_APP="$APP" SOP_FOLIO_REUSE_RECEIPT
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
        receipt_path = pathlib.Path(os.environ.get('SOP_FOLIO_REUSE_RECEIPT', root / 'perf/build-receipt.json'))
        receipt_bytes = receipt_path.read_bytes()
        receipt = json.loads(receipt_bytes)
        if app_path.suffix != '.app' or not receipt.get('artifact', {}).get('icon'):
            raise ValueError('Reuse requires a .app and an explicit icon-bound build receipt')
        valid, detail = app_sop.verify_build_receipt(app, app_path, receipt_path)
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
        cache_file = pathlib.Path(os.environ['ACCEPT_WORK']) / 'cache-check.json'
        if cache_file.exists():
            facts['canonical_cache_check'] = json.loads(cache_file.read_text())
            facts['build_performed'] = not facts['canonical_cache_check']['valid']
            facts['selection'] = 'canonical_auto'
            if facts['build_performed']:
                facts['mode'] = 'verified_new_build'
        else:
            facts.update(selection='explicit', build_performed=False)
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
    cache_file = pathlib.Path(os.environ['ACCEPT_WORK']) / 'cache-check.json'
    if cache_file.exists():
        data['canonical_cache_check'] = json.loads(cache_file.read_text())
        data['build_performed'] = not data['canonical_cache_check']['valid']
    if reuse:
        valid, detail = app_sop.verify_build_receipt(app, app_path, receipt_path)
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
