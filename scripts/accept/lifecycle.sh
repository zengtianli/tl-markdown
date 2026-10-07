#!/bin/bash
# Folio's「配置与更新」command checks against a running window: the built app runs --lifecycle-self-test (the real
# store and the production wiring, offscreen: no window, no Dock icon, no activation, no input), and the real
# folio command from the same bundle is run against it as child processes.
#
# Usage: bash scripts/accept/lifecycle.sh [path/to/TLMarkdown.app]   (default: build/DerivedData release product)
# Does not build. The app is run as a UIElement copy with its own bundle id (the shared sim_lane.uielement_copy,
# as native_ui.sh does), so the owner's Folio and its LaunchServices record are not involved.
# Everything it touches is inside build/accept/lifecycle/run.*: the state folder, the shared layer's support folder
# and its "cloud" folder. The switch lives in a throwaway named preference domain (test.tianli.folio.<id>), which
# is deleted afterwards. HOME stays the real one on purpose: the named domain has to go through the preferences
# daemon to stay in step between the running window and the commands.
# Result: build/accept/lifecycle/lifecycle.json (and lifecycle-window.png, the offscreen render of the shared window).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="${1:-$ROOT/build/DerivedData/Build/Products/Release/TLMarkdown.app}"
OUT="$ROOT/build/accept/lifecycle"
[ -x "$APP/Contents/MacOS/TLMarkdown" ] && [ -x "$APP/Contents/Resources/bin/folio" ] || {
  echo "没有构建产物：$APP（先 bash build.sh --build-only）" >&2; exit 64; }
mkdir -p "$OUT"
WORK="$(mktemp -d "$OUT/run.XXXXXX")"
exec /Users/tianli/Dev/.venv/bin/python - "$APP" "$WORK" "$OUT" <<'PY'
import json, os, pathlib, plistlib, shutil, subprocess, sys, uuid

app, work, out = (pathlib.Path(p).resolve() for p in sys.argv[1:4])
sys.path.insert(0, str(pathlib.Path.home() / 'Dev/tools/dev/lib/tools/macapp/ios'))
import sim_lane

suite = 'test.tianli.folio.' + uuid.uuid4().hex
proc, status, result = None, 1, {}
try:
    copy = sim_lane.uielement_copy(app, work / 'copy')
    info = plistlib.loads((copy / 'Contents/Info.plist').read_bytes())
    assert info.get('LSUIElement') is True and info['CFBundleIdentifier'] != 'cyou.tianli.TLMarkdown', info['CFBundleIdentifier']
    env = {k: v for k, v in os.environ.items()
           if k not in ('TL_MARKDOWN_OPEN', 'TL_MARKDOWN_BENCHMARK', 'MDINDEX_DB', 'APP_LIFECYCLE_FOLLOW_CHANNEL', 'CFFIXED_USER_HOME')}
    env.update(FOLIO_BACKGROUND='1', TL_MARKDOWN_STATE_DIR=str(work / 'state'), APP_LIFECYCLE_SUPPORT_DIR=str(work / 'support'),
               APP_LIFECYCLE_CLOUD_DIR=str(work / 'cloud'), FOLIO_PREFERENCES_SUITE=suite, SOP_OUT_DIR=str(work / 'out'))
    proc = subprocess.Popen([str(copy / 'Contents/MacOS' / info['CFBundleExecutable']), '--lifecycle-self-test'],
                            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    try:
        stdout, stderr = proc.communicate(timeout=240)
    except subprocess.TimeoutExpired:
        proc.kill()
        stdout, stderr = proc.communicate(timeout=10)
        sys.stderr.write('self-test did not finish in 240 s; its progress so far:\n' + stderr[-3000:])
    status = proc.returncode
    try:
        result = json.loads(stdout)
    except ValueError:
        result = {'ok': False, 'error': 'the self-test printed no JSON', 'stdout': stdout[-2000:], 'stderr': stderr[-2000:]}
        status = status or 1
    result.update(app=str(app), run_bundle_id=info['CFBundleIdentifier'], exit_code=proc.returncode)
    if not result.get('ok'):
        result['progress'] = stderr[-4000:]
        sys.stderr.write(stderr[-3000:])
    shot = work / 'out/lifecycle-window.png'
    if shot.is_file():
        shutil.copyfile(shot, out / 'lifecycle-window.png')
finally:
    # Only our direct child and our own folder; the throwaway domain by its exact name.
    if proc is not None and proc.poll() is None:
        proc.kill()
        proc.wait(timeout=5)
    subprocess.run(['/usr/bin/defaults', 'delete', suite], capture_output=True)
    shell = pathlib.Path.home() / 'Library/Preferences' / (suite + '.plist')
    result['preference_domain_removed'] = not shell.exists() or shell.stat().st_size <= 42
    if shell.exists() and shell.stat().st_size <= 42:
        shell.unlink()
    shutil.rmtree(work, ignore_errors=True)
    result['work_removed'] = not work.exists()
    (out / 'lifecycle.json').write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
print(json.dumps({k: result.get(k) for k in ('ok', 'count', 'failed', 'commands_run', 'back_to_back_regressions', 'not_followed',
                                              'preference_domain', 'preference_domain_removed', 'work_removed', 'error')}, ensure_ascii=False))
sys.exit(0 if status == 0 and result.get('ok') else 1)
PY
