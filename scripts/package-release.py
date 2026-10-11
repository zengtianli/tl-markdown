#!/usr/bin/env python3
"""Stage the release ZIP from the notarized, stapled build; optionally migrate an already public ZIP.

Only a package at Folio's release grade (scripts/release_grade.py) is staged: an ad hoc or Apple
Development build is a trial build and is refused.
"""
from datetime import datetime, timezone
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urljoin, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
import release_grade

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_APP = ROOT / "build/DerivedData/Build/Products/Release/TLMarkdown.app"
GITHUB_REPOSITORY = "zengtianli/tl-markdown"
PUBLIC_RELEASE = "https://app-mac-folio.tianli.cyou/release.json"


def github_assets(release):
    tag = f"v{release['version']}-{release['build']}"
    base = f"https://github.com/{GITHUB_REPOSITORY}/releases"
    assets = f"{base}/download/{tag}"
    return {"tag": tag, "release_url": f"{base}/tag/{tag}",
            "download_url": f"{assets}/{release['filename']}",
            "checksum_url": f"{assets}/SHA256SUMS.txt"}


def public_metadata(release):
    # Only existing public release facts: never upload receipts, logs or local paths.
    keys = ("product", "bundle_id", "source_commit", "source_sha256", "built_at", "version", "build",
            "cli_sha256", "minimum_macos", "architectures", "filename", "bytes", "sha256", "signature",
            "signing_identity", "hardened_runtime", "notarized", "stapled", "gatekeeper", "executable_sha256",
            "verification")
    public = {key: release[key] for key in keys if key in release}
    public.update({key: value for key, value in github_assets(release).items() if key != "tag"})
    assert "/Users/" not in json.dumps(public), "Local paths entered public metadata"
    return public


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_digest(root=ROOT):
    files = [root / name for name in ("Info.plist", "Editor/package.json", "Editor/package-lock.json", "Editor/build.mjs",
                                     "TLMarkdown.xcodeproj/project.pbxproj", "Resources/欢迎使用.md", "Resources/graph-view.html", "icon/AppIcon.icns")]
    files += list((root / "Sources").rglob("*.swift")) + list((root / "Editor/src").glob("*"))
    files += list((root / "CLI").glob("*.swift"))
    sha = hashlib.sha256()
    for path in sorted(files):
        if path.is_file():
            sha.update(str(path.relative_to(root)).encode() + b"\0" + path.read_bytes() + b"\0")
    return sha.hexdigest()


