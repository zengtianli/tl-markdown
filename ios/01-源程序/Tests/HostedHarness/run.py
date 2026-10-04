#!/usr/bin/env python3
"""One non-UI hosted test-without-building run; never builds or retries."""
import argparse
from contextlib import contextmanager, ExitStack
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import stat
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parent
PACKAGE = ROOT / "iphone"
REPO = Path(__file__).resolve().parents[2]
HARNESS_ROOT = Path(__file__).resolve().parent
SDK_RECEIPT = None
DEADLINE = None
sys.path.insert(0, "/Users/tianli/Dev/tools/dev/lib/tools/macapp/ios")
import sim_lane
sys.path.insert(0, "/Users/tianli/Apps/chapter/engine")
import app_sop

def remaining(maximum):
    seconds = maximum if DEADLINE is None else min(maximum, DEADLINE - time.monotonic())
    if seconds <= 0:
        raise sim_lane.Busy('Hosted operation deadline exhausted; cleanup remains reserved')
    return seconds

def chapter_lock():
    path = app_sop.STATE_DIR / 'lock'
    fields = ['SOP_GLOBAL_LOCK_FD', 'SOP_GLOBAL_LOCK_PID', 'SOP_GLOBAL_LOCK_PID_STARTED']
    if not any(os.environ.get(name) for name in fields):
        handle = path.open('a')
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return handle, {'path': str(path), 'inherited': False, 'pid': os.getpid()}
        except BaseException:
            handle.close()
            raise
    if not all(os.environ.get(name) for name in fields):
        raise ValueError('Incomplete actual Chapter ancestor descriptor identity')
    descriptor, parent = int(os.environ[fields[0]]), int(os.environ[fields[1]])
    started = app_sop.local_process_started(str(parent))
    if descriptor < 3 or started is None or started != float(os.environ[fields[2]]):
        raise ValueError('Chapter ancestor PID/start is not current')
    ancestor, seen = os.getppid(), set()
    while ancestor > 1 and ancestor != parent and ancestor not in seen:
        seen.add(ancestor)
        answer = subprocess.run(['ps', '-o', 'ppid=', '-p', str(ancestor)], capture_output=True,
                                text=True, check=True, timeout=5).stdout.strip()
        ancestor = int(answer or 0)
    if ancestor != parent:
        raise ValueError('Chapter descriptor owner is not a real ancestor')
    actual, canonical = os.fstat(descriptor), path.stat()
    if (not stat.S_ISREG(actual.st_mode) or (actual.st_dev, actual.st_ino)
            != (canonical.st_dev, canonical.st_ino)):
        raise ValueError('Chapter descriptor is not the canonical regular file')
    with path.open('a') as probe:
        try:
            fcntl.flock(probe, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            pass
        else:
            raise ValueError('Chapter descriptor was not already exclusively held')
    borrowed = os.fdopen(os.dup(descriptor), 'a')
    try:
        fcntl.flock(borrowed, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BaseException:
        borrowed.close()
        raise
    return borrowed, {'path': str(path), 'inherited': True, 'pid': parent, 'pid_started': started,
                      'device': actual.st_dev, 'inode': actual.st_ino}

def queue_gate(stage, observations):
    allowed, reason = app_sop.steady(False, allow_owner_now=False)
    ac = 'AC Power' in app_sop.sh(['pmset', '-g', 'batt']).stdout
    observations.append({'stage': stage, 'at': now(), 'steady': allowed, 'reason': reason,
                         'ac': ac, 'load': os.getloadavg()[0]})
    if not allowed or not ac:
        raise sim_lane.Busy(reason + ('' if ac else '; no AC power'))
    remaining(600)

@contextmanager
def sdk_gate(label):
    locks = tuple(sim_lane.lock_chain(label))
    pid, started = os.getpid(), sim_lane.pid_started(os.getpid())
    try:
        sim_lane.acquire(locks, None, 0, 0, sim_lane.max_load_default())
        yield
    finally:
        for lock in reversed(locks):
            owner = lock.record() or {}
            if (lock.held and owner.get('pid') == pid and owner.get('pid_started') == started
                    and owner.get('label') == label):
                lock.release()

@contextmanager
def sdk_environment():
    # Acceptor output paths are not SDK source dependencies; original stager still checks every retained path.
    fields = ['SOP_REPO', 'SOP_OUT_DIR', 'SOP_CONFIG']
    saved = {key: os.environ.pop(key) for key in fields if key in os.environ}
    try:
        yield
    finally:
        os.environ.update(saved)

def build_command(command, log, cwd, developer_dir=None):
    child, identity, observed = None, '', {}
    try:
        with log.open('w') as output:
            environment = dict(os.environ)
            for key in ('DYLD_LIBRARY_PATH', 'DYLD_FRAMEWORK_PATH', 'DYLD_INSERT_LIBRARIES', 'SDKROOT', 'TOOLCHAINS'):
                environment.pop(key, None)
            if developer_dir:
                environment['DEVELOPER_DIR'] = developer_dir
            child = subprocess.Popen(command, cwd=cwd, env=environment, stdout=output, stderr=subprocess.STDOUT,
                                     start_new_session=True)
            identity = sim_lane.pid_started(child.pid)
            observed[child.pid] = identity
            deadline = time.monotonic() + remaining(420)
            while child.poll() is None:
                for pid in group_members(child.pid):
                    observed.setdefault(pid, sim_lane.pid_started(pid))
                if gui_processes() or time.monotonic() >= deadline:
                    raise sim_lane.Busy('Hosted build operation gate/deadline refused')
                time.sleep(0.5)
            return child.returncode
    finally:
        stop_group(child, identity, observed)

def chapter_accept(single_editor=False):
    global DEADLINE
    import prepare
    import bind
    sys.path.insert(0, '/Users/tianli/Apps/.claude/skills/app-lightweight/scripts')
    import platform_measure
    if (os.environ.get('SOP_APP_ID') != 'folio' or os.environ.get('SOP_CHECK') != 'functionality'
            or Path(os.environ.get('SOP_REPO', '')).resolve() != REPO
            or not all(os.environ.get(name) for name in ['SOP_GLOBAL_LOCK_FD', 'SOP_GLOBAL_LOCK_PID',
                                                        'SOP_GLOBAL_LOCK_PID_STARTED'])
            or any(os.environ.get(name) for name in ['SIM_LANE_EXTRA_LOCK', 'SIM_LANE_LOCK'])):
        raise ValueError('Folio fixed queue identity/actual parent descriptor is required; overrides refused')
    output = REPO / 'perf/acceptance'
    if Path(os.environ.get('SOP_OUT_DIR', '')).resolve() != output.resolve():
        raise ValueError('Original Folio acceptance output identity required')
    attempt = uuid.uuid4().hex
    work = Path('/private/tmp') / ('folio-hosted-queue-' + attempt)
    evidence = output / 'hosted-fileflow-20261004' / attempt
    evidence.mkdir(parents=True)
    observations, code, error, held, device = [], 1, None, None, None
    started = time.monotonic()
    DEADLINE = started + 400
    try:
        held, identity = chapter_lock()
        with ExitStack() as leases:
            queue_gate('ordinary-sdk', observations)
            with sdk_gate('folio-hosted-sdk:' + attempt):
                with sdk_environment():
                    built = platform_measure.cached_build('folio', REPO, 'iphone', 'FolioMobile', False,
                                                           leases, build_timeout=remaining(420))
                receipt = Path((built.get('reuse') or {}).get('receipt') or Path(built['work_dir']) / 'build.json')
                verified = sim_lane.reuse_build(receipt, 'folio', REPO, 'iphone', 'FolioMobile', 'Release', False)
                before_input = verified['reuse']['input_sha256']
                before_test = sha(REPO / 'Tests/HostedIntegrationTests.swift')
                shutil.copy2(receipt, evidence / 'ordinary-sdk-build.json')
                shutil.copy2(built['log'], evidence / 'ordinary-sdk-build.log')
                queue_gate('hosted-build', observations)
                prepare.main(['--receipt', str(receipt), '--platform', 'iphone', '--workdir', str(work), '--write'])
                package = work / 'iphone'
                xcodegen = shutil.which('xcodegen') or '/opt/homebrew/bin/xcodegen'
                generated = build_command([xcodegen, 'generate', '--spec', 'project.hosted.yml'],
                                          package / 'xcodegen.log', package)
                if generated:
                    raise RuntimeError('Actual overlay XcodeGen failed: ' + str(generated))
                prepared = json.loads((package / 'prepared.json').read_text())
                command = [str(Path(prepared['xcode']['developer_dir']) / 'usr/bin/xcodebuild'),
                           '-project', str(package / 'FolioMobile.xcodeproj'), '-scheme', 'FolioMobile',
                           '-configuration', 'Debug', '-destination', 'generic/platform=iOS Simulator',
                           '-derivedDataPath', str(package / 'dd'), 'CODE_SIGNING_ALLOWED=NO', 'build-for-testing']
                build_started = now()
                build_code = build_command(command, package / 'hosted-build.log', package, prepared['xcode']['developer_dir'])
                current = sim_lane.reuse_build(receipt, 'folio', REPO, 'iphone', 'FolioMobile', 'Release', False)
                stable = (current['reuse']['input_sha256'] == before_input
                          and sha(REPO / 'Tests/HostedIntegrationTests.swift') == before_test)
                observation = {'exit_code': build_code, 'input_stable': stable,
                               'preparation_sha256': sha(package / 'prepared.json'),
                               'log': str(package / 'hosted-build.log'), 'log_sha256': sha(package / 'hosted-build.log'),
                               'command': command, 'started_at': build_started, 'finished_at': now(),
                               'configuration': 'Debug', 'chapter_lock': identity}
                (package / 'hosted-build-observation.json').write_text(json.dumps(observation, indent=2) + '\n')
                if build_code or not stable:
                    raise RuntimeError('Actual Hosted build/current source stability did not pass')
                bind.main(['--workdir', str(work), '--receipt', str(receipt), '--write'])
            queue_gate('hosted-runtime', observations)
            # This single dedicated stock device is selected by the original native API, no UI/bootstrap runner.
            device = sim_lane.ensure_device('iphone', device_type='iPhone-17-Pro', runtime='27.0', name='Folio Integration')
            arguments = ['--workdir', str(work), '--receipt', str(receipt), '--udid', device['udid'],
                         '--execute', '--timeout', str(max(1, int(remaining(300))))]
            if single_editor:
                arguments += ['--single-editor']
            code = main(arguments)
    except Exception as failure:
        error = str(failure)
        code = 75 if isinstance(failure, (sim_lane.Busy, BlockingIOError)) else 1
    finally:
        cleanup = {'workdir': str(work), 'cache_retained': False, 'shutdown_verified': False}
        if work.exists():
            for path in (work / 'iphone').glob('*.json'):
                shutil.copy2(path, evidence / path.name)
            for path in (work / 'iphone').glob('*.log'):
                shutil.copy2(path, evidence / path.name)
            for run_directory in work.glob('run-*'):
                shutil.copytree(run_directory, evidence / run_directory.name)
            if (work / 'run-expected.json').is_file():
                shutil.copy2(work / 'run-expected.json', evidence / 'run-expected.json')
            cleanup['cache_retained'] = (work / 'run-expected.json').is_file()
            if not cleanup['cache_retained']:
                shutil.rmtree(work)
        if device:
            try:
                cleanup.update(udid=device['udid'], shutdown_verified=sim_lane.device_info(device['udid'])['state'] == 'Shutdown')
                if code == 0 and not cleanup['shutdown_verified']:
                    code, error = 1, 'Owned device shutdown could not be verified'
            except Exception as failure:
                cleanup['error'] = str(failure)
                code, error = 1, str(failure)
        if held is not None:
            held.close()  # Borrowed duplicate never unlocks the parent's file description.
        value = {'ok': code == 0, 'status': 'passed' if code == 0 else 'deferred' if code == 75 else 'failed',
                 'exit_code': code, 'error': error, 'attempt': attempt, 'records': str(evidence),
                 'ordinary_sdk_configuration': 'Release' if (evidence / 'ordinary-sdk-build.json').is_file() else None,
                 'hosted_configuration': 'Debug',
                 'selected_tests': ['testSDKOpenEditSafeSaveAndRecovery'] if single_editor else 'all three original hosted tests',
                 'cleanup': cleanup, 'gates': observations, 'elapsed_seconds': time.monotonic() - started,
                 'summary': 'Actual WK/App open → edit → save → fresh reopen and draft recovery' if code == 0 else error or 'Hosted failed',
                 'uncovered': ['Files picker/OS grant UI', 'OS Scene/multiwindow', 'full WebKit auxiliary accounting']}
        (evidence / 'result.json').write_text(json.dumps(value, indent=2) + '\n')
        (output / 'functionality.detail.json').write_text(json.dumps(value, indent=2) + '\n')
        DEADLINE = None
    print(json.dumps(value))
    return code

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def gui_processes():
    lines = subprocess.run(["ps", "-Ao", "pid=,comm="], capture_output=True, text=True, check=True).stdout.splitlines()
    return [line for line in lines if "/Simulator.app/" in line or "/AppSimulator.app/" in line or line.split()[-1:] in (["Simulator"], ["AppSimulator"])]

def validate():
    harness = json.loads((HARNESS_ROOT / "binding.json").read_text())
    if {name:sha(HARNESS_ROOT/name) for name in harness["files"]} != harness["files"]:
        raise RuntimeError("repository harness binding changed")
    expected = json.loads((ROOT / "run-expected.json").read_text())
    actual = {path: sha(path) for path in expected["files"]}
    if actual != expected["files"]:
        raise RuntimeError("prepared/test/binary/resource/project/log binding changed")
    prepared = json.loads((PACKAGE / "prepared.json").read_text())
    if Path(prepared["receipt"]).resolve() != SDK_RECEIPT:
        raise RuntimeError("explicit SDK receipt does not match the prepared package")
    if sha(SDK_RECEIPT) != prepared["receipt_sha256"]:
        raise RuntimeError("explicit SDK receipt bytes changed")
    observation = json.loads((PACKAGE / "hosted-build-observation.json").read_text())
    if observation["exit_code"] != 0 or observation["input_stable"] is not True:
        raise RuntimeError("actual build-for-testing was not successful and stable")
    if observation["preparation_sha256"] != sha(PACKAGE / "prepared.json") or observation["log_sha256"] != sha(observation["log"]):
        raise RuntimeError("build observation proof mismatch")
    reused = sim_lane.reuse_build(Path(prepared["receipt"]), "folio", REPO, "iphone", scheme="FolioMobile", fixture_debug=False)
    if reused["reuse"]["input_sha256"] != expected["input_sha256"] or prepared["hosted_test_sha256"] != expected["test_sha256"]:
        raise RuntimeError("production or test inputs changed")
    runs = list((PACKAGE / "dd/Build/Products").glob("*.xctestrun"))
    if len(runs) != 1:
        raise RuntimeError("need exactly one actual xctestrun")
    run = plistlib.loads(runs[0].read_bytes())
    tests = [v for k,v in run.items() if not k.startswith("__")]
    if len(tests) != 1 or tests[0].get("IsAppHostedTestBundle") is not True or tests[0].get("IsUITestBundle"):
        raise RuntimeError("xctestrun must contain only the non-UI hosted test bundle")
    if tests[0].get("TestHostBundleIdentifier") != "cyou.tianli.TLMarkdown.mobile":
        raise RuntimeError("wrong test host")
    import bind
    roots, products = bind.products(tests, runs[0].parent, PACKAGE)
    if [str(root) for root in roots] != expected.get('product_roots') or products != expected.get('product_files'):
        raise RuntimeError('complete actual hosted host/test binary or resource file set changed')
    app = app_sop.load_apps("folio")[0]
    return {"harness_binding_sha256":sha(HARNESS_ROOT/"binding.json"),"files": actual, "input_sha256": expected["input_sha256"], "test_sha256": expected["test_sha256"],
            "monitor_code": app_sop.monitor_inputs(app,{})["bindings"]["code"], "xctestrun": str(runs[0].resolve()),
            "xcode": prepared["xcode"], "sdk": reused["sdk"], "expected_manifest_sha256": sha(ROOT / "run-expected.json")}

def group_members(group):
    output = subprocess.run(["ps", "-Ao", "pid=,pgid="], capture_output=True, text=True, check=True).stdout
    return [int(parts[0]) for line in output.splitlines() if len(parts := line.split()) == 2 and int(parts[1]) == group]

def stop_group(child, identity, observed):
    if child is None:
        return
    members = group_members(child.pid)
    if not members:
        return
    if child.poll() is None:
        if sim_lane.pid_started(child.pid) != identity or os.getpgid(child.pid) != child.pid:
            raise RuntimeError("refuse to signal reused/foreign process group")
    elif any(sim_lane.pid_started(pid) != observed.get(pid) for pid in members):
        raise RuntimeError("refuse to signal unidentified group members after leader exit")
    try:
        os.killpg(child.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.monotonic() + 8
    while group_members(child.pid) and time.monotonic() < deadline:
        time.sleep(0.1)
    remaining = group_members(child.pid)
    if remaining:
        if child.poll() is None and sim_lane.pid_started(child.pid) == identity:
            os.killpg(child.pid, signal.SIGKILL)
        elif all(sim_lane.pid_started(pid) == observed.get(pid) for pid in remaining):
            os.killpg(child.pid, signal.SIGKILL)
        else:
            raise RuntimeError("refuse to kill unbound remaining process group")
    try:
        child.wait(timeout=8)
    except subprocess.TimeoutExpired:
        raise RuntimeError("owned test process failed to exit")

def main(argv=None):
    global ROOT, PACKAGE, SDK_RECEIPT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--chapter-accept', action='store_true')
    parser.add_argument('--single-editor', action='store_true', help='one actual editor open/edit/save/reopen and draft recovery')
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--udid")
    parser.add_argument("--workdir", type=Path)
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args(argv)
    if args.chapter_accept:
        if any([args.execute, args.udid, args.workdir, args.receipt]) or args.timeout != 300:
            parser.error('fixed Chapter transaction does not accept manual overrides')
        return chapter_accept(single_editor=args.single_editor)
    if not args.workdir or not args.receipt:
        parser.error('--workdir and --receipt are required for original manual mode')
    ROOT = args.workdir.resolve()
    PACKAGE = ROOT / "iphone"
    SDK_RECEIPT = args.receipt.resolve()
    if ROOT.is_relative_to(REPO.parents[1]):
        parser.error("workdir must be outside live source trees")
    if not args.execute:
        proof = validate()
        print(json.dumps({"status":"readonly-validation-only","input_sha256":proof["input_sha256"],"test_sha256":proof["test_sha256"],"bound_file_count":len(proof["files"]),"harness_binding_sha256":proof["harness_binding_sha256"],"no_boot":True,"no_test":True},indent=2))
        return 0
    if not args.udid:
        parser.error("--execute requires the allocated dedicated Folio Integration UDID")
    record = {"status":"not-passed", "started_at":now(), "driver_sha256":sha(__file__), "udid":args.udid,
              "scope":"non-UI test-without-building; no XCUIApplication or synthetic events"}
    destination = ROOT / ("run-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + str(os.getpid()))
    destination.mkdir()
    log = destination / "test.log"
    result = destination / "tests.xcresult"
    global_lock = session = child = None
    session_birth = None
    entered = False
    child_identity = ""
    observed_group = {}
    errors = []
    def interrupted(signum, frame):
        raise InterruptedError("signal " + str(signum))
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        record["before"] = before = validate()
        if gui_processes():
            raise RuntimeError("Simulator/AppSimulator GUI is present")
        global_lock, record['chapter_lock'] = chapter_lock()
        device = sim_lane.device_info(args.udid)
        if (device["name"] != "Folio Integration" or device["state"] != "Shutdown" or not device["available"]
                or device["device_type"] != "iPhone-17-Pro" or not device["runtime"].endswith("iOS-27-0")):
            raise RuntimeError("device must be the dedicated available Folio Integration iPhone-17-Pro/iOS27.0 in Shutdown state")
        record["device"] = device
        session = sim_lane.Session("iphone", args.udid, label="Folio hosted integration", lock_wait=0, load_wait=0,
                                   boot_timeout=remaining(420))
        session_birth = sim_lane.pid_started(os.getpid())
        session.__enter__()
        entered = True
        if sim_lane.booted_udids() != {args.udid}:
            raise RuntimeError("another simulator is booted; no test started")
        command = [str(Path(before["xcode"]["developer_dir"])/"usr/bin/xcodebuild"), "test-without-building", "-xctestrun", before["xctestrun"],
                   "-destination", "platform=iOS Simulator,id="+args.udid, "-destination-timeout", "10", "-resultBundlePath", str(result),
                   "-parallel-testing-enabled", "NO", "-maximum-concurrent-test-simulator-destinations", "1"]
        if args.single_editor:
            command += ['-only-testing:FolioHostedIntegration/HostedIntegrationTests/testSDKOpenEditSafeSaveAndRecovery']
            command += ['-collect-test-diagnostics', 'never']
        record["command"] = command
        environment = {**os.environ, "DEVELOPER_DIR": before["xcode"]["developer_dir"]}
        for key in ("DYLD_LIBRARY_PATH", "DYLD_FRAMEWORK_PATH", "DYLD_INSERT_LIBRARIES", "SDKROOT", "TOOLCHAINS"):
            environment.pop(key, None)
        with log.open("w") as output:
            child = subprocess.Popen(command, cwd=PACKAGE, env=environment, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            child_identity = sim_lane.pid_started(child.pid)
            observed_group[child.pid] = child_identity
            record["test_process"] = {"pid":child.pid, "pid_started":child_identity, "pgid":os.getpgid(child.pid)}
            deadline = time.monotonic() + remaining(args.timeout)
            while child.poll() is None:
                for pid in group_members(child.pid):
                    observed_group.setdefault(pid, sim_lane.pid_started(pid))
                if gui_processes():
                    raise RuntimeError("Simulator/AppSimulator GUI appeared")
                if time.monotonic() > deadline:
                    raise TimeoutError("single test round timed out; no automatic retry")
                time.sleep(0.5)
            record["exit_code"] = child.returncode
        if gui_processes():
            raise RuntimeError("Simulator/AppSimulator GUI appeared")
        record["after"] = after = validate()
        record["input_stable"] = before == after
        if child.returncode != 0 or before != after or not result.is_dir():
            raise RuntimeError("test exit/results/input stability did not pass")
        summary_command = [str(Path(before["xcode"]["developer_dir"])/"usr/bin/xcresulttool"), "get", "test-results", "summary", "--path", str(result)]
        summary_process = subprocess.run(summary_command, capture_output=True, text=True, timeout=30, check=True, env=environment)
        summary = json.loads(summary_process.stdout)
        record["xcresult_summary"] = summary
        expected_tests = 1 if args.single_editor else 3
        if summary.get("passedTests") != expected_tests or summary.get("failedTests") != 0 or summary.get("skippedTests", 0) != 0:
            raise RuntimeError(f"xcresult must show the selected {expected_tests} hosted tests passed without skips")
        record["status"] = "candidate-pass-cleanup-pending"
    except BaseException as exc:
        errors.append(type(exc).__name__ + ": " + str(exc))
    finally:
        try:
            stop_group(child, child_identity, observed_group)
        except BaseException as exc:
            errors.append("process cleanup: " + str(exc))
        if session is not None:
            # Session.__exit__ currently skips release when shutdown throws.
            # Release each of our own locks independently even on boot/shutdown failure.
            try:
                owns_local = any(lock.held and lock.path == sim_lane.LOCK_DIR
                                 and (lock.record() or {}).get('pid') == os.getpid()
                                 and (lock.record() or {}).get('pid_started') == session_birth
                                 and (lock.record() or {}).get('label') == session.label for lock in session.locks)
                if entered or owns_local:
                    sim_lane.shutdown(args.udid)
                    if sim_lane.device_info(args.udid)["state"] != "Shutdown":
                        raise RuntimeError("owned device did not shut down")
            except BaseException as exc:
                errors.append("owned device shutdown: " + str(exc))
            finally:
                for lock in reversed(session.locks):
                    try:
                        owner = lock.record() or {}
                        if (lock.held and owner.get('pid') == os.getpid() and owner.get('pid_started') == session_birth
                                and owner.get('label') == session.label):
                            lock.release()
                        elif lock.held:
                            raise RuntimeError('owned native lock identity changed; no foreign lock is removed')
                    except BaseException as exc:
                        errors.append("owned lock release: " + str(exc))
                shutil.rmtree(session.work, ignore_errors=True)
        if global_lock is not None:
            global_lock.close()
        try:
            record["after"] = validate()
            record["input_stable"] = record.get("before") == record["after"]
            if not record["input_stable"]:
                errors.append("inputs changed before final result")
        except BaseException as exc:
            errors.append("final readonly validation: " + str(exc))
        record["finished_at"] = now()
        record["observed_process_group"] = observed_group
        record["errors"] = errors
        record["log"] = str(log)
        record["log_sha256"] = sha(log) if log.is_file() else None
        record["xcresult"] = str(result)
        record["status"] = "passed" if record["status"] == "candidate-pass-cleanup-pending" and not errors else "failed-or-deferred"
        (destination / "result.json").write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n")
        print(json.dumps(record,ensure_ascii=False,indent=2))
    return 0 if record["status"] == "passed" else 75 if any("BlockingIOError" in e or "Busy:" in e for e in errors) else 1

if __name__ == "__main__":
    sys.exit(main())
