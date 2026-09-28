#!/usr/bin/env python3
"""Fold one measure-lightweight.py raw result into perf/lightweight.json.

The page and README read the top level, which must describe the exact release
package. A re-measurement of the same marketing version (e.g. a later build of
1.2.0) moves the replaced top level into measurement_history and keeps
compare_previous_release; a new marketing version turns the old top level into
compare_previous_release. Only measured values are written.

  python3 scripts/release/fold-lightweight.py --raw build/perf-1.2.0-51.json [--dry-run]

Kept outside scripts/*.py on purpose: it edits measurement records only and is
not a build input for the installed-app receipt.
"""
import argparse
import copy
import datetime
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PERF = ROOT / "perf/lightweight.json"


def fold(data, raw, tests):
    old = copy.deepcopy(data)
    new_version = f"{raw['version']} ({raw['build']})"
    same_line = old["version"].split(" ")[0] == str(raw["version"])
    launch_old = next(item for item in old["speed_gui"] if item["key"] == "launch")
    now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    history = data.setdefault("measurement_history", [])
    if same_line:
        history.append({"replaced_at": now, "reason": f"同一版本线重测：{old['version']} → {new_version}（发行包重建）",
                        "version": old["version"], "size": old["size"], "idle": old["idle"],
                        "launch": {k: launch_old.get(k) for k in ("median_ms", "runs", "samples_ms")},
                        "conditions": old.get("conditions")})
    else:
        history.append({"replaced_at": now, "reason": f"发布 {new_version}：{old['version']} 转入 compare_previous_release",
                        "previous_compare_previous_release": old.get("compare_previous_release")})
        data["compare_previous_release"] = {
            "version": old["version"], "download_file": old["size"].get("download_file"),
            "state": f"上一发行版，{old['measured_at']} 同一脚本、同一合成样例、同一隔离方式实测，非同时段对比",
            "size": {"download_bytes": old["size"]["download_bytes"], "installed_bytes": old["size"]["installed_bytes"]},
            "idle": {k: old["idle"].get(k) for k in ("footprint_mb", "main_footprint_mb", "cpu_pct")},
            "launch_median_ms": launch_old["median_ms"], "launch_runs": launch_old.get("runs")}
    previous = data["compare_previous_release"]
    data["version"] = new_version
    data["measured_at"] = raw["measured_at"][:10]
    data["device"] = raw["device"]
    size = dict(old["size"])
    size.update({"download_bytes": raw["download_bytes"], "installed_bytes": raw["installed_bytes"],
                 "download_mb": round(raw["download_bytes"] / 2**20, 2), "installed_mb": round(raw["installed_bytes"] / 2**20, 2),
                 "download_file": raw["source"],
                 "growth_vs_previous_bytes": raw["installed_bytes"] - previous["size"]["installed_bytes"]})
    data["size"] = size
    load = raw["idle"].get("load_before", {})
    data["conditions"] = (f"发布包 {raw['source']} 解压后做隔离副本（改 bundle ID、去文件关联、ad-hoc 重签、独立状态目录），"
                          f"open -g -j -n 后台隐藏启动，不抢焦点；测量前 app_sop 空闲门通过；"
                          f"开始时 loadavg {load.get('loadavg', '未记录')}，内存压力等级 {load.get('memory_pressure_level', '未记录')}")
    data["idle"] = raw["idle"]
    for item in data["speed_gui"]:
        if item["key"] == "launch":
            item.update({"median_ms": raw["launch"]["median_ms"], "runs": len(raw["launch"]["samples_ms"]),
                         "samples_ms": raw["launch"]["samples_ms"], "method": raw["launch"]["method"]})
    if tests:
        data["tests"] = tests
    return data


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--raw", type=Path, required=True)
    ap.add_argument("--tests", help="tests actually run on this release build")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    raw = json.loads(a.raw.read_text())
    before = PERF.read_text()
    data = fold(json.loads(before), raw, a.tests)
    text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    if "/Users/" in text:
        raise SystemExit("local path in perf record; nothing written")
    if a.dry_run:
        print(json.dumps({k: data[k] for k in ("version", "measured_at", "size")}, ensure_ascii=False, indent=2))
        return
    if PERF.read_text() != before:
        raise SystemExit("perf/lightweight.json changed concurrently; nothing written")
    PERF.write_text(text)
    print(f"folded {data['version']} into {PERF.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
