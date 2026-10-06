#!/usr/bin/env python3
"""Create a hosted-XCTest XcodeGen overlay from a verified frozen SDK build.

Does not build, boot, install, launch, or modify the original/frozen checkout.
Run in the native owner's allocated slot, after the new SDK build receipt exists.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import yaml

REPO = Path(__file__).resolve().parents[2]
SIM_MODULE = Path("/Users/tianli/Dev/tools/dev/lib/tools/macapp/ios")

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def overlay(component, family, destination, test_source):
    component, family = component.resolve(), family.resolve()
    document = yaml.safe_load((component / "project.yml").read_text())
    assert document["targets"]["FolioMobile"]["supportedDestinations"] == ["iOS", "visionOS"]
    # Frozen sources live outside this overlay; flat groups avoid cross-root parent cycles.
    document.setdefault("options", {})["createIntermediateGroups"] = False
    # Every compile/resource path is pinned to the verified frozen tree, not
    # FOLIO_FAMILY_ROOT from a live shell or the out-of-repository overlay folder.
    for template in document["targetTemplates"].values():
        if "info" in template:
            template["info"]["path"] = str(destination / "Generated/FolioMobile-Info.plist")
        for item in template.get("sources", []):
            path = item["path"]
            if path.startswith("${FOLIO_FAMILY_ROOT}/"):
                item["path"] = str(family / path.removeprefix("${FOLIO_FAMILY_ROOT}/"))
            else:
                item["path"] = str(component / path)
    app = document["targets"]["FolioMobile"]
    # Release identity now lives on the actual target for ASC preflight.
    # Keep the hosted overlay's generated plist outside the frozen source tree.
    if "info" in app:
        app["info"]["path"] = str(destination / "Generated/FolioMobile-Info.plist")
    app.setdefault("settings", {}).setdefault("base", {}).update({
        "PRODUCT_MODULE_NAME": "Folio", "ENABLE_TESTABILITY": "YES",
    })
    # Production properties are preserved; only the output path changes.
    app["scheme"] = {"testTargets": ["FolioHostedIntegration"]}
    test_source = test_source.resolve()
    if not test_source.is_file():
        raise ValueError("independently frozen hosted test is missing")
    document["targets"]["FolioHostedIntegration"] = {
        "type": "bundle.unit-test",
        "supportedDestinations": ["iOS", "visionOS"],
        "sources": [{"path": str(test_source)}],
        "dependencies": [{"target": "FolioMobile"}],
        "settings": {"base": {
            "PRODUCT_BUNDLE_IDENTIFIER": "cyou.tianli.TLMarkdown.mobile.hosted-tests",
            "GENERATE_INFOPLIST_FILE": "YES",
            "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Folio.app/Folio",
            "BUNDLE_LOADER": "$(TEST_HOST)",
        }},
    }
    return document

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", required=True, type=Path)
    parser.add_argument("--platform", required=True, choices=["iphone", "ipad", "vision"])
    parser.add_argument("--workdir", required=True, type=Path)
    parser.add_argument("--write", action="store_true", help="explicitly freeze tests and write overlay; default is readonly")
    args = parser.parse_args(argv)
    # Existing official-local verifier rejects old hashes, live paths, foreign
    # SDKs, changed binary/source copies, and wrong Xcode. It performs no build.
    sys.path.insert(0, str(SIM_MODULE))
    import sim_lane
    built = sim_lane.reuse_build(args.receipt, "folio", REPO, args.platform,
                                 scheme="FolioMobile", fixture_debug=False)
    work = Path(built["work_dir"]).resolve()
    component = Path(built["reuse"]["source_copy"]).resolve()
    family = work / "src"
    live_test = REPO / "Tests/HostedIntegrationTests.swift"
    test_bytes = live_test.read_bytes()
    test_hash = hashlib.sha256(test_bytes).hexdigest()
    workdir = args.workdir.resolve()
    out = workdir / "iphone"
    if out.is_relative_to(REPO.parents[1]) or out.is_relative_to(work):
        raise ValueError("workdir must be outside live and frozen source trees")
    if not args.write:
        print(json.dumps({"status":"readonly-validation-only","input_sha256":built["reuse"]["input_sha256"],"test_sha256":test_hash,"planned_out":str(out),"no_build":True,"no_boot":True},indent=2))
        return
    out.mkdir(parents=True, exist_ok=True)
    spec = out / "project.hosted.yml"
    if spec.exists() or (out / "prepared.json").exists() or (out / "test_src").exists():
        raise FileExistsError("use a fresh output directory; previous evidence is preserved")
    test_directory = out / "test_src"
    test_directory.mkdir()
    test = test_directory / "HostedIntegrationTests.swift"
    test.write_bytes(test_bytes)
    if sha(test) != test_hash or sha(live_test) != test_hash:
        raise ValueError("hosted test changed while freezing; no manifest issued")
    document = overlay(component, family, out, test)
    spec.write_text(yaml.safe_dump(document, allow_unicode=True, sort_keys=False))
    manifest = {
        "status": "prepared-not-built", "platform": args.platform,
        "receipt": str(args.receipt.resolve()), "receipt_sha256": sha(args.receipt),
        "input_sha256": built["reuse"]["input_sha256"],
        "source_copy": str(component), "family_copy": str(family),
        "test_src": str(test), "test_live_source": str(live_test),
        "hosted_test_sha256": sha(test), "overlay_sha256": sha(spec),
        "prepare_script_sha256": sha(__file__),
        "prepare_script": str(Path(__file__).resolve()),
        "xcode": built["xcode"],
        "boundary": "SDK integration only; no Files provider grants, picker UI, OS scene or crash claim",
    }
    (out / "prepared.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    main()
