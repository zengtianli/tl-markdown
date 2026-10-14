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
import argparse
import shlex

ROOT = Path(__file__).resolve().parents[1]
ENGINE = Path.home() / "Apps/chapter/engine"
PYTHON = Path.home() / "Dev/.venv/bin/python"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--local', action='store_true', help='Explicit stable-signed local iteration; no notarization/publication')
    parser.add_argument('--signed-app', type=Path, help='Same-source Developer ID package from the certificate owner')
    parser.add_argument('--candidate-receipt', type=Path)
    parser.add_argument('--signing-receipt', type=Path)
    args = parser.parse_args()
    if args.signed_app and not args.local: parser.error('--signed-app requires --local')
    if args.signed_app and (not args.candidate_receipt or not args.signing_receipt): parser.error('--signed-app requires both original receipts')
    if Path(sys.executable).absolute() != PYTHON.absolute():
        os.execv(str(PYTHON), [str(PYTHON), str(Path(__file__).resolve()), *sys.argv[1:]])
    import yaml
    config = yaml.safe_load((ROOT / "project.yaml").read_text())
    installed = Path("/Applications") / (config["name_en"] + ".app")
    sys.path.insert(0, str(ENGINE))
    import app_sop
    app = app_sop.load_apps("folio-mac")[0]
    if installed.exists():
        current, detail = app_sop.verify_build_receipt(app, installed)
        if current:
            if args.local:
                subprocess.run([str(PYTHON), str(ROOT / 'scripts/release_grade.py'), 'check-local', str(installed)], check=True)
            subprocess.run([str(PYTHON), str(ROOT / 'scripts/install-cli.py'), str(installed)], check=True)
            print(json.dumps({"ok": True, "skipped": True, "detail": detail,
                              "artifact": app_sop.artifact_snapshot(installed)}, ensure_ascii=False, indent=2))
            return
    # Enumerate source inputs, not generated Editor assets or mutable receipts. Scripts are the ones build.sh
    # --install actually runs; site, demo, measurement and acceptance scripts do not shape the installed app,
    # and listing them (scripts/*.py) made a page-only edit re-open the receipt and bump the build number.
    patterns = ["Sources/**", "CLI/**", "Tests/**", "TLMarkdown.xcodeproj/**", "Info.plist",
                "project.yaml", "build.sh", "scripts/build-cli.sh", "scripts/test.sh", "scripts/package-release.py",
                "scripts/test_file_open.py", "scripts/install-cli.py", "scripts/release_grade.py",
                "Editor/src/**", "Editor/*.mjs", "Editor/package*.json",
                "Resources/*.txt", "Resources/*.md", "Resources/graph-view.html", "icon/*.png", "icon/*.icns"]
    build_command = 'bash build.sh --install-local' if args.local else 'bash build.sh --install'
    if args.signed_app:
        build_command = ' '.join(name + '=' + shlex.quote(str(path.resolve(strict=True))) for name,path in [
            ('FOLIO_PREBUILT',args.signed_app), ('FOLIO_CANDIDATE_RECEIPT',args.candidate_receipt), ('FOLIO_SIGNING_RECEIPT',args.signing_receipt)]) + ' ' + build_command
    command = [str(PYTHON), str(ENGINE / "app_sop.py"), "build-receipt", "--app", "folio-mac",
               "--artifact", str(installed), "--build-command",
               "set -o pipefail; " + build_command + " 2>&1 | tee build/install-verification.log"]
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
