#!/usr/bin/env python3
"""One non-UI hosted test-without-building run; never builds or retries."""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent
PACKAGE = ROOT / "iphone"
REPO = Path(__file__).resolve().parents[2]
HARNESS_ROOT = Path(__file__).resolve().parent
SDK_RECEIPT = None
sys.path.insert(0, "/Users/tianli/Dev/tools/dev/lib/tools/macapp/ios")
import sim_lane
sys.path.insert(0, "/Users/tianli/Apps/chapter/engine")
import app_sop

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

def main():
    global ROOT, PACKAGE, SDK_RECEIPT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--udid")
    parser.add_argument("--workdir", required=True, type=Path)
    parser.add_argument("--receipt", required=True, type=Path)
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()
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
        global_lock = (app_sop.STATE_DIR / "lock").open("a")
        fcntl.flock(global_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        device = sim_lane.device_info(args.udid)
        if (device["name"] != "Folio Integration" or device["state"] != "Shutdown" or not device["available"]
                or device["device_type"] != "iPhone-17-Pro" or not device["runtime"].endswith("iOS-27-0")):
            raise RuntimeError("device must be the dedicated available Folio Integration iPhone-17-Pro/iOS27.0 in Shutdown state")
        record["device"] = device
        session = sim_lane.Session("iphone", args.udid, label="Folio hosted integration", lock_wait=0, load_wait=0)
        session.__enter__()
        entered = True
        if sim_lane.booted_udids() != {args.udid}:
            raise RuntimeError("another simulator is booted; no test started")
        command = [str(Path(before["xcode"]["developer_dir"])/"usr/bin/xcodebuild"), "test-without-building", "-xctestrun", before["xctestrun"],
                   "-destination", "platform=iOS Simulator,id="+args.udid, "-destination-timeout", "10", "-resultBundlePath", str(result),
                   "-parallel-testing-enabled", "NO", "-maximum-concurrent-test-simulator-destinations", "1"]
        record["command"] = command
        environment = {**os.environ, "DEVELOPER_DIR": before["xcode"]["developer_dir"]}
        for key in ("DYLD_LIBRARY_PATH", "DYLD_FRAMEWORK_PATH", "DYLD_INSERT_LIBRARIES", "SDKROOT", "TOOLCHAINS"):
            environment.pop(key, None)
        with log.open("w") as output:
            child = subprocess.Popen(command, cwd=PACKAGE, env=environment, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            child_identity = sim_lane.pid_started(child.pid)
            observed_group[child.pid] = child_identity
            record["test_process"] = {"pid":child.pid, "pid_started":child_identity, "pgid":os.getpgid(child.pid)}
            deadline = time.monotonic() + args.timeout
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
        if summary.get("passedTests") != 3 or summary.get("failedTests") != 0 or summary.get("skippedTests", 0) != 0:
            raise RuntimeError("xcresult must show all three hosted tests passed without skips")
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
                owns_local = any(lock.held and lock.path == sim_lane.LOCK_DIR for lock in session.locks)
                if entered or owns_local:
                    sim_lane.shutdown(args.udid)
                    if sim_lane.device_info(args.udid)["state"] != "Shutdown":
                        raise RuntimeError("owned device did not shut down")
            except BaseException as exc:
                errors.append("owned device shutdown: " + str(exc))
            finally:
                for lock in reversed(session.locks):
                    try:
                        lock.release()
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
    return 0 if record["status"] == "passed" else 75 if any("BlockingIOError" in e for e in errors) else 1

if __name__ == "__main__":
    sys.exit(main())
