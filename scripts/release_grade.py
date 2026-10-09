#!/usr/bin/env python3
"""Folio's release grade: what may enter /Applications or a download, on any Mac.

    python3 scripts/release_grade.py check <Folio.app>            read-only verdict as JSON, exit 1 below grade
    python3 scripts/release_grade.py install <Folio-…zip | .app>  verify, then replace /Applications/Folio.app

The grade is the package a stranger's Mac opens without a prompt: every Mach-O signed by the Developer ID
below with the hardened runtime and a secure timestamp, Apple's notarization ticket stapled, Gatekeeper
answering "Notarized Developer ID", and no provisioning profile that lists devices. Ad-hoc and Apple
Development signatures are trial builds and are refused here. `build.sh --install` installs through this
file, and a second Mac installs the same ZIP through it, so there is one gate.

Never launches, quits or restarts Folio.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = "cyou.tianli.TLMarkdown"
TEAM = "B9LJH93LA4"
IDENTITY = f"Developer ID Application: tianli Zeng ({TEAM})"
DESTINATION = Path("/Applications/Folio.app")
MACH_O = {b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}


class BelowGrade(Exception):
    pass


def run(*args):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True)
    return result.returncode, (result.stdout + result.stderr).strip()


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def mach_o_files(app):
    found = []
    for path in sorted(app.rglob("*")):
        if path.is_file() and not path.is_symlink():
            with path.open("rb") as stream:
                if stream.read(4) in MACH_O:
                    found.append(path)
    return found


def grade(app):
    """The verdict for one .app; raises BelowGrade with the first reason it is not a release package."""
    app = Path(app)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != BUNDLE_ID:
        raise BelowGrade(f"bundle id 是 {info.get('CFBundleIdentifier')}，不是 {BUNDLE_ID}")
    code, output = run("/usr/bin/codesign", "--verify", "--deep", "--strict", app)
    if code:
        raise BelowGrade(f"签名校验未通过：{output[-400:]}")
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    code_files = mach_o_files(app)
    if executable not in code_files:
        raise BelowGrade("主可执行文件不是 Mach-O")
    for path in code_files:
        # The bundle's own signature is the one on its main executable; ask for it through the bundle.
        code, detail = run("/usr/bin/codesign", "-d", "--verbose=4", app if path == executable else path)
        name = str(path.relative_to(app))
        if code:
            raise BelowGrade(f"{name} 读不到签名：{detail[-300:]}")
        lines = detail.splitlines()
        if "Signature=adhoc" in lines:
            raise BelowGrade(f"{name} 是 adhoc 签名（试构建），不能安装或分发")
        if f"Authority={IDENTITY}" not in lines or f"TeamIdentifier={TEAM}" not in lines:
            authority = next((line for line in lines if line.startswith("Authority=")), "Authority=无")
            raise BelowGrade(f"{name} 的签名身份是 {authority}，要求 {IDENTITY}")
        flags = next((line for line in lines if line.startswith("CodeDirectory ")), "")
        if "runtime" not in flags:
            raise BelowGrade(f"{name} 没有 hardened runtime")
        if not any(line.startswith("Timestamp=") for line in lines):
            raise BelowGrade(f"{name} 没有安全时间戳")
    profile = app / "Contents/embedded.provisionprofile"
    profile_state = "无"
    if profile.exists():
        decoded = subprocess.run(["/usr/bin/security", "cms", "-D", "-i", str(profile)], capture_output=True)
        if decoded.returncode:
            raise BelowGrade("包内描述文件读不出来")
        if "ProvisionedDevices" in plistlib.loads(decoded.stdout):
            raise BelowGrade("包内描述文件带设备清单（只在登记过的设备上能跑）；发行包用 Developer ID 的直接分发描述文件")
        profile_state = "有，无设备清单"
    code, staple = run("/usr/bin/xcrun", "stapler", "validate", app)
    if code:
        raise BelowGrade(f"没有装订公证票据：{staple[-300:]}")
    code, assessment = run("/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=2", app)
    if code or "source=Notarized Developer ID" not in assessment:
        raise BelowGrade(f"Gatekeeper 未放行：{assessment[-300:]}")
    return {"ok": True, "app": str(app), "bundle_id": BUNDLE_ID,
            "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
            "identity": IDENTITY, "hardened_runtime": True, "secure_timestamp": True, "stapled": True,
            "gatekeeper": "Notarized Developer ID", "provisioning_profile": profile_state,
            "executable_sha256": digest(executable),
            "code": [str(path.relative_to(app)) for path in code_files]}


def install(source):
    source = Path(source).expanduser().resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="folio-install-") as temporary:
        if source.suffix == ".zip":
            code, output = run("/usr/bin/ditto", "-x", "-k", source, temporary)
            if code:
                raise BelowGrade(f"安装包解不开：{output[-300:]}")
            apps = [path for path in Path(temporary).iterdir() if path.suffix == ".app"]
            if len(apps) != 1:
                raise BelowGrade("安装包里没有唯一的 App")
            staged = apps[0]
        else:
            staged = source
        verdict = grade(staged)
        if DESTINATION.exists():
            old = plistlib.loads((DESTINATION / "Contents/Info.plist").read_bytes())
            same = (old.get("CFBundleShortVersionString"), old.get("CFBundleVersion")) == (verdict["version"], verdict["build"])
            if same and digest(DESTINATION / "Contents/MacOS" / old["CFBundleExecutable"]) != verdict["executable_sha256"]:
                raise BelowGrade(f"已装的 {verdict['version']} ({verdict['build']}) 与这份包同版本同构建但内容不同；重出包要用新的构建号")
            archive = Path.home() / ".Trash" / f"folio-previous-{int(time.time())}"
            archive.mkdir(parents=True)
            DESTINATION.rename(archive / DESTINATION.name)
            verdict["previous"] = str(archive / DESTINATION.name)
        code, output = run("/usr/bin/ditto", staged, DESTINATION)
        if code:
            raise RuntimeError(f"复制到 {DESTINATION} 失败：{output[-300:]}")
    installed = grade(DESTINATION)
    if installed["executable_sha256"] != verdict["executable_sha256"]:
        raise RuntimeError("装好的 App 与安装包不一致")
    code, link = run(sys.executable, ROOT / "scripts/install-cli.py", DESTINATION)
    if code:
        raise RuntimeError(f"App 已装好，命令行入口没有接上：{link[-300:]}")
    installed.update(installed=str(DESTINATION), cli=link, previous=verdict.get("previous"))
    return installed


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("action", choices=["check", "install"])
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    try:
        result = grade(args.path) if args.action == "check" else install(args.path)
    except BelowGrade as error:
        print(json.dumps({"ok": False, "reason": str(error)}, ensure_ascii=False, indent=2))
        raise SystemExit(1)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
