#!/usr/bin/env python3
"""Build, verify and install through the existing gate, then verify its receipt.

Never launches the installed app or stops an existing user session. Chapter's
build-receipt command owns provenance and only records a genuinely fresh build.
"""
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
ENGINE = Path.home() / "Apps/chapter/engine"
PYTHON = Path.home() / "Dev/.venv/bin/python"


def main():
    if sys.argv[1:]:
        raise SystemExit("Usage: python3 scripts/verify-install.py")
    if Path(sys.executable).absolute() != PYTHON.absolute():
        os.execv(str(PYTHON), [str(PYTHON), str(Path(__file__).resolve())])
    import yaml
    config = yaml.safe_load((ROOT / "project.yaml").read_text())
    installed = Path("/Applications") / (config["name_en"] + ".app")
    sys.path.insert(0, str(ENGINE))
    import app_sop
    app = app_sop.load_apps("folio-mac")[0]
    if installed.exists():
        current, detail = app_sop.verify_build_receipt(app, installed)
        if current:
            subprocess.run([str(PYTHON), str(ROOT / 'scripts/install-cli.py'), str(installed)], check=True)
            print(json.dumps({"ok": True, "skipped": True, "detail": detail,
                              "artifact": app_sop.artifact_snapshot(installed)}, ensure_ascii=False, indent=2))
            return
    # Enumerate source inputs, not generated Editor assets or mutable receipts.
    patterns = ["Sources/**", "CLI/**", "Tests/**", "TLMarkdown.xcodeproj/**", "Info.plist",
                "project.yaml", "build.sh", "scripts/*.py", "scripts/*.sh",
                "Editor/src/**", "Editor/*.mjs", "Editor/package*.json",
                "Resources/*.txt", "Resources/*.md", "Resources/graph-view.html", "icon/*.png", "icon/*.icns"]
    command = [str(PYTHON), str(ENGINE / "app_sop.py"), "build-receipt", "--app", "folio-mac",
               "--artifact", str(installed), "--build-command",
               "set -o pipefail; bash build.sh --install 2>&1 | tee build/install-verification.log"]
    for pattern in patterns:
        command.extend(["--source-glob", pattern])
    print("Building, running isolated editor/file-open checks, and installing with a Chapter receipt…", flush=True)
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    if result.returncode:
        sys.stderr.write(result.stderr or result.stdout)
        raise SystemExit(result.returncode)
    # Read-only reuse of Chapter's actual receipt verifier, including icon,
    # executable, bundle identity, version and the current input digest.
    ok, detail = app_sop.verify_build_receipt(app, installed)
    if ok:
        subprocess.run([str(PYTHON), str(ROOT / 'scripts/install-cli.py'), str(installed)], check=True)
    print(json.dumps({"ok": ok, "installed": str(installed), "detail": detail,
                      "artifact": app_sop.artifact_snapshot(installed)}, ensure_ascii=False, indent=2))
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
