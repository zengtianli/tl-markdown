#!/usr/bin/env python3
"""Folio one ordinary Release production-demo launch/capture; default dry, never builds.
Launch scope only: Store uses a separate new iPhone17ProMax ownership plan.
"""
import argparse
import datetime
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

sys.dont_write_bytecode = True
QA_DIR = Path(__file__).resolve().parent
ROOT = QA_DIR
RESOURCE_ROOT = QA_DIR
sys.path.insert(0, str(RESOURCE_ROOT))
import guard
guard.reject_environment()  # before importing resource -> sim_lane
spec = importlib.util.spec_from_file_location('folio_resource_recipe', RESOURCE_ROOT / 'resource.py')
recipe = importlib.util.module_from_spec(spec); sys.modules[spec.name] = recipe
exec(compile((RESOURCE_ROOT / 'resource.py').read_bytes(), str(RESOURCE_ROOT / 'resource.py'), 'exec'), recipe.__dict__)

SHOTS = Path('/Users/tianli/Dev/tools/dev/lib/tools/macapp/ios/store_shots.py')
lane, sop, process = recipe.lane, recipe.sop, recipe.original_process
sha = recipe.sha
SPAWNING = False
PENDING_INTERRUPT = None

def inputs(platform):
    return {'production': recipe.inputs(platform), 'wrapper_sha256': sha(__file__),
            'store_shots': {'path': str(SHOTS), 'sha256': sha(SHOTS)},
            'device_request': {'udid': recipe.PHONE} if platform == 'iphone' else {'name': recipe.NAMES[platform]},
            'observation': 'one original Session.install/baseline/launch; copy original returned frame only',
            'launch_args': ['-folio-demo'], 'no_build': True, 'no_rotation': True}

def worker(platform, destination, before):
    owner = int(os.environ.get('FOLIO_RESOURCE_OBSERVER_OWNER_PID', '0'))
    if owner != os.getppid() or lane.pid_started(owner) != os.environ.get('FOLIO_RESOURCE_OBSERVER_OWNER_STARTED'):
        raise RuntimeError('worker controller PID/start differs')
    if not destination.resolve().is_relative_to((ROOT / 'runs').resolve()):
        raise RuntimeError('worker path outside own recipe tree')
    canonical = recipe.module('folio_thin_canonical_platform_measure', recipe.MEASURE)
    shots = recipe.module('folio_thin_canonical_store_shots', SHOTS)
    cfg = sop.load_apps('folio')[0]['sop']['platforms'][platform]
    selection = argparse.Namespace(udid=recipe.PHONE if platform == 'iphone' else None,
                                   name=recipe.NAMES.get(platform))
    info = lane.bundle_info(Path(before['production']['app_path']))
    with recipe.observation_context(platform, destination, before['production']) as (journal, observations):
        recipe.ATTEMPT.require('device selection')
        actual_device = canonical.measurement_device(platform, cfg, selection)
        journal.selected(actual_device)
        with lane.Session(platform, actual_device['udid'], label='Folio thin launch ' + platform,
                          lock_wait=0, load_wait=0) as session:
            installed = session.install(Path(before['production']['app_path']))
            baseline, baseline_stable = session.baseline()
            returned = session.launch(info['bundle_id'], ['-folio-demo'], 'auto', 60, baseline, info['executable'])
            if len(observations) != 1:
                raise RuntimeError('one actual Markdown launch observation required')
            observed = observations[0]
            frame = Path(observed['frame'])
            dimensions = shots.png_size(frame)
            dimension_problems = shots.validate(platform, [frame])
            capture = {'actual_device': actual_device, 'install_seconds': installed,
                       'baseline_stable': baseline_stable, 'launch': observed,
                       'dimensions': dimensions, 'display_type': shots.display_type(platform, dimensions),
                       'store_validation_errors': dimension_problems, 'store_shots_sha256': sha(SHOTS),
                       'scope': 'one ordinary Release production-demo Markdown launch and original frame; no Files/OS Scene/user edits/WC/resources/upload claim',
                       'no_rotation': 'no helper build, no orientation manipulation; actual image dimensions only'}
            guard.atomic_json(destination / 'capture.json', capture)
            session.terminate(info['bundle_id'])
        final_device = lane.device_info(actual_device['udid'])
        capture['state_after_original_session'] = final_device
        guard.atomic_json(destination / 'capture.json', capture)
        if final_device.get('state') != 'Shutdown':
            raise RuntimeError('original Session did not leave the dedicated device Shutdown')
    return 0

