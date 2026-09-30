#!/usr/bin/env python3
"""Chapter's registered re-measurement (project.yaml sop.measure.command).

Measures the release package of the installed build (build/release-<version>/Folio-<version>-<build>-arm64.zip,
the package build.sh produced for exactly that install) with measure-lightweight.py and folds the result into
perf/lightweight.json with fold-lightweight.py.

Exits 75 when the machine is not steady (app_sop's gate: AC power, 10 minutes without input, load below the
core count), before measuring or when the owner came back while it ran: Chapter tries the same input again
when it is steady. Nothing is written in that case.

Kept outside scripts/*.py on purpose: it is not a build input of the installed-app receipt.
"""
import plistlib
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = Path("/Applications/Folio.app")
DEFER = 75
sys.path.insert(0, str(Path.home() / "Apps/chapter/engine"))
import app_sop  # noqa: E402


def main():
    steady, why = app_sop.steady()
    if not steady:
        print(f"未测量：{why}")
        return DEFER
    info = plistlib.loads((APP / "Contents/Info.plist").read_bytes())
    short, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    package = ROOT / f"build/release-{short}/Folio-{short}-{build}-arm64.zip"
    if not package.is_file():
        print(f"没有装机构建 {short} ({build}) 的发行包：{package.relative_to(ROOT)}；先按 build.sh 出包")
        return 1
    raw = ROOT / f"build/perf-{short}-{build}.json"
    subprocess.run([sys.executable, str(ROOT / "scripts/measure-lightweight.py"), "--zip", str(package), "--raw", str(raw)],
                   cwd=ROOT, check=True)
    steady, why = app_sop.steady()
    # The measurement's own load is expected afterwards; the owner coming back, unplugging or a build is not.
    if not steady and any(not reason.startswith("负载") for reason in why.split("；")):
        print(f"样本作废，未写入：测量期间{why}")
        return DEFER
    subprocess.run([sys.executable, str(ROOT / "scripts/release/fold-lightweight.py"), "--raw", str(raw)], cwd=ROOT, check=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
