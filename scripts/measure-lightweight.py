#!/usr/bin/env python3
"""Measure Folio's install size, launch time, idle memory and idle CPU without touching the user's session.

The released (or freshly built) app is copied into a temporary directory with a
separate bundle ID, no document associations and an isolated state directory,
then launched only with `open -g -j` (background, hidden: never takes focus).
No clicks, keys or window activation are synthesized. The copy is unregistered
and deleted afterwards.

Idle memory and CPU come from the shared app-lightweight measure.py
(`idle <PID> --with-helpers`): the app process plus the WebKit XPC services in its
launchd domain (WebContent / GPU / Networking) and any child processes; no
footprint queries inside the CPU window, memory sampled three times after it.
Memory is phys_footprint (Activity Monitor "Memory" column), in MiB. Each
process's lifetime peak (phys_footprint_peak) is recorded as well, and the
WebContent state (reclaimed after a memory-pressure event or not) is labelled,
because that state alone moves the total by ~40 MB.

  python3 scripts/measure-lightweight.py --zip build/release/Folio-<version>-<build>-arm64.zip --raw perf/raw/baseline.json
  python3 scripts/measure-lightweight.py --app build/DerivedData/Build/Products/Release/TLMarkdown.app --raw perf/raw/after.json
  python3 scripts/measure-lightweight.py --runs 0 --app build/perf-next/after-4/TLMarkdown.app --raw perf/raw/idle.json   # idle only
"""
from pathlib import Path
import argparse
import importlib.util
import json
import os
import plistlib
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
WEBKIT = ("com.apple.WebKit.WebContent", "com.apple.WebKit.GPU", "com.apple.WebKit.Networking")
LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"


def sh(*args):
    return subprocess.run(args, capture_output=True, text=True, check=False).stdout.strip()


def sample_document(path):
    """Deterministic synthetic Markdown (~200 KB): headings, prose, tables, code, lists, math."""
    parts = ["# Folio 性能样例\n\n本文件由 measure-lightweight.py 生成，只含合成内容。\n"]
    for i in range(1, 201):
        parts.append(f"\n## 第 {i} 节 · 水位与流量记录\n\n")
        parts.append("这是一段用于测量的中文正文，包含**加粗**、*斜体*、`行内代码`和[链接](https://example.com)。" * 3 + "\n\n")
        parts.append("| 站点 | 水位 (m) | 流量 (m³/s) |\n| --- | ---: | ---: |\n")
        parts.extend(f"| 站 {i}-{j} | {10 + j * 0.37:.2f} | {120 + i * j:.1f} |\n" for j in range(1, 5))
        parts.append(f"\n- [ ] 待办 {i}\n- [x] 已完成 {i}\n\n```python\ndef flow_{i}(h):\n    return {i} * h ** 1.5\n```\n")
        if i % 20 == 0:
            parts.append(f"\n$$Q = {i} \\cdot b \\sqrt{{2g}} H^{{3/2}}$$\n")
    path.write_text("".join(parts), encoding="utf-8")
    return path.stat().st_size


def isolated_copy(source, work):
    app = work / "FolioPerf.app"
    subprocess.run(["ditto", str(source), str(app)], check=True)
    info_path = app / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    version = (info["CFBundleShortVersionString"], info["CFBundleVersion"])
    info["CFBundleIdentifier"] = "cyou.tianli.Folio.Perf"
    info.pop("CFBundleDocumentTypes", None)
    info.pop("UTImportedTypeDeclarations", None)
    info_path.write_bytes(plistlib.dumps(info))
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
    return app, version


def webkit_pids():
    pids = set()
    for name in WEBKIT:
        pids |= {int(p) for p in sh("pgrep", "-f", name).split()}
    return pids




def cpu_seconds(pid):
    t = sh("ps", "-o", "time=", "-p", str(pid))
    if not t:
        return None
    days, _, rest = t.rpartition("-")
    secs = sum(float(v) * 60 ** i for i, v in enumerate(reversed(rest.split(":"))))
    return secs + (int(days) * 86400 if days else 0)




def main_pid(app):
    exe = str(app / "Contents/MacOS")
    for _ in range(100):
        pids = [int(p) for p in sh("pgrep", "-f", exe).split()]
        if pids:
            return pids[0]
        time.sleep(0.1)
    raise SystemExit("App did not start")


def stop(pid, helpers):
    subprocess.run(["kill", "-TERM", str(pid)], check=False)
    for _ in range(100):
        if not cpu_seconds(pid) and not (helpers & webkit_pids()):
            return
        time.sleep(0.1)


