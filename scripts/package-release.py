#!/usr/bin/env python3
"""Stage a self-contained binary ZIP. Does not install, launch, or publish Folio."""
from datetime import datetime, timezone
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_APP = ROOT / "build/DerivedData/Build/Products/Release/TLMarkdown.app"


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_digest():
    files = [ROOT / name for name in ("Info.plist", "Editor/package.json", "Editor/package-lock.json", "Editor/build.mjs",
                                     "TLMarkdown.xcodeproj/project.pbxproj", "Resources/欢迎使用.md", "icon/AppIcon.icns")]
    files += list((ROOT / "Sources").glob("*.swift")) + list((ROOT / "Editor/src").glob("*"))
    sha = hashlib.sha256()
    for path in sorted(files):
        if path.is_file():
            sha.update(str(path.relative_to(ROOT)).encode() + b"\0" + path.read_bytes() + b"\0")
    return sha.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=DEFAULT_APP)
    parser.add_argument("--out", type=Path, default=ROOT / "build/release")
    parser.add_argument("--stamp", action="store_true", help="Record build provenance before signing; called by build.sh")
    args = parser.parse_args()
    app = args.app.resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == "cyou.tianli.TLMarkdown", "Unexpected application identity"
    assert info["CFBundleDisplayName"] == "Folio", "Unexpected display name"
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    stamp_file = app / "Contents/Resources/FolioBuild.json"
    if args.stamp:
        stamp = {"source_commit": run("git", "-C", str(ROOT), "rev-parse", "HEAD"),
                 "source_sha256": source_digest(), "built_at": datetime.now(timezone.utc).isoformat(),
                 "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"]}
        stamp_file.write_text(json.dumps(stamp, ensure_ascii=False, indent=2) + "\n")
        return
    stamp = json.loads(stamp_file.read_text())
    assert stamp["source_sha256"] == source_digest(), "Sources changed after build; rebuild before packaging"
    assert stamp["version"] == info["CFBundleShortVersionString"] and stamp["build"] == info["CFBundleVersion"], "Build metadata mismatch"
    run("codesign", "--verify", "--deep", "--strict", str(app))
    assert b"/Users/" not in executable.read_bytes(), "Developer debug paths remain in the distributed executable"
    signing = run("codesign", "-d", "--verbose=4", str(app))
    assert "Signature=adhoc" in signing, "This packaging description expects the current adhoc pipeline"
    architectures = run("lipo", "-archs", str(executable)).split()
    # No external runtime is used. Inspect load commands instead of assuming a small bundle is portable.
    dependencies = run("otool", "-L", str(executable)).splitlines()[1:]
    for line in dependencies:
        dependency = line.strip().split(" (", 1)[0]
        assert dependency.startswith(("/usr/lib/", "/System/Library/", "@rpath/libswift")), f"Unexpected runtime dependency: {dependency}"
    resources = app / "Contents/Resources"
    for name in ("Editor/index.html", "Editor/editor.js", "Editor/mermaid.js", "THIRD-PARTY-NOTICES.txt", "欢迎使用.md"):
        assert (resources / name).is_file(), f"Missing bundled resource: {name}"
    assert not any(p.name in {".git", "session.json", "node_modules"} for p in app.rglob("*")), "Development or user state entered the app"
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    filename = f"Folio-{stamp['version']}-{stamp['build']}-{'_'.join(architectures)}.zip"
    archive = out / filename
    with tempfile.TemporaryDirectory(prefix="folio-package-") as temporary:
        staged = Path(temporary) / "Folio.app"
        run("ditto", str(app), str(staged))
        run("codesign", "--verify", "--deep", "--strict", str(staged))
        packed = Path(temporary) / filename
        run("ditto", "-c", "-k", "--norsrc", "--noextattr", "--keepParent", str(staged), str(packed))
        # Verify the actual ZIP, including the signature, after a clean extraction.
        extracted = Path(temporary) / "unpacked"
        run("ditto", "-x", "-k", str(packed), str(extracted))
        run("codesign", "--verify", "--deep", "--strict", str(extracted / "Folio.app"))
        shutil.copyfile(packed, archive)
    metadata = {"product": "Folio", "bundle_id": info["CFBundleIdentifier"], **stamp,
                "minimum_macos": info["LSMinimumSystemVersion"], "architectures": architectures,
                "filename": filename, "bytes": archive.stat().st_size, "sha256": digest(archive),
                "download_url": f"downloads/{filename}", "signature": "adhoc", "notarized": False,
                "verification": {"archive_signature": "passed", "bundled_resources": "passed",
                                 "system_runtime_dependencies": "passed", "gui_final_package": "pending"}}
    (out / "release.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
    (out / "SHA256SUMS.txt").write_text(f"{metadata['sha256']}  {filename}\n")
    print(json.dumps(metadata, ensure_ascii=False, indent=2))
    print(f"Staged: {archive}")


if __name__ == "__main__":
    main()
