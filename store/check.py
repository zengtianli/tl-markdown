#!/usr/bin/env python3
"""Version, generated-resource freshness, Info keys, icon and sandbox contract; no network."""
from pathlib import Path
import hashlib
import json
import plistlib
import sys
import yaml

STORE = Path(__file__).resolve().parent
ROOT = STORE.parent

def editor_digest():
    paths = [ROOT / 'Editor' / n for n in ('build.mjs', 'package.json', 'package-lock.json')]
    paths += sorted((ROOT / 'Editor/src').rglob('*'))
    digest = hashlib.sha256()
    for path in sorted(paths):
        if path.is_file(): digest.update(str(path.relative_to(ROOT)).encode() + b'\0' + path.read_bytes() + b'\0')
    return digest.hexdigest()

if sys.argv[1:] == ['--stamp-editor']:
    (STORE / 'Generated/editor-source.sha256').write_text(editor_digest() + '\n')
    raise SystemExit(0)

root = plistlib.loads((ROOT / 'Info.plist').read_bytes())
spec = yaml.safe_load((STORE / 'project.yml').read_text())
target = spec['targets']['Folio']; settings = {**spec['settings']['base'], **target['settings']['base']}
props = target['info']['properties']; entitlements = target['entitlements']['properties']
assert settings['MARKETING_VERSION'] == root['CFBundleShortVersionString'], 'Store version differs from root Info.plist'
assert settings['PRODUCT_BUNDLE_IDENTIFIER'] == root['CFBundleIdentifier']
assert props['CFBundleShortVersionString'] == '$(MARKETING_VERSION)' and props['CFBundleVersion'] == '$(CURRENT_PROJECT_VERSION)'
assert set(root).issubset(props), 'Store Info properties must contain every original key'
for key, value in root.items():
    if key not in ('CFBundleIdentifier', 'CFBundleExecutable', 'CFBundleVersion', 'CFBundleShortVersionString', 'LSMinimumSystemVersion'):
        assert props[key] == value, f'Original Info key changed: {key}'
assert entitlements['com.apple.security.app-sandbox'] and not any('temporary-exception' in k for k in entitlements)
assert 'APP_STORE' in settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'].split()
assert not list((ROOT / 'Sources').rglob('*sync-conflict-*.swift'))
icons = json.loads((STORE / 'Assets.xcassets/AppIcon.appiconset/Contents.json').read_text())['images']
assert len(icons) == 10 and all((STORE / 'Assets.xcassets/AppIcon.appiconset' / item['filename']).is_file() for item in icons)
stamp = STORE / 'Generated/editor-source.sha256'
assert stamp.is_file() and stamp.read_text().strip() == editor_digest(), 'Editor resources absent/stale: bash store/build-editor.sh'
for name in ('index.html', 'editor.js', 'editor.css', 'katex.js', 'katex.css', 'highlight.js', 'mermaid.js'):
    assert (STORE / 'Generated/Editor' / name).is_file(), f'Missing editor resource: {name}'
print(f'store/check.sh: ok (version {settings["MARKETING_VERSION"]}, {len(entitlements)} entitlements, fresh editor resources)')
