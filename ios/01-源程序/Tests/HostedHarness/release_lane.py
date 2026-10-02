#!/usr/bin/env python3
"""Folio-only serial Release/build-launch/perf recipe. Default plan, never auto-retries.

Uses canonical sim_lane, Chapter launch acceptance and platform_measure; no collector.
Formal perf is blocked until canonical simulator helper attribution exists.
"""
import argparse
import ast
import datetime
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
PYTHON = Path("/Users/tianli/Dev/.venv/bin/python")
TOOLS = {
    "sim_lane":Path("/Users/tianli/Dev/tools/dev/lib/tools/macapp/ios/sim_lane.py"),
    "measure":Path("/Users/tianli/Apps/.claude/skills/app-lightweight/scripts/measure.py"),
    "platform_measure":Path("/Users/tianli/Apps/.claude/skills/app-lightweight/scripts/platform_measure.py"),
    "platform_launch":Path("/Users/tianli/Apps/chapter/engine/acceptors/platform_launch.py"),
    "app_sop":Path("/Users/tianli/Apps/chapter/engine/app_sop.py"),
}
sys.path.insert(0,str(TOOLS["sim_lane"].parent))
import sim_lane
sys.path.insert(0,str(TOOLS["app_sop"].parent))
import app_sop
spec = importlib.util.spec_from_file_location("folio_harness_process_helpers",HERE/"run.py")
process_helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(process_helpers)

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def helper_interface():
    measure = ast.parse(TOOLS["measure"].read_text())
    platform = ast.parse(TOOLS["platform_measure"].read_text())
    helper = next(n for n in ast.walk(measure) if isinstance(n,ast.FunctionDef) and n.name=="helper_pids")
    idle = next(n for n in ast.walk(platform) if isinstance(n,ast.FunctionDef) and n.name=="idle_sample")
    args = lambda n: {a.arg for a in n.args.args+n.args.kwonlyargs}
    literals = lambda n: {v.value for v in ast.walk(n) if isinstance(v,ast.Constant) and isinstance(v.value,str)}
    checks = {"measure_helper_accepts_udid":"udid" in args(helper),
              "measure_cli_accepts_udid":"--udid" in literals(measure),
              "platform_idle_accepts_udid":"udid" in args(idle),
              "platform_idle_passes_with_helpers":"--with-helpers" in literals(idle),
              "platform_idle_passes_udid":"--udid" in literals(idle)}
    return {"checks":checks,"ready":all(checks.values()),
            "required_runtime_receipt":"measurement.idle.helper_attribution: verified=true, udid equals measurement.udid, main_pid/main_started/process PID-start provenance; scope must include App-associated helpers",
            "note":"This is the proposed Native-owner canonical contract, not a claim that the current tool supports it."}

def current():
    app = app_sop.load_apps("folio")[0]
    return {"tools":{name:sha(path) for name,path in TOOLS.items()},
            "lanes":{p:{k:v for k,v in app_sop.lane_inputs(app,p).items() if k in ("input_sha256","file_count")} for p in ("iphone","ipad","vision")},
            "helper_interface":helper_interface()}

def receipt_command(platform,receipt):
    command = [str(PYTHON),str(TOOLS["platform_measure"]),"--app","folio","--repo",str(REPO),"--platform",platform,
               "--reuse-size-build",str(receipt),"--reuse-runtime-build",str(receipt),"--runs","5","--settle","45",
               "--idle-seconds","60","--warmup-settle","45","--lock-wait","0","--load-wait","0"]
    if platform=="iphone":
        command.append("--sync-ios")
    return command