def main():
    global SPAWNING, PENDING_INTERRUPT, ROOT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', required=True, choices=['iphone', 'ipad', 'vision'])
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--slot-seconds', type=int, default=600)
    parser.add_argument('--workdir', required=True, type=Path)
    parser.add_argument('--worker', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    attempt = recipe.attempt_budget.Attempt(args.slot_seconds, worker=bool(args.worker)); recipe.ATTEMPT = attempt
    ROOT = args.workdir.resolve(); recipe.ROOT = ROOT
    if ROOT.is_relative_to(recipe.REPO.parents[1]): raise RuntimeError('workdir must be outside Folio source family')
    if not 1 <= args.slot_seconds <= 600:
        raise RuntimeError('bounded slot must be 1..600 seconds')
    before = inputs(args.platform)
    expected = json.loads((ROOT / 'thin-binding.json').read_text())['platforms'][args.platform]
    if before != expected:
        raise RuntimeError('ordinary SDK/source/wrapper/store ABI binding changed; no rebind')
    if args.worker:
        return worker(args.platform, args.worker, before)
    if not args.execute:
        print(json.dumps({'status': 'dry-only-no-device', 'inputs': before,
                          'execute_requires': 'new Root sole native grant; Chapter global NB + original canonical Session lock/load wait0',
                          'stop_rule': 'single attempt, no retry, failure stops caller queue',
                          'cleanup': 'own PID/start worker end, same canonical gate, actual own UDID Shutdown + actual directory lock terminal before global release',
                          'store_scope': 'launch phase only, actual dimensions/alpha reported without claiming Store. Separate Store phase requires new dedicated iPhone17ProMax and actual creation/owner receipt; no resizing.',
                          'not_proven': ['five-launch median', 'idle resources', 'complete WebKit helpers', 'real user Files/Scene interaction', 'complete App Store submission']}, ensure_ascii=False, indent=2))
        return 0
    if args.platform != 'iphone':
        raise RuntimeError('this frozen phone launch entry does not claim iPad/Vision creation; use independent owned creation entry')
    if process.gui_processes():
        raise RuntimeError('Simulator/AppSimulator GUI present; no device operation')
    destination = ROOT / 'runs' / (datetime.datetime.now().astimezone().strftime('%Y%m%d-%H%M%S') + '-' + args.platform + '-' + str(os.getpid()))
    destination.mkdir(parents=True, exist_ok=False)
    log = destination / 'launch.log'
    record = {'status': 'not-passed', 'before': before, 'started_at': datetime.datetime.now().astimezone().isoformat()}
    errors, observed = [], {}
    child = None; identity = ''; held = False
    controller = {'pid': os.getpid(), 'pid_started': lane.pid_started(os.getpid())}
    global_lock = (sop.STATE_DIR / 'lock').open('a')
    try:
        attempt.require('Chapter NB admission')
        fcntl.flock(global_lock, fcntl.LOCK_EX | fcntl.LOCK_NB); held = True
        with log.open('w') as output:
            PENDING_INTERRUPT = None
            SPAWNING = True
            try:
                child = subprocess.Popen([recipe.PYTHON, str(Path(__file__).resolve()), '--platform', args.platform, '--worker', str(destination), '--workdir', str(ROOT), '--slot-seconds', str(args.slot_seconds)],
                    stdout=output, stderr=subprocess.STDOUT, start_new_session=True,
                    env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1',
                         'FOLIO_RESOURCE_OBSERVER_OWNER_PID': str(controller['pid']),
                         'FOLIO_RESOURCE_OBSERVER_OWNER_STARTED': controller['pid_started'], **attempt.environment()})
                identity = lane.pid_started(child.pid); observed[child.pid] = identity
            finally:
                SPAWNING = False
            if PENDING_INTERRUPT is not None:
                signum, PENDING_INTERRUPT = PENDING_INTERRUPT, None
                raise InterruptedError('signal during child registration ' + str(signum))
            while child.poll() is None:
                for pid in process.group_members(child.pid): observed.setdefault(pid, lane.pid_started(pid))
                if process.gui_processes(): raise RuntimeError('Simulator/AppSimulator GUI appeared')
                if attempt.expired(): record['budget_crossed_during_existing_child'] = True
                time.sleep(.25)
        record['exit_code'] = child.returncode
        if process.gui_processes(): raise RuntimeError('Simulator/AppSimulator GUI appeared at worker exit')
        if child.returncode: raise RuntimeError('one thin operation failed: ' + str(child.returncode))
        capture = json.loads((destination / 'capture.json').read_text())
        record['capture'] = capture; record['capture_sha256'] = sha(destination / 'capture.json')
        record['status'] = 'candidate-launch-capture-cleanup-pending'
    except BaseException as error: errors.append(type(error).__name__ + ': ' + str(error))
    finally:
        with guard.cleanup_signals_blocked():
            try:
                record['cleanup'] = guard.cleanup(lane, process, child, identity, observed, destination, controller) if held else {'clear': True, 'device': 'global busy; worker not started'}
                record['cleanup']['chapter_global_held_during_observation'] = held
                guard.atomic_json(destination / 'cleanup.json', record['cleanup'])
                record['cleanup_sha256'] = sha(destination / 'cleanup.json')
                if not record['cleanup']['clear']: errors.append('own terminal cleanup incomplete: ' + json.dumps(record['cleanup']['errors']))
            except BaseException as error: errors.append('bounded own cleanup: ' + str(error))
            finally: global_lock.close()
        try:
            record['after'] = inputs(args.platform); record['input_stable'] = record['after'] == before
        except BaseException as error: errors.append('final readonly inputs: ' + str(error))
        if not record.get('input_stable'): errors.append('inputs changed')
        if (destination / 'capture.json').exists():
            record['capture_sha256'] = sha(destination / 'capture.json')
        record.update(errors=errors, process_group=observed, log=str(log), log_sha256=sha(log) if log.exists() else None,
                      finished_at=datetime.datetime.now().astimezone().isoformat())
        attempt.finalize(record, errors, 'candidate-launch-capture-cleanup-pending', 'passed-single-release-markdown-launch-capture-scope-only')
        guard.atomic_json(destination / 'result.json', record)
        print(json.dumps(record, ensure_ascii=False, indent=2))
    return 0 if record['status'].startswith('passed-') else 1

def interrupted(signum, frame):
    global PENDING_INTERRUPT
    if SPAWNING:
        PENDING_INTERRUPT = signum
        return  # no process signal mask; child identity registers before same cleanup
    raise InterruptedError('external signal ' + str(signum))
if __name__ == '__main__':
    signal.signal(signal.SIGTERM, interrupted); signal.signal(signal.SIGINT, interrupted)
    sys.exit(main())