def launch_times(app, state, doc, runs):
    """Launch to the editor window's onAppear, which reads the document and writes the isolated session record.

    The built-in TL_MARKDOWN_BENCHMARK report needs a main-capable window and
    does not fire for a hidden (-j) launch, so the observable is the moment
    session.json first appears in the isolated state directory.
    """
    samples = []
    for n in range(runs):
        for f in state.glob("*"):
            f.unlink()
        record = state / "session.json"
        t0 = time.time()
        subprocess.run(["open", "-g", "-j", "-n", "--env", f"TL_MARKDOWN_STATE_DIR={state}",
                        "--env", f"TL_MARKDOWN_OPEN={doc}", str(app)], check=True)
        deadline = time.time() + 30
        while time.time() < deadline and not record.exists():
            time.sleep(0.005)
        if not record.exists():
            raise SystemExit("App did not open the document")
        samples.append(round((record.stat().st_birthtime - t0) * 1000, 1))
        pid = main_pid(app)
        stop(pid, set())
        time.sleep(3)  # let WebKit helpers exit before the next cold-ish launch
    return samples


# Shared app-lightweight measure.py; override with APP_LIGHTWEIGHT_MEASURE when it lives elsewhere.
MEASURE = Path(os.environ.get("APP_LIGHTWEIGHT_MEASURE", Path.home() / "Apps/.claude/skills/app-lightweight/scripts/measure.py"))
_spec = importlib.util.spec_from_file_location("app_lightweight_measure", MEASURE)
measure = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(measure)
# WebContent frees ~40 MB (JS heap, bytecode, caches) on a system memory-pressure event; whether
# that has happened before the sample is chance. Below this fraction of its lifetime peak it has.
RECLAIMED_BELOW = 0.6


def footprint_now_and_peak(pid):
    """phys_footprint and phys_footprint_peak (lifetime high-water mark) in MiB."""
    out = sh("footprint", "-p", str(pid))
    def grab(key):
        m = re.search(r"\b" + key + r":\s*([\d.]+)\s*(KB|MB|GB|B)\b", out)
        return m and round(float(m.group(1)) * {"B": 1 / 1048576, "KB": 1 / 1024, "MB": 1, "GB": 1024}[m.group(2)], 1)
    return grab("phys_footprint"), grab("phys_footprint_peak")


def load_note():
    return {"at": time.strftime("%H:%M:%S"), "loadavg": sh("sysctl", "-n", "vm.loadavg"),
            "memory_pressure_level": sh("sysctl", "-n", "kern.memorystatus_vm_pressure_level"),
            "swap": sh("sysctl", "-n", "vm.swapusage")}


def roster(pid, seen):
    """1 Hz: every process of the app (descendants + XPC services in its launchd pid domain) with its
    highest RSS so far (MiB). measure.py cannot see processes that exit between its readings."""
    rows = {int(p): name for p, name in measure.helper_pids(pid).items()}
    rows[pid] = "main"
    for p, name in rows.items():
        rss = sh("ps", "-o", "rss=", "-p", str(p))
        if rss.isdigit():
            entry = seen.setdefault(p, {"pid": p, "name": name, "peak_rss_mb": 0.0})
            entry["peak_rss_mb"] = max(entry["peak_rss_mb"], round(int(rss) / 1024, 1))