def call(command,path,deadline,environment):
    child = None
    identity = ""
    observed = {}
    with path.open("w") as output:
        try:
            child = subprocess.Popen(command,cwd=REPO,env=environment,stdout=output,stderr=subprocess.STDOUT,start_new_session=True)
            identity = sim_lane.pid_started(child.pid)
            observed[child.pid] = identity
            while child.poll() is None:
                for pid in process_helpers.group_members(child.pid):
                    observed.setdefault(pid,sim_lane.pid_started(pid))
                if process_helpers.gui_processes():
                    raise RuntimeError("Simulator/AppSimulator GUI appeared")
                if time.monotonic()>deadline:
                    raise TimeoutError("allocated slot deadline expired; no retry")
                time.sleep(0.25)
            if child.returncode!=0:
                raise RuntimeError(f"canonical command exit {child.returncode}; evidence retained: {path}")
        finally:
            process_helpers.stop_group(child,identity,observed)
    return {"command":command,"log":str(path),"log_sha256":sha(path),"exit_code":child.returncode}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workdir",required=True,type=Path)
    parser.add_argument("--execute",action="store_true")
    parser.add_argument("--stage",choices=["build-launch","perf","all"],default="all")
    parser.add_argument("--slot-seconds",type=int,default=1200)
    args = parser.parse_args()
    work = args.workdir.resolve()
    if work.is_relative_to(REPO.parents[1]):
        parser.error("workdir must be outside live Folio family")
    before = current()
    bound = json.loads((HERE/"release-binding.json").read_text())
    if before["tools"]!=bound["tools"] or before["lanes"]!=bound["lanes"] or sha(__file__)!=bound["driver_sha256"]:
        raise RuntimeError("source/tool recipe binding changed; re-review before refreshing its independent binding")
    plan = {"status":"plan-only-no-heavy","bindings":before,"stage":args.stage,
            "budgets":{"iphone":{"memory_mb":150,"cpu_pct":0.5,"size_mb":12,"cold_median_ms":1500},
                       "ipad":{"memory_mb":150,"cpu_pct":0.5,"size_mb":12,"cold_median_ms":1500},
                       "vision":{"memory_mb":150,"cpu_pct":0.5,"size_mb":12,"cold_median_ms":2000}},
            "build_commands":{p:["bash",str(REPO/"scripts/build.sh"),p] for p in ("iphone","vision")},
            "reuse":"iPad reuses the verified ordinary iPhone Release binary via canonical reuse_build",
            "perf_commands":{p:receipt_command(p,work/(p+"-release.json")) for p in ("iphone","ipad","vision")},
            "launch_materials":"Chapter run_acceptor launch_<platform> + SOP_PLATFORM_REUSE_BUILD/LOCK_WAIT=0/LOAD_WAIT=0; preserves its actual lane-ready screenshot/capture with source and binary bindings",
            "uncovered":"launch screenshots are existing startup materials only; no synthetic Files/edit UI workflow, final App Store set, tutorial or user demonstration claimed"}
    if not args.execute:
        print(json.dumps(plan,ensure_ascii=False,indent=2)); return 0
    if args.stage in ("perf","all") and not before["helper_interface"]["ready"]:
        print(json.dumps({"status":"blocked-before-heavy","gap":before["helper_interface"]},ensure_ascii=False,indent=2)); return 2
    if process_helpers.gui_processes():
        raise RuntimeError("GUI present; no heavy started")
    work.mkdir(parents=True,exist_ok=False)
    lock = (app_sop.STATE_DIR/"lock").open("a")
    record = {"status":"not-passed","before":before,"driver_sha256":sha(__file__),"operations":[]}
    deadline = time.monotonic()+args.slot_seconds
    environment = dict(os.environ)
    receipts = {}
    try:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        if args.stage in ("build-launch","all"):
            for platform in ("iphone","vision"):
                log = work/(platform+"-release-build.log")
                operation = call(plan["build_commands"][platform],log,deadline,environment)
                raw = log.read_text()
                built = json.loads(raw[raw.index("{"):raw.rindex("}")+1])
                if built.get("ok") is not True or built.get("configuration")!="Release" or built.get("compilation_conditions"):
                    raise RuntimeError("ordinary Release receipt missing; no Debug/testability substitution")
                path = work/(platform+"-release.json")
                path.write_text(json.dumps(built,ensure_ascii=False,indent=2)+"\n")
                receipts[platform] = path
                sim_lane.reuse_build(path,"folio",REPO,platform,"FolioMobile","Release",False)
                record["operations"].append(operation)
            receipts["ipad"] = work/"ipad-release.json"
            receipts["ipad"].write_bytes(receipts["iphone"].read_bytes())
        else:
            raise RuntimeError("perf-only requires existing receipts: use a prepared workdir via Root; this fresh-workdir recipe never invents them")
        app = app_sop.load_apps("folio")[0]
        for platform in ("iphone","ipad","vision"):
            if args.stage in ("build-launch","all"):
                sim_lane.reuse_build(receipts[platform],"folio",REPO,platform,"FolioMobile","Release",False)
                for key,value in {"SOP_PLATFORM_REUSE_BUILD":str(receipts[platform]),"SOP_PLATFORM_LOCK_WAIT":"0","SOP_PLATFORM_LOAD_WAIT":"0"}.items():
                    os.environ[key] = value
                name = "launch_"+platform
                digest = app_sop.monitor_inputs(app,{})["bindings"]["platform_"+platform]
                command = app_sop.resolve_acceptor(app,name)[0]
                launched = app_sop.run_acceptor(app,name,command,digest,timeout=max(1,int(deadline-time.monotonic())))
                record["operations"].append({"launch":platform,"record":launched})
                if launched["status"]!="passed" or process_helpers.gui_processes():
                    raise RuntimeError("actual launch/material check did not pass")
            if args.stage in ("perf","all"):
                operation = call(receipt_command(platform,receipts[platform]),work/(platform+"-perf.log"),deadline,environment)
                doc = json.loads((REPO/f"perf/platforms/{platform}.json").read_text())
                evidence = json.loads((REPO/doc["runtime_measurement"]["evidence"]).read_text())
                measured = evidence["measurement"]
                attribution = measured["idle"].get("helper_attribution") or {}
                if (attribution.get("verified") is not True or attribution.get("udid")!=measured.get("udid")
                        or not attribution.get("main_pid") or not attribution.get("main_started")
                        or not attribution.get("processes") or "host process only" in measured.get("scope","").lower()):
                    raise RuntimeError("canonical receipt does not prove UDID-bound App helper total; no formal perf pass")
                if doc["speed"]["runs"]!=5 or evidence["measurement"]["settle_s"]!=45 or measured["idle"]["window_s"]!=60:
                    raise RuntimeError("actual 5-run median/45s settle/60s sample missing")
                operation["evidence"] = doc["runtime_measurement"]["evidence"]
                operation["evidence_sha256"] = sha(REPO/operation["evidence"])
                record["operations"].append(operation)
        record["after"] = current()
        if record["after"]!=before:
            raise RuntimeError("source/tool inputs changed during lane")
        record["status"] = "build-launch-passed-resource-pending" if args.stage=="build-launch" else "canonical-perf-observed-review-budgets-and-material-scope"
    except BaseException as exc:
        record["error"] = type(exc).__name__+": "+str(exc)
        raise
    finally:
        lock.close()
        record["finished_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        (work/"result.json").write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n")
    print(json.dumps(record,ensure_ascii=False,indent=2)); return 0

if __name__=="__main__":
    sys.exit(main())
