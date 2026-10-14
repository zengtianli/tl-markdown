#!/usr/bin/env python3
"""Real Release App, private simulator state, detached UIKit actions and shared lifecycle.

--build uses the original build.sh under sim_lane's lock. Acceptance never substitutes
a host Swift executable for the mobile App. --app/--receipt select a verified candidate;
the default reads the existing build receipts, and does not claim a phone installation.
"""
import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
HQ = Path.home() / 'Dev/tools/dev/lib/tools/macapp/ios'
sys.path.insert(0, str(HQ))
import sim_lane as lane


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def artifact_files(app):
    files = {}
    for path in sorted(app.rglob('*')):
        if path.is_symlink():
            raise ValueError('Unexpected symlink in mobile candidate: ' + str(path))
        if path.is_file():
            files[str(path.relative_to(app))] = sha(path)
    return files


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


@contextmanager
def build_environment():
    fields = ['SOP_REPO', 'SOP_OUT_DIR', 'SOP_CONFIG', 'FOLIO_FAMILY_ROOT']
    saved = {key: os.environ.pop(key) for key in fields if key in os.environ}
    os.environ['FOLIO_FAMILY_ROOT'] = str(ROOT.parents[1])
    try:
        yield
    finally:
        os.environ.pop('FOLIO_FAMILY_ROOT', None)
        os.environ.update(saved)


def build(platform):
    locks = tuple(lane.lock_chain('folio-product-basics-build-' + platform))
    try:
        lane.acquire(locks, None, 0, 0, lane.max_load_default())
        with build_environment():
            result = subprocess.run(['bash', str(ROOT / 'scripts/build.sh'), platform], cwd=ROOT,
                                    text=True, capture_output=True, timeout=900)
        print(result.stderr[-5000:], flush=True)
        if result.returncode:
            raise RuntimeError(result.stdout[-3000:] or result.stderr[-3000:])
        receipt = ROOT / 'build/product-basics' / (platform + '-build.json')
        record = json.loads(result.stdout)
        record['product_basics_artifact_files'] = artifact_files(Path(record['app_path']))
        write(receipt, record)
        return receipt
    finally:
        for lock in reversed(locks):
            if lock.held:
                lock.release()