def idle(app, state, doc, settle, seconds):
    """Launch hidden, settle, then the shared measure.py idle --with-helpers (CPU window without
    footprint queries, memory sampled 3x afterwards), plus each process's lifetime peak."""
    for f in state.glob("*"):
        f.unlink()
    before = load_note()
    subprocess.run(["open", "-g", "-j", "-n", "--env", f"TL_MARKDOWN_STATE_DIR={state}",
                    "--env", f"TL_MARKDOWN_OPEN={doc}", str(app)], check=True)
    pid = main_pid(app)
    seen, t0 = {}, time.time()
    while time.time() - t0 < settle:  # the settle period, not the measured window
        roster(pid, seen)
        time.sleep(1)
    run = subprocess.run([sys.executable, str(MEASURE), "idle", str(pid), "--seconds", str(seconds), "--with-helpers"],
                         capture_output=True, text=True, check=True)
    result = json.loads(run.stdout[:run.stdout.rindex("}") + 1])["idle"]
    result["process"] = f"{app.name} (PID {pid}) + helpers"
    for proc in result["processes"]:
        now, peak = footprint_now_and_peak(proc["pid"])
        proc["lifetime_peak_mb"] = peak
        proc["footprint_now_mb"] = now
    web = next((p for p in result["processes"] if "WebKit.WebContent" in p["name"]), None)
    if web and web["lifetime_peak_mb"]:
        ratio = web["footprint_peak_mb"] / web["lifetime_peak_mb"]
        result["webcontent_state"] = "已回收" if ratio < RECLAIMED_BELOW else "未回收"
        result["webcontent_to_lifetime_peak"] = round(ratio, 2)
        result["webcontent_mb"] = web["footprint_peak_mb"]
        result["webcontent_lifetime_peak_mb"] = web["lifetime_peak_mb"]
    result["settle_roster"] = sorted(seen.values(), key=lambda x: x["pid"])
    result["settle_s"], result["load_before"], result["load_after"] = settle, before, load_note()
    result["units"] = "*_mb 为 MiB（2^20 字节，footprint 工具与活动监视器同口径）"
    result["method"] = (f"open -g -j -n 隐藏启动 → 静置 {settle} s（其间 1 Hz 记录进程名册与 RSS 峰值）→ "
                        f"measure.py idle <PID> --seconds {seconds} --with-helpers（CPU 窗口内不查 footprint，"
                        "窗口后另采 3 次同时刻合计取峰值）→ 各进程 footprint -p 的 phys_footprint_peak（生命周期峰值）；"
                        f"WebContent 当前/生命周期峰值 < {RECLAIMED_BELOW} 记为「已回收」")
    stop(pid, {p["pid"] for p in result["processes"]})
    return result


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--zip", type=Path, help="release ZIP (measures download size too)")
    ap.add_argument("--app", type=Path, help="built .app instead of a ZIP")
    ap.add_argument("--runs", type=int, default=7, help="launch-time runs; 0 skips them")
    ap.add_argument("--settle", type=int, default=45)
    ap.add_argument("--seconds", type=int, default=60)
    ap.add_argument("--raw", type=Path, required=True)
    a = ap.parse_args()
    assert a.zip or a.app, "--zip or --app is required"
    # A user's own Folio may keep running: every reading is scoped to this copy's PID and its launchd domain.
    assert not sh("pgrep", "-f", "FolioPerf.app"), "Another isolated FolioPerf copy is being measured"
    with tempfile.TemporaryDirectory(prefix="folio-perf-") as tmp:
        work = Path(tmp)
        result = {"measured_at": time.strftime("%Y-%m-%d %H:%M:%S %z"),
                  "device": f"{sh('sysctl', '-n', 'hw.model')} / {sh('sysctl', '-n', 'machdep.cpu.brand_string')} / "
                            f"{sh('sysctl', '-n', 'hw.memsize') and int(sh('sysctl', '-n', 'hw.memsize')) // 2**30} GB / macOS {sh('sw_vers', '-productVersion')}"}
        if a.zip:
            subprocess.run(["ditto", "-x", "-k", str(a.zip), str(work / "unzipped")], check=True)
            source = next((work / "unzipped").glob("*.app"))
            result["download_bytes"] = a.zip.stat().st_size
            result["source"] = a.zip.name
        else:
            source = a.app
            result["source"] = str(a.app.relative_to(ROOT)) if a.app.is_relative_to(ROOT) else a.app.name
        result["installed_bytes"] = int(sh("du", "-sk", str(source)).split()[0]) * 1024
        app, (version, build) = isolated_copy(source, work)
        result["version"], result["build"] = version, build
        state = work / "state"
        state.mkdir(mode=0o700)
        doc = work / "sample.md"
        result["document_bytes"] = sample_document(doc)
        try:
            if a.runs:
                launches = launch_times(app, state, doc, a.runs)
                result["launch"] = {"samples_ms": launches, "median_ms": round(statistics.median(launches), 1),
                                    "method": "open -g -j 隐藏启动 → 编辑窗口出现并读入文档（隔离会话记录首次写盘）；首次为冷启动，其余热启动"}
            result["idle"] = idle(app, state, doc, a.settle, a.seconds)
        finally:
            for pid in sh("pgrep", "-f", str(app / "Contents/MacOS")).split():
                subprocess.run(["kill", "-TERM", pid], check=False)
            subprocess.run([LSREGISTER, "-u", str(app)], check=False, capture_output=True)
    a.raw.parent.mkdir(parents=True, exist_ok=True)
    a.raw.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    summary = {k: v for k, v in result.items() if k != "idle"}
    summary["idle"] = {k: v for k, v in result["idle"].items() if k not in ("processes", "settle_roster")}
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
