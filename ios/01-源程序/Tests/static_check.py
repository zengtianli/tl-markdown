#!/usr/bin/env python3
"""Static wiring checks only; never claimed as UI or permission acceptance."""
import hashlib
import json
import pathlib
import plistlib
import re
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
family = root.parents[1]
shared = pathlib.Path.home() / "Dev/tools/dev/lib/tools/macapp/swift-shared"
for name in ("LaneSignal.swift", "PlatformCompat.swift"):
    assert (root / "Shared" / name).read_bytes() == (shared / name).read_bytes(), name
spec = (root / "project.yml").read_text()
for name in ("Models.swift", "IndexEngine.swift"):
    assert f"${{FOLIO_FAMILY_ROOT}}/Sources/{name}" in spec
    assert not (root / "Sources" / name).exists(), "duplicated Foundation source"
assert "${FOLIO_FAMILY_ROOT}/Resources/Editor" in spec
assert "supportedDestinations: [iOS, visionOS]" in spec
# When generated, check XcodeGen's actual output: forcing 1,2 on the
# universal target silently omits the native Vision device family (7).
generated = root / "FolioMobile.xcodeproj/project.pbxproj"
if generated.is_file():
    project = generated.read_text()
    assert 'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator xros xrsimulator"' in project
    assert 'TARGETED_DEVICE_FAMILY = "1,2,7"' in project, "native Vision device family missing"
registration = (root / "project.yaml").read_text()
assert "source_root: ../.." in registration
for source in ("Sources/Models.swift", "Sources/IndexEngine.swift", "Resources/Editor/**", "AppIcon.icns", "Info.plist"):
    assert source in registration
assert "component: folio-mac" in registration and "not_applicable:" in registration
assert "passed" not in registration
for script in (root / "scripts").glob("*.sh"):
    subprocess.run(["bash", "-n", str(script)], check=True)
plistlib.loads((root / "Resources/PrivacyInfo.xcprivacy").read_bytes())
for contents in (root / "Resources/Assets.xcassets").rglob("Contents.json"):
    value = json.loads(contents.read_text())
    for item in value.get("images", []):
        assert (contents.parent / item["filename"]).is_file()
    for layer in value.get("layers", []):
        assert (contents.parent / layer["filename"]).is_dir()
editor = (root / "Sources/MobileEditor.swift").read_text()
assert "nonPersistent" in editor and 'resource-type' in editor
assert "TL_PREVIEW_ONLY" in editor and "window.tl.receive" in editor
assert 'contains("..")' in editor and "startAccessingSecurityScopedResource" in (root / "Sources/DocumentWorkspace.swift").read_text()
bridge = re.search(r'const folioHandler =.*?folioHandler.postMessage =.*?;', editor, re.S).group(0)
# Exercise the actual injected stamp adapter with queued messages. This is a
# JavaScript bridge test, not proof of WKWebView/Files provider acceptance.
subprocess.run(["node", "-e", """
const vm=require('vm'), assert=require('assert'); const messages=[];
const context={window:{webkit:{messageHandlers:{editor:{postMessage:body=>messages.push(body)}}}}};
vm.createContext(context); vm.runInContext(process.argv[1],context);
context.window.__folioEditorGeneration='generation-A';
context.window.webkit.messageHandlers.editor.postMessage({type:'change',id:'doc',text:'old event',mobileGeneration:'forged'});
context.window.__folioEditorGeneration='generation-B';
context.window.webkit.messageHandlers.editor.postMessage({type:'change',id:'doc',text:'new event'});
assert.equal(messages[0].mobileGeneration,'generation-A');
assert.equal(messages[1].mobileGeneration,'generation-B');
console.log('PASS injected bridge: queued messages retain their actual load generation');
""", bridge], check=True)
print("PASS static: shared sources, Editor binding, universal target, registration, script syntax, brand assets, privacy declaration")
print("Shared source SHA256:")
for path in (family / "Sources/Models.swift", family / "Sources/IndexEngine.swift", family / "Info.plist", family / "AppIcon.icns"):
    print(path.relative_to(family), hashlib.sha256(path.read_bytes()).hexdigest())
