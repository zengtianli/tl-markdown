#!/usr/bin/env python3
"""Freeze actual build-for-testing artifacts; default readonly, never compiles."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import sys

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0,"/Users/tianli/Dev/tools/dev/lib/tools/macapp/ios")
import sim_lane

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def products(entries, test_root, package):
    host = Path(entries[0]['TestHostPath'].replace('__TESTROOT__', str(test_root))).resolve()
    test = Path(entries[0]['TestBundlePath'].replace('__TESTROOT__', str(test_root))
                .replace('__TESTHOST__', str(host))).resolve()
    if (not host.is_relative_to(package.resolve()) or not host.is_dir()
            or not test.is_relative_to(package.resolve()) or not test.is_dir() or test.suffix != '.xctest'):
        raise ValueError('actual host/test products must belong to this workdir')
    roots = [host, test]
    paths = [path for root in roots for path in sorted(root.rglob('*')) if path.is_file() or path.is_symlink()]
    if any(not path.resolve().is_relative_to(package.resolve()) for path in paths):
        raise ValueError('hosted product symlink leaves the owned workdir')
    files = {str(path.absolute()): sha(path) for path in paths if path.is_file()}
    if not any(path.is_file() for path in test.rglob('*')):
        raise ValueError('actual hosted test bundle is empty')
    return roots, files

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workdir",required=True,type=Path)
    parser.add_argument("--receipt",required=True,type=Path)
    parser.add_argument("--write",action="store_true",help="explicitly write a new artifact binding; default readonly")
    args = parser.parse_args(argv)
    root = args.workdir.resolve()
    if root.is_relative_to(REPO.parents[1]):
        parser.error("workdir must be outside live source trees")
    package = root/"iphone"
    prepared = json.loads((package/"prepared.json").read_text())
    observation = json.loads((package/"hosted-build-observation.json").read_text())
    if (Path(prepared["receipt"]).resolve()!=args.receipt.resolve()
            or prepared["receipt_sha256"]!=sha(args.receipt)):
        raise ValueError("explicit SDK receipt does not match prepared inputs")
    built = sim_lane.reuse_build(args.receipt,"folio",REPO,"iphone",scheme="FolioMobile",fixture_debug=False)
    if (observation["exit_code"]!=0 or observation["input_stable"] is not True
            or observation["preparation_sha256"]!=sha(package/"prepared.json")
            or observation["log_sha256"]!=sha(observation["log"])):
        raise ValueError("need a real stable successful build-for-testing observation and unchanged log")
    test = Path(prepared["test_src"])
    live_test = REPO/"Tests/HostedIntegrationTests.swift"
    if sha(test)!=prepared["hosted_test_sha256"] or sha(live_test)!=sha(test):
        raise ValueError("live and independently frozen test bytes differ")
    runs = list((package/"dd/Build/Products").glob("*.xctestrun"))
    if len(runs)!=1:
        raise ValueError("need exactly one actual xctestrun")
    plist = plistlib.loads(runs[0].read_bytes())
    entries = [v for k,v in plist.items() if not k.startswith("__")]
    if len(entries)!=1 or not entries[0].get("IsAppHostedTestBundle") or entries[0].get("IsUITestBundle"):
        raise ValueError("only a non-UI hosted test bundle is accepted")
    roots, product_files = products(entries, runs[0].parent, package)
    prepare_script = Path(prepared.get("prepare_script") or root/"prepare.py")
    if sha(prepare_script)!=prepared["prepare_script_sha256"]:
        raise ValueError("actual preparation script binding changed")
    files = [package/"prepared.json",package/"hosted-build-observation.json",Path(observation["log"]),
             package/"project.hosted.yml",package/"FolioMobile.xcodeproj/project.pbxproj",test,live_test,prepare_script,runs[0]]
    binding = {"input_sha256":built["reuse"]["input_sha256"],"test_sha256":sha(test),
               "files":{**{str(path.resolve()):sha(path) for path in files}, **product_files},
               "product_roots": [str(root) for root in roots], "product_files": product_files}
    output = root/"run-expected.json"
    if args.write:
        if output.exists():
            raise FileExistsError("existing artifact binding is preserved; use a fresh workdir")
        output.write_text(json.dumps(binding,ensure_ascii=False,indent=2)+"\n")
    print(json.dumps({"status":"artifact-bound-not-tested" if args.write else "readonly-validation-only",
                      "file_count":len(binding["files"]),"input_sha256":binding["input_sha256"],
                      "test_sha256":binding["test_sha256"],"no_build":True,"no_boot":True},indent=2))

if __name__=="__main__":
    main()
