#!/usr/bin/env python3
"""Measure the installed `folio` index/search CLI against the fixed Python md_index baseline on this Mac.

Writes one key, "index_cli", into perf/lightweight.json (everything else is kept
byte-for-byte). Only aggregate numbers are recorded: no note paths, no note text,
no home-directory paths (this is a public repository).

  python3 scripts/measure-index.py                 # idle gate must pass; writes perf/lightweight.json
  python3 scripts/measure-index.py --force-dry-run # measure even if the gate fails; print JSON only
  python3 scripts/measure-index.py --runs 7        # search / incremental repetitions (median)

Idle gate: app_sop.steady() (AC power, user idle >= 10 min, load < cores, no build).
Checked before and after measuring; if it fails, exit 78 and write nothing.

What is measured (each process separately, via os.wait4 rusage):
  - size and `--version` of /Applications/Folio.app/Contents/Resources/bin/folio
  - `folio index --full` into a temporary database, using this Mac's real index
    configuration read-only, then `folio index` with no changes (incremental)
  - `folio search 水库` (2 characters: LIKE path) and `folio search 汛限水位` (FTS path)
  - the Python baseline md_index.py pinned at BASELINE_COMMIT (sha256-checked), run
    from a temporary copy with INDEX_PATH pointing to its own temporary database:
    full build and the same two searches
Wall clock, user+sys CPU and peak RSS (MiB) are reported separately. The
temporary databases live in build/perf-index/ and are deleted at the end.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sqlite3
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PERF = ROOT / "perf/lightweight.json"
WORK = ROOT / "build/perf-index"
KEY = "index_cli"
FOLIO = Path("/Applications/Folio.app/Contents/Resources/bin/folio")
CONFIG = Path.home() / "Library/Application Support/TLMarkdown/index.json"
INDEXER = Path.home() / "Apps/md-index/indexer"
BASELINE_COMMIT = "d06f313e870067aec02bfe5e07e8b730d8b8338e"
BASELINE_SHA256 = "0b522559c93b3baed6994cbedfdcc1472b82649c9318f61edb6b091cc60e62e3"
TERMS = (("水库", "2 字，LIKE 回退"), ("汛限水位", "4 字，FTS trigram"))
IDLE_EXIT = 78
# Earlier records, cited as-is (different day / sample; not same-run comparisons).
PRIOR = {
    "python_full_build_20260926": {"wall_s": 12.2, "cpu_s": 10.2, "peak_rss_mb": 69.6,
                                   "source": "md-index indexer perf/index-build.json（2026-09-26，生产全量刷新）"},
    "gui_note_search_20260927": {"docs": 4540, "水库_like_s": 0.13, "汛限水位_fts_s": 0.17,
                                 "source": "handoffs/note-search-merge.md（Folio 侧栏搜索，进程内查询，非 CLI）"},
}


def sh(*args):
    return subprocess.run(args, capture_output=True, text=True, check=False).stdout.strip()


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def machine():
    mem = sh("sysctl", "-n", "hw.memsize")
    return (f"{sh('sysctl', '-n', 'hw.model')} / {sh('sysctl', '-n', 'machdep.cpu.brand_string')} / "
            f"{int(mem) // 2**30 if mem.isdigit() else '?'} GB / macOS {sh('sw_vers', '-productVersion')}")


def load_note():
    return {"at": time.strftime("%H:%M:%S"), "loadavg": sh("sysctl", "-n", "vm.loadavg"),
            "memory_pressure_level": sh("sysctl", "-n", "kern.memorystatus_vm_pressure_level")}


def gate():
    sys.path.insert(0, os.path.expanduser("~/Apps/chapter/engine"))
    import app_sop  # noqa: E402  (shared idle gate)
    return app_sop.steady()


COUNT_KEYS = ("changed", "unchanged", "removed")


def run(cmd, counts=False):
    """One child process: wall (s), user+sys CPU (s), peak RSS (MiB) from its own rusage.
    counts=True: the command prints `folio ... --json` stats; keep only the file counts."""
    with tempfile.TemporaryFile() as err, tempfile.TemporaryFile() as out:
        t0 = time.perf_counter()
        proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=out if counts else subprocess.DEVNULL, stderr=err)
        _, status, ru = os.wait4(proc.pid, 0)
        wall = time.perf_counter() - t0
        proc.returncode = os.waitstatus_to_exitcode(status)
        if proc.returncode:
            err.seek(0)
            # Local diagnosis only; never written to the perf file.
            sys.stderr.write(err.read()[-2000:].decode("utf-8", "replace"))
            raise SystemExit(f"child exited {proc.returncode}: {Path(cmd[0]).name} {cmd[1] if len(cmd) > 1 else ''}")
        result = {"wall_s": round(wall, 4), "cpu_s": round(ru.ru_utime + ru.ru_stime, 4),
                  "user_s": round(ru.ru_utime, 3), "sys_s": round(ru.ru_stime, 3),
                  "peak_rss_mb": round(ru.ru_maxrss / 2**20, 1)}  # macOS: ru_maxrss is bytes
        if counts:
            out.seek(0)
            stats = json.loads(out.read())
            result["files"] = {k: stats.get(k) for k in COUNT_KEYS}
    return result


def repeated(cmd, runs, counts=False):
    samples = [run(cmd, counts) for _ in range(runs)]
    extra = {"files_per_run": [s["files"] for s in samples]} if counts else {}
    return {"runs": runs, **extra,
            "median_ms": round(statistics.median(s["wall_s"] for s in samples) * 1000, 1),
            "median_cpu_ms": round(statistics.median(s["cpu_s"] for s in samples) * 1000, 1),
            "peak_rss_mb": max(s["peak_rss_mb"] for s in samples),
            "samples_ms": [round(s["wall_s"] * 1000, 1) for s in samples]}


def db_facts(db: Path):
    con = sqlite3.connect(db.resolve().as_uri() + "?mode=ro", uri=True)
    try:
        docs, chars = con.execute("SELECT COUNT(*), COALESCE(SUM(nchar), 0) FROM doc").fetchone()
    finally:
        con.close()
    return {"documents": docs, "characters": chars}


def python_child(source: Path, db: Path, argv):
    """Run the pinned md_index.py with INDEX_PATH redirected; __file__ stays in the indexer
    directory so HERE/data keeps the same exclusion as production."""
    module = {"__name__": "md_index_baseline", "__file__": str(INDEXER / "md_index.py")}
    exec(compile(source.read_bytes(), str(INDEXER / "md_index.py"), "exec"), module)
    module["INDEX_PATH"] = db
    sys.argv = ["md_index.py", *argv]
    return int(module["main"]())


def baseline_source(tmp: Path) -> Path:
    data = subprocess.run(["git", "-C", str(INDEXER), "show", f"{BASELINE_COMMIT}:md_index.py"],
                          capture_output=True, check=True, timeout=30).stdout
    if sha256(data) != BASELINE_SHA256:
        raise SystemExit("pinned Python baseline missing or changed")
    path = tmp / "md_index_baseline.py"
    path.write_bytes(data)
    return path


def ratio(a, b):
    return round(a / b, 3) if b else None


def measure(runs):
    if not FOLIO.is_file() or not CONFIG.is_file():
        raise SystemExit("installed folio CLI or index configuration missing")
    config_hash = sha256(CONFIG.read_bytes())
    binary = FOLIO.read_bytes()
    version = sh(str(FOLIO), "--version")
    result = {
        "measured_at": time.strftime("%Y-%m-%d %H:%M:%S %z"),
        "device": machine(),
        "cli": {"file": "Folio.app/Contents/Resources/bin/folio", "version": version,
                "bytes": len(binary), "mb": round(len(binary) / 1e6, 2), "sha256": sha256(binary)},
        "baseline": {"what": "md-index indexer md_index.py（Python，固定提交）", "commit": BASELINE_COMMIT,
                     "sha256": BASELINE_SHA256, "python": sh(sys.executable, "--version")},
        "load_before": load_note(),
    }
    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True, mode=0o700)
    folio_db, python_db = WORK / "folio.db", WORK / "python.db"
    folio = [str(FOLIO)]
    common = ["--db", str(folio_db), "--config", str(CONFIG)]
    try:
        with tempfile.TemporaryDirectory(prefix="folio-index-baseline-") as tmp:
            source = baseline_source(Path(tmp))
            result["baseline"]["source_bytes"] = source.stat().st_size
            py = [sys.executable, str(Path(__file__).resolve()), "--_python-child", str(source), str(python_db)]

            full = run(folio + ["index", "--full"] + common)
            incremental = repeated(folio + ["index", "--json"] + common, runs, counts=True)
            f_search = {t: repeated(folio + ["search", t, "--db", str(folio_db)], runs) for t, _ in TERMS}
            f_facts = db_facts(folio_db)

            p_full = run(py + ["build"])
            p_search = {t: repeated(py + ["search", t], runs) for t, _ in TERMS}
            p_facts = db_facts(python_db)
    finally:
        shutil.rmtree(WORK, ignore_errors=True)
    if sha256(CONFIG.read_bytes()) != config_hash:
        raise SystemExit("index configuration changed during measurement; nothing written")

    result["load_after"] = load_note()
    result["corpus"] = {"folio": f_facts, "python": p_facts,
                        "note": "同一台机器、同一时段、各自按生产范围扫描；只记篇数与字符数"}
    result["full_build"] = {"folio": full, "python": p_full,
                            "folio_vs_python": {k: ratio(full[k], p_full[k]) for k in ("wall_s", "cpu_s", "peak_rss_mb")}}
    result["incremental"] = {
        "folio": incremental, "python": None, "python_note": "Python 基线每次都整库重建，没有增量路径",
        "note": ("全量后立即重复 folio index（不带 --full）。扫描的是正在使用的真实工作区，其他进程可能在期间改动文件；"
                 "files_per_run 为 folio 自报的 changed/unchanged/removed 篇数。当前实现只要 changed 或 removed 非零，"
                 "就对整个 FTS 表执行 rebuild，所以这类样本的耗时接近全量")}
    result["search"] = [{"term": t, "path": how, "folio": f_search[t], "python": p_search[t],
                         "folio_vs_python_median": ratio(f_search[t]["median_ms"], p_search[t]["median_ms"])}
                        for t, how in TERMS]
    result["prior_records"] = PRIOR
    result["units"] = "*_s 秒；*_ms 毫秒；peak_rss_mb 为 MiB（ru_maxrss / 2^20）；cli.mb 为十进制 MB"
    result["method"] = (
        "每个子进程单独 os.wait4 取 rusage：墙钟（perf_counter）、CPU = user + sys、峰值 RSS = ru_maxrss。"
        "folio 用本机真实索引配置只读（前后 sha256 一致），写入 build/perf-index/ 临时库，测完删除；"
        "全量 1 次，随后无变化增量与两条搜索各跑 runs 次取中位数（输出丢弃）。"
        f"Python 基线为 md_index.py@{BASELINE_COMMIT[:12]}（校验 sha256），从临时副本运行，INDEX_PATH 指向临时库，"
        "__file__ 保持原目录以沿用同一排除；每次搜索含解释器启动，与 CLI 实际调用同口径。"
        "空闲门 app_sop.steady() 在测量前后都通过才写入。")
    return result


def write(result):
    before = PERF.read_bytes()
    data = json.loads(before)
    data[KEY] = result
    text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    if "/Users/" in json.dumps(result, ensure_ascii=False):
        raise SystemExit("refusing to write a home-directory path into the public perf file")
    if PERF.read_bytes() != before:
        raise SystemExit("perf/lightweight.json changed concurrently; nothing written")
    PERF.write_text(text)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--_python-child":
        return python_child(Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4:])
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--runs", type=int, default=5, help="repetitions for incremental and each search (median)")
    ap.add_argument("--force-dry-run", action="store_true",
                    help="measure even if the idle gate fails; print JSON, write nothing")
    a = ap.parse_args()
    ok, why = gate()
    print(f"空闲门：{'通过' if ok else '未通过'}（{why}）", file=sys.stderr)
    if not ok and not a.force_dry_run:
        return IDLE_EXIT
    result = measure(a.runs)
    ok_after, why_after = gate()
    result["idle_gate"] = {"before": {"ok": ok, "why": why}, "after": {"ok": ok_after, "why": why_after}}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if a.force_dry_run:
        print("dry-run：未写入 perf/lightweight.json", file=sys.stderr)
        return 0
    if not ok_after:
        print(f"空闲门测量后未通过（{why_after}），不写入", file=sys.stderr)
        return IDLE_EXIT
    write(result)
    print(f"已写入 perf/lightweight.json 的 {KEY}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