def exercise(platform, receipt, selected_app, spec, run):
    with build_environment():
        built = lane.reuse_build(receipt, 'folio', ROOT, platform, 'FolioMobile', 'Release', False)
    app = Path(built['app_path'])
    if selected_app and selected_app.resolve() != app.resolve():
        raise ValueError('--app must be the original receipt-bound mobile artifact')
    if built.get('product_basics_artifact_files') != artifact_files(app):
        raise ValueError('Candidate bundle resources differ from the actual build receipt')
    destination = run / platform
    destination.mkdir(parents=True)
    shutil.copy2(receipt, destination / 'build-receipt.json')
    token = uuid.uuid4().hex
    device = lane.ensure_device(platform, name='Folio Basics ' + platform)
    observation = {'subject': 'candidate', 'environment': 'simulator', 'platform': platform,
                   'device': device, 'app': str(app), 'receipt': str(receipt), 'receipt_sha256': sha(receipt),
                   'source_sha256': built['reuse']['input_sha256'], 'executable_sha256': built['executable_sha256'],
                   'bundle_id': built['bundle_id'], 'version': built['version'], 'build': built['build']}
    checks, phases = {}, {}
    print('Runtime ' + platform + ': ' + device['udid'], flush=True)
    with lane.Session(platform, device['udid'], label='Folio product basics ' + platform,
                      lock_wait=0, load_wait=0, boot_timeout=180) as session:
        # Only this dedicated simulator is addressed; Simulator.app is never launched.
        session.install(app)
        container = Path(lane.simctl('get_app_container', device['udid'], built['bundle_id'], 'data').stdout.strip())
        state = container / 'Library/Application Support' / ('FolioBasics-' + token)
        try:
            for phase in ('exercise', 'readback'):
                session.terminate(built['bundle_id'])
                result = lane.simctl('launch', device['udid'], built['bundle_id'], '--product-basics-self-test',
                                     token, phase, spec['digest'], timeout=30)
                observation[phase + '_launch'] = result.stdout.strip()
                output = state / (phase + '.json')
                deadline = time.monotonic() + 120
                while not output.is_file() and time.monotonic() < deadline:
                    time.sleep(0.25)
                if not output.is_file():
                    raise RuntimeError(platform + ' real App did not finish ' + phase + ' within 120 seconds')
                raw = json.loads(output.read_text())
                if raw.get('app_id') != 'folio' or raw.get('spec_digest') != spec['digest'] or raw.get('bundle_id') != built['bundle_id']:
                    raise ValueError('Actual App result identity mismatch')
                shutil.copy2(output, destination / (phase + '.json'))
                phases[phase] = {'path': str((destination / (phase + '.json')).relative_to(ROOT)),
                                 'sha256': sha(output), 'pid': observation[phase + '_launch']}
                checks.update(raw['checks'])
                print(platform + ' ' + phase + ': ' + json.dumps(raw.get('failed')) + ' ' + json.dumps(raw.get('facts', {}).get('error', '')), flush=True)
                if raw.get('failed'):
                    break
            image = state / 'settings.png'
            if image.is_file():
                shutil.copy2(image, destination / 'settings.png')
            observation['phases'] = phases
        finally:
            session.terminate(built['bundle_id'])
            if (state / 'update-before.json').is_file():
                lane.simctl('launch', device['udid'], built['bundle_id'], '--product-basics-self-test',
                            token, 'cleanup', spec['digest'], timeout=30)
                cleanup = state / 'cleanup.json'
                deadline = time.monotonic() + 30
                while not cleanup.is_file() and time.monotonic() < deadline:
                    time.sleep(0.25)
                if cleanup.is_file():
                    cleanup_record = json.loads(cleanup.read_text())
                    checks.update(cleanup_record['checks'])
                    shutil.copy2(cleanup, destination / 'cleanup.json')
                else:
                    checks['settings.cleanup_completed'] = False
                session.terminate(built['bundle_id'])
            # Dedicated sandbox test domain only. Do not uninstall or erase a device.
            if state.is_dir():
                shutil.rmtree(state)
    checks['settings.simulator_shutdown'] = lane.device_info(device['udid'])['state'] == 'Shutdown'
    checks['settings.private_state_removed'] = not state.exists()
    observation['checks'] = checks
    write(destination / 'observation.json', observation)
    return observation


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true', help='only build current Release candidates via original entry')
    parser.add_argument('--app', type=Path)
    parser.add_argument('--receipt', type=Path, default=os.environ.get('SOP_FOLIO_BASICS_RECEIPT'))
    parser.add_argument('--vision-receipt', type=Path, default=os.environ.get('SOP_FOLIO_BASICS_VISION_RECEIPT'))
    parser.add_argument('--platforms', default='iphone,ipad,vision')
    parser.add_argument('--inspect', action='store_true', help='read original product-process evidence and hashes; does not run App')
    args = parser.parse_args()
    platforms = args.platforms.split(',')
    if not platforms or any(p not in ('iphone', 'ipad', 'vision') for p in platforms):
        parser.error('--platforms must contain iphone,ipad,vision')
    if args.build:
        for platform in ('iphone', 'vision'):
            if platform in platforms or platform == 'iphone' and 'ipad' in platforms:
                print('Receipt: ' + str(build(platform)), flush=True)
        return 0
    if args.inspect:
        record = ROOT / 'perf/acceptance/product_basics.detail.json'
        detail = json.loads(record.read_text())
        valid = all(sha(ROOT / row['evidence']) == row['evidence_sha256'] for row in detail['features'].values())
        print(json.dumps({'detail': detail, 'evidence_hashes_match': valid}, ensure_ascii=False, indent=2))
        return 0 if valid else 1
    spec = json.loads(os.environ['SOP_PRODUCT_BASICS_SPEC'])
    out = Path(os.environ['SOP_OUT_DIR']).resolve()
    if not out.is_relative_to(ROOT):
        raise ValueError('Evidence output must belong to this component')
    run = out / ('product-basics-mobile-' + uuid.uuid4().hex)
    run.mkdir(parents=True)
    observations, error, code = [], None, 0
    try:
        receipts = {}
        for build_platform in ('iphone', 'vision'):
            if not any(p == build_platform or p == 'ipad' and build_platform == 'iphone' for p in platforms):
                continue
            explicit = args.vision_receipt if build_platform == 'vision' else args.receipt
            receipt = explicit or ROOT / 'build/product-basics' / (build_platform + '-build.json')
            if not explicit and not args.app:
                try:
                    with build_environment():
                        cached = lane.reuse_build(receipt, 'folio', ROOT, build_platform, 'FolioMobile', 'Release', False)
                    if cached.get('product_basics_artifact_files') != artifact_files(Path(cached['app_path'])):
                        raise lane.LaneError('Full bundle binding is absent or changed')
                except (lane.LaneError, OSError, ValueError):
                    print('Current candidate required: ' + build_platform, flush=True)
                    receipt = build(build_platform)
            receipts[build_platform] = receipt.resolve()
        for platform in platforms:
            receipt = receipts['vision' if platform == 'vision' else 'iphone']
            observations.append(exercise(platform, receipt, args.app, spec, run))
            if any(v is not True for v in observations[-1]['checks'].values()):
                code = 1
                break
    except lane.Busy as exc:
        print('Deferred by original simulator lane: ' + str(exc), flush=True)
        return 75
    except Exception as exc:
        error, code = str(exc), 1
        print(error, flush=True)
    required = [check for row in spec['features'].values() for check in row['required_checks']]
    checks = {key: len(observations) == len(platforms) and all(row['checks'].get(key) is True for row in observations) for key in required}
    for row in observations:
        for key, value in row['checks'].items():
            checks[key.split('.')[0] + '.' + row['platform'] + '.' + key.split('.', 1)[1]] = value
    checks['settings.all_declared_mobile_platforms'] = set(platforms) == {'iphone', 'ipad', 'vision'} and len(observations) == 3
    raw = {'schema_version': 1, 'app_id': 'folio', 'spec_digest': spec['digest'], 'subject': 'candidate',
           'checks': checks, 'observations': observations, 'error': error,
           'boundaries': ['No physical phone installation or publication', 'Isolated production sync engine; Apple cross-device KVS not tested',
                          'Real App Store HTTPS check plus actual isolated test-feed I/O in the shared checker; store action captured without opening another app']}
    original = run / 'raw.json'
    write(original, raw)
    detail = {'schema_version': 1, 'app_id': 'folio', 'spec_digest': spec['digest'], 'features': {}}
    for feature, row in spec['features'].items():
        selected = [key for key in checks if key.startswith(feature + '.')]
        passed = all(checks.get(key) is True for key in row['required_checks']) and all(checks[key] is True for key in selected)
        detail['features'][feature] = {'result': 'passed' if passed else 'failed', 'method': 'ui_automation',
             'evidence': str(original.relative_to(ROOT)), 'evidence_sha256': sha(original), 'checks': selected}
    write(out / 'product_basics.detail.json', detail)
    print(json.dumps({'raw': str(original.relative_to(ROOT)), 'failed': [key for key, value in checks.items() if value is not True], 'error': error}, ensure_ascii=False), flush=True)
    return 0 if code == 0 and all(checks.values()) else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except lane.Busy as error:
        print(str(error), flush=True)
        sys.exit(75)
