#!/usr/bin/env python3
"""Prepare synthetic files only; never launch an app or touch a user's session."""
from datetime import datetime
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--app", type=Path, default=ROOT / "build/DerivedData/Build/Products/Release/TLMarkdown.app")
args = parser.parse_args()
assert args.app.is_dir(), "Build the app before preparing its isolated recording copy"
run = ROOT / "build" / "demo" / datetime.now().strftime("%Y%m%d-%H%M%S-%f")
run.mkdir(parents=True)
source = ROOT / "docs" / "demo" / "写作样例.md"
document = run / source.name
shutil.copyfile(source, document)
(run / "state").mkdir(mode=0o700)
environment = {"FOLIO_BACKGROUND": "1", "TL_MARKDOWN_STATE_DIR": str(run / "state"), "TL_MARKDOWN_OPEN": str(document)}
app = run / "Folio.app"
subprocess.run(["ditto", str(args.app), str(app)], check=True)
info_path = app / "Contents/Info.plist"
info = plistlib.loads(info_path.read_bytes())
original_bundle_id = info["CFBundleIdentifier"]
info["CFBundleIdentifier"] = "cyou.tianli.Folio.Recording." + run.name
info["LSEnvironment"] = environment
info["LSUIElement"] = True
info["NSSupportsAutomaticTermination"] = False
info["NSSupportsSuddenTermination"] = False
info.pop("CFBundleDocumentTypes", None)
info.pop("UTImportedTypeDeclarations", None)
info_path.write_bytes(plistlib.dumps(info))
subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
(run / "input.json").write_text(json.dumps({
    "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
    "document": document.name,
    "replacement": {"before": "进行中", "after": "已经完成"},
    "source_bundle_id": original_bundle_id,
    "app_version": info["CFBundleShortVersionString"],
    "app_build": info["CFBundleVersion"],
    "executable_sha256": hashlib.sha256((app / "Contents/MacOS" / info["CFBundleExecutable"]).read_bytes()).hexdigest(),
}, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({"run": str(run), "app": str(app), "version": info["CFBundleShortVersionString"],
                  "build": info["CFBundleVersion"], "environment": environment}, ensure_ascii=False, indent=2))
