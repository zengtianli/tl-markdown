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


def signature_grade(app):
    """Stable product/team, hardened runtime and timestamps; does not grant distribution."""
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
    return {"ok": True, "app": str(app), "bundle_id": BUNDLE_ID,
            "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
            "identity": IDENTITY, "hardened_runtime": True, "secure_timestamp": True,
            "provisioning_profile": profile_state, "executable_sha256": digest(executable),
            "code": [str(path.relative_to(app)) for path in code_files]}


def grade(app):
    """Public packages always require the original notarization and Gatekeeper gate."""
    app = Path(app)
    result = signature_grade(app)
    code, staple = run("/usr/bin/xcrun", "stapler", "validate", app)
    if code:
        raise BelowGrade(f"没有装订公证票据：{staple[-300:]}")
    code, assessment = run("/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=2", app)
    if code or "source=Notarized Developer ID" not in assessment:
        raise BelowGrade(f"Gatekeeper 未放行：{assessment[-300:]}")
    result.update(stapled=True, gatekeeper="Notarized Developer ID")
    return result


def verify_local_source(app, receipt, signing_receipt):
    """Exact file and signature chain, independent of later handoff-only Git commits."""
    app, receipt, signing_receipt = Path(app), Path(receipt), Path(signing_receipt)
    candidate, signed = json.loads(receipt.read_text()), json.loads(signing_receipt.read_text())
    if signed.get('kind') != 'local-iteration' or signed.get('distribution') is not False:
        raise BelowGrade('不是本地迭代签名链')
    if signed['input_receipt_sha256'] != digest(receipt) or signed['unsigned_artifact'] != candidate['artifact']:
        raise BelowGrade('签名链没有绑定原候选回执')
    for relative, expected in candidate['source']['files'].items():
        path = (ROOT / relative).resolve(strict=True)
        if not path.is_relative_to(ROOT) or digest(path) != expected:
            raise BelowGrade(f'当前源码与签名原候选不同：{relative}')
    verdict = signature_grade(app)
    if any(verdict[key] != signed[key] for key in ('bundle_id', 'version', 'build', 'executable_sha256')):
        raise BelowGrade('签名原件与持证机回执不同')
    stamp = json.loads((app / 'Contents/Resources/FolioBuild.json').read_text())
    if stamp['source_commit'] != candidate['source']['commit'] or digest(app / 'Contents/Resources/bin/folio') != stamp['cli_sha256']:
        raise BelowGrade('包内原构建来源或 CLI 不符')
    return verdict