def publish_existing(path):
    """Channel migration only: require the exact archive currently served by the public site.

    The explicitly authorized historical public build may predate release_grade. This never packages
    a new trial build, changes its signing facts, or relaxes the normal package/install gate.
    """
    release = json.loads(path.read_text())
    archive = path.parent / release["filename"]
    assert release["product"] == "Folio" and release["bundle_id"] == release_grade.BUNDLE_ID
    assert release["filename"] == f"Folio-{release['version']}-{release['build']}-arm64.zip"
    assert archive.stat().st_size == release["bytes"] and digest(archive) == release["sha256"]
    published = json.loads(run("curl", "-4", "--fail", "--silent", "--show-error", "--max-time", "30", PUBLIC_RELEASE))
    for key in ("version", "build", "filename", "bytes", "sha256", "source_commit", "source_sha256", "signature", "notarized"):
        assert published[key] == release[key], f"Public release differs: {key}"
    public_zip = urljoin(PUBLIC_RELEASE, published["download_url"])
    assert urlsplit(public_zip).scheme == "https" and urlsplit(public_zip).netloc == urlsplit(PUBLIC_RELEASE).netloc
    assert json.loads(run("gh", "api", f"repos/{GITHUB_REPOSITORY}"))["private"] is False
    commit = release["source_commit"]
    assert json.loads(run("gh", "api", f"repos/{GITHUB_REPOSITORY}/commits/{commit}"))["sha"] == commit
    links = github_assets(release)
    with tempfile.TemporaryDirectory(prefix="folio-github-", dir=ROOT / "build") as temporary:
        work = Path(temporary)
        downloaded = work / "online.zip"
        run("curl", "-4", "--fail", "--silent", "--show-error", "--max-time", "90", "--output", str(downloaded), public_zip)
        assert digest(downloaded) == release["sha256"], "Public ZIP differs from the original archive"
        source = work / "source"
        source.mkdir()
        source_tar = work / "source.tar"
        run("git", "-C", str(ROOT), "archive", "--output", str(source_tar), commit)
        run("tar", "-xf", str(source_tar), "-C", str(source))
        assert source_digest(source) == release["source_sha256"], "Public commit differs from build source fingerprint"
        unpacked = work / "unpacked"
        run("ditto", "-x", "-k", str(archive), str(unpacked))
        app = unpacked / "Folio.app"
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        stamp = json.loads((app / "Contents/Resources/FolioBuild.json").read_text())
        for key in ("version", "build", "source_commit", "source_sha256", "cli_sha256"):
            assert stamp[key] == release[key], f"Archive build stamp differs: {key}"
        assert info["CFBundleIdentifier"] == release["bundle_id"]
        assert info["CFBundleShortVersionString"] == release["version"] and info["CFBundleVersion"] == release["build"]
        run("codesign", "--verify", "--deep", "--strict", str(app))
        assert digest(app / "Contents/Resources/bin/folio") == release["cli_sha256"]
        if release["signature"] == "adhoc" and release["notarized"] is False:
            assert "Signature=adhoc" in run("codesign", "-d", "--verbose=4", str(app))
        else:
            release_grade.grade(app)
        metadata = work / "release.json"
        metadata.write_text(json.dumps(public_metadata(release), ensure_ascii=False, indent=2) + "\n")
        checksum = work / "SHA256SUMS.txt"
        checksum.write_text(f"{release['sha256']}  {release['filename']}\n")
        notes = work / "notes.md"
        signing = "ad-hoc 签名，未经过 Apple 公证" if release["signature"] == "adhoc" else "Developer ID 签名，已公证并装订"
        notes.write_text(f"Folio · 文页 {release['version']}（构建 {release['build']}）\n\n"
                         f"将官网已公开的同字节安装包迁移至 GitHub Release。Apple 芯片 Mac，macOS {release['minimum_macos']}+。\n\n"
                         f"此历史包为{signing}；签名状态保持原样。本次没有重新编译、签名、公证或安装。\n\n"
                         f"- 源码提交：{commit}\n- 大小：{release['bytes']} 字节\n- SHA-256：`{release['sha256']}`\n")
        releases = json.loads(run("gh", "api", f"repos/{GITHUB_REPOSITORY}/releases?per_page=100"))
        existing = next((item for item in releases if item["tag_name"] == links["tag"]), None)
        if existing is None:
            run("gh", "release", "create", links["tag"], str(archive), str(checksum), str(metadata),
                "--repo", GITHUB_REPOSITORY, "--target", commit, "--draft", "--title",
                f"Folio {release['version']} ({release['build']})", "--notes-file", str(notes))
        staged_release = existing or next(item for item in json.loads(run("gh", "api", f"repos/{GITHUB_REPOSITORY}/releases?per_page=100"))
                                         if item["tag_name"] == links["tag"])
        if staged_release["draft"]:
            assert staged_release["target_commitish"] == commit, "Draft release targets a different source commit"
        else:
            assert json.loads(run("gh", "api", f"repos/{GITHUB_REPOSITORY}/commits/{links['tag']}"))["sha"] == commit, "Release tag points at a different source commit"
        readback = work / "readback"
        run("gh", "release", "download", links["tag"], "--repo", GITHUB_REPOSITORY, "--dir", str(readback))
        assert digest(readback / release["filename"]) == release["sha256"], "GitHub ZIP differs"
        assert (readback / "release.json").read_bytes() == metadata.read_bytes(), "GitHub metadata differs"
        assert (readback / "SHA256SUMS.txt").read_bytes() == checksum.read_bytes(), "GitHub checksum differs"
        if existing is None or existing["draft"]:
            run("gh", "release", "edit", links["tag"], "--repo", GITHUB_REPOSITORY, "--draft=false", "--latest")
        assert json.loads(run("gh", "api", f"repos/{GITHUB_REPOSITORY}/commits/{links['tag']}"))["sha"] == commit
    print(json.dumps({"ok": True, **links, "sha256": release["sha256"], "bytes": release["bytes"],
                      "source_commit": commit, "signature": release["signature"], "notarized": release["notarized"]}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=DEFAULT_APP)
    parser.add_argument("--out", type=Path, default=ROOT / "build/release")
    parser.add_argument("--stamp", action="store_true", help="Record build provenance before signing; called by build.sh")
    parser.add_argument("--adopt", action="store_true", help="Check that a build made on another Mac is this commit, these sources and this build number; called by build.sh")
    parser.add_argument("--stamp-cli", action="store_true", help="Record the bundled command's digest after its Developer ID signature; called by build.sh")
    parser.add_argument("--publish-existing", type=Path, metavar="RELEASE_JSON",
                        help="Publish the exact currently public archive to GitHub; no build, signing, installation or website deployment")
    args = parser.parse_args()
    if args.publish_existing:
        if args.stamp or args.adopt or args.stamp_cli:
            parser.error("--publish-existing cannot modify build stamps")
        publish_existing(args.publish_existing.resolve())
        return
    app = args.app.resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == "cyou.tianli.TLMarkdown", "Unexpected application identity"
    assert info["CFBundleDisplayName"] == "Folio", "Unexpected display name"
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    stamp_file = app / "Contents/Resources/FolioBuild.json"
    if args.stamp:
        stamp = {"source_commit": run("git", "-C", str(ROOT), "rev-parse", "HEAD"),
                 "source_sha256": source_digest(), "built_at": datetime.now(timezone.utc).isoformat(),
                 "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
                 "cli_sha256": digest(app / 'Contents/Resources/bin/folio')}
        stamp_file.write_text(json.dumps(stamp, ensure_ascii=False, indent=2) + "\n")
        return
    stamp = json.loads(stamp_file.read_text())
    if args.adopt:
        commit, count = run("git", "-C", str(ROOT), "rev-parse", "HEAD"), run("git", "-C", str(ROOT), "rev-list", "--count", "HEAD")
        assert stamp["source_commit"] == commit, f"Prebuilt app is commit {stamp['source_commit'][:7]}, this checkout is {commit[:7]}"
        assert stamp["source_sha256"] == source_digest(), "Prebuilt app was built from different sources than this checkout"
        assert stamp["build"] == info["CFBundleVersion"] == count, "Prebuilt app's build number is not this checkout's commit count"
        assert stamp["version"] == info["CFBundleShortVersionString"], "Build metadata mismatch"
        assert digest(app / "Contents/Resources/bin/folio") == stamp["cli_sha256"], "CLI changed after the build"
        return
    if args.stamp_cli:
        stamp["cli_sha256"] = digest(app / "Contents/Resources/bin/folio")
        stamp_file.write_text(json.dumps(stamp, ensure_ascii=False, indent=2) + "\n")
        return
    assert stamp["source_sha256"] == source_digest(), "Sources changed after build; rebuild before packaging"
    assert stamp["version"] == info["CFBundleShortVersionString"] and stamp["build"] == info["CFBundleVersion"], "Build metadata mismatch"
    run("codesign", "--verify", "--deep", "--strict", str(app))
    assert b"/Users/" not in executable.read_bytes(), "Developer debug paths remain in the distributed executable"
    try:
        release_grade.grade(app)
    except release_grade.BelowGrade as error:
        raise SystemExit(f"Not a release package: {error}")
    architectures = run("lipo", "-archs", str(executable)).split()
    # No external runtime is used. Inspect load commands instead of assuming a small bundle is portable.
    dependencies = run("otool", "-L", str(executable)).splitlines()[1:]
    for line in dependencies:
        dependency = line.strip().split(" (", 1)[0]
        assert dependency.startswith(("/usr/lib/", "/System/Library/", "@rpath/libswift")), f"Unexpected runtime dependency: {dependency}"
    resources = app / "Contents/Resources"
    cli = resources / 'bin/folio'
    assert cli.is_file() and digest(cli) == stamp['cli_sha256'], 'CLI missing or changed after build'
    assert cli.stat().st_size <= 2000000, 'CLI size budget exceeded'
    assert b'/Users/' not in cli.read_bytes(), 'Developer paths remain in CLI'
    run('codesign', '--verify', '--strict', str(cli))
    assert (resources / 'graph-view.html').is_file(), 'Missing graph template'
    for name in ("Editor/index.html", "Editor/editor.js", "Editor/katex.js", "Editor/katex.css", "Editor/highlight.js", "Editor/mermaid.js", "THIRD-PARTY-NOTICES.txt", "欢迎使用.md"):
        assert (resources / name).is_file(), f"Missing bundled resource: {name}"
    assert (resources / f"{info['CFBundleIconFile']}.icns").is_file(), "Info.plist icon is missing from the bundle"
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
        # The grade of what a downloader actually unpacks: signature, hardened runtime, stapled ticket, Gatekeeper.
        verdict = release_grade.grade(extracted / "Folio.app")
        shutil.copyfile(packed, archive)
    metadata = {"product": "Folio", "bundle_id": info["CFBundleIdentifier"], **stamp,
                "minimum_macos": info["LSMinimumSystemVersion"], "architectures": architectures,
                "filename": filename, "bytes": archive.stat().st_size, "sha256": digest(archive),
                "signature": "developer-id", "signing_identity": verdict["identity"],
                "hardened_runtime": True, "notarized": True, "stapled": True, "gatekeeper": verdict["gatekeeper"],
                "executable_sha256": verdict["executable_sha256"],
                "verification": {"archive_signature": "passed", "bundled_resources": "passed",
                                 "system_runtime_dependencies": "passed", "gui_final_package": "pending"}}
    metadata.update({key: value for key, value in github_assets(metadata).items() if key != "tag"})
    (out / "release.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
    (out / "SHA256SUMS.txt").write_text(f"{metadata['sha256']}  {filename}\n")
    print(json.dumps(metadata, ensure_ascii=False, indent=2))
    print(f"Staged: {archive}")


if __name__ == "__main__":
    main()