def sign_local(source, receipt, out):
    """Certificate owner signs a source/asset-bound copy only; never compiles or installs."""
    receipt = Path(receipt).resolve(strict=True)
    recorded = json.loads(receipt.read_text())
    for relative, expected in recorded['source']['files'].items():
        path = (ROOT / relative).resolve(strict=True)
        if not path.is_relative_to(ROOT) or digest(path) != expected:
            raise BelowGrade(f"签名前源码输入不匹配：{relative}")
    out = Path(out).resolve()
    if not out.is_relative_to(ROOT / 'build') or out.exists():
        raise BelowGrade("签名输出必须是本产品 build/ 下尚不存在的目录")
    out.mkdir(parents=True)
    code, output = run('/usr/bin/ditto', '-x', '-k', source, out)
    if code:
        raise BelowGrade(output)
    apps = list(out.glob('*.app'))
    if len(apps) != 1:
        raise BelowGrade("候选归档没有唯一 App")
    app = apps[0]
    artifact = recorded['artifact']
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if (info['CFBundleIdentifier'] != BUNDLE_ID or str(info['CFBundleVersion']) != artifact['build']
            or info['CFBundleShortVersionString'] != artifact['version'] or digest(app / artifact['executable']) != artifact['sha256']):
        raise BelowGrade("候选与原构建回执不匹配")
    icon = artifact['icon']
    if digest(app / icon['path']) != icon['sha256']:
        raise BelowGrade("候选图标不匹配")
    code, output = run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
    if code:
        raise BelowGrade(output)
    cli = app / 'Contents/Resources/bin/folio'
    stamp = json.loads((app / 'Contents/Resources/FolioBuild.json').read_text())
    if digest(cli) != stamp['cli_sha256'] or stamp['source_commit'] != recorded['source']['commit']:
        raise BelowGrade("候选 CLI/构建来源不匹配")
    for args in [("--identifier", BUNDLE_ID + '.cli', str(cli)), (str(app),)]:
        if len(args) == 1:
            subprocess.run([sys.executable, str(ROOT / 'scripts/package-release.py'), '--app', str(app), '--stamp-cli'], check=True)
        subprocess.run(['/usr/bin/codesign', '--force', '--options', 'runtime', '--timestamp', '--sign', IDENTITY, *args], check=True)
    result = signature_grade(app)
    archive = out / 'Folio-local-signed.zip'
    subprocess.run(['/usr/bin/ditto', '-c', '-k', '--keepParent', str(app), str(archive)], check=True)
    result.update(kind='local-iteration', distribution=False, notarization_requested=False,
                  input_receipt_sha256=digest(receipt), input_archive_sha256=digest(source),
                  unsigned_artifact=artifact, signed_archive=str(archive), signed_archive_sha256=digest(archive))
    (out / 'signing-receipt.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    return result


def install_local(source):
    """Explicit local iteration, same stable signature, atomic rollback; no public package gate bypass."""
    source = Path(source).resolve(strict=True)
    verdict = signature_grade(source)
    if DESTINATION.is_symlink():
        raise BelowGrade("已装 App 为软链，拒绝替换")
    if DESTINATION.exists():
        signature_grade(DESTINATION)
        def requirement(path):
            code, detail = run('/usr/bin/codesign', '-d', '-r-', path)
            if code: raise BelowGrade(detail)
            return next(line for line in detail.splitlines() if line.startswith('designated =>'))
        if requirement(source) != requirement(DESTINATION):
            raise BelowGrade("稳定 designated requirement 改变，拒绝影响现有授权")
    processes = subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True)
    for line in processes.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) == 2 and fields[1].startswith(str(DESTINATION) + '/Contents/MacOS/'):
            raise BelowGrade("Folio 正在运行，保留现有进程，未替换；沿原队列在空闲时接续")
    stage = Path(tempfile.mkdtemp(prefix='.Folio-local-install-', dir=DESTINATION.parent))
    candidate, previous = stage / 'Candidate.app', stage / 'Previous.app'
    swapped = False
    try:
        subprocess.run(['/usr/bin/ditto', str(source), str(candidate)], check=True)
        if signature_grade(candidate)['executable_sha256'] != verdict['executable_sha256']:
            raise BelowGrade("安装副本与签名原件不同")
        if DESTINATION.exists(): DESTINATION.rename(previous)
        candidate.rename(DESTINATION); swapped = True
        installed = signature_grade(DESTINATION)
        if installed['executable_sha256'] != verdict['executable_sha256']:
            raise BelowGrade("装机字节不匹配")
        subprocess.run([sys.executable, str(ROOT / 'scripts/install-cli.py'), str(DESTINATION)], check=True)
    except Exception:
        if swapped: DESTINATION.rename(stage / 'Rejected.app')
        if previous.exists(): previous.rename(DESTINATION)
        raise
    # Keep the previous exact bundle in this transaction for deliberate rollback, never delete it.
    installed.update(kind='local-iteration', distribution=False, notarization_requested=False,
                     installed=str(DESTINATION), previous=str(previous) if previous.exists() else None, transaction=str(stage))
    (stage / 'receipt.json').write_text(json.dumps(installed, ensure_ascii=False, indent=2) + '\n')
    return installed


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
    parser.add_argument("action", choices=["check", "install", "check-local", "sign-local", "install-local", "verify-local-source"])
    parser.add_argument("path", type=Path)
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--signing-receipt", type=Path)
    args = parser.parse_args()
    try:
        if args.action == 'verify-local-source':
            if not args.receipt or not args.signing_receipt: parser.error('two original receipts required')
            result = verify_local_source(args.path, args.receipt, args.signing_receipt)
        elif args.action == 'sign-local':
            if not args.receipt or not args.out: parser.error('sign-local requires --receipt and --out')
            result = sign_local(args.path, args.receipt, args.out)
        elif args.action == 'install-local': result = install_local(args.path)
        elif args.action == 'check-local': result = signature_grade(args.path)
        else: result = grade(args.path) if args.action == "check" else install(args.path)
    except BelowGrade as error:
        print(json.dumps({"ok": False, "reason": str(error)}, ensure_ascii=False, indent=2))
        raise SystemExit(1)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
