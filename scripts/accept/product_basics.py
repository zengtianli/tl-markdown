#!/usr/bin/env python3
"""Actual Folio binary, receipt-bound candidate or installed default; original hidden lifecycle suite."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT.parent / 'chapter/engine'))
import app_sop
import yaml


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=Path(os.environ.get('SOP_FOLIO_BASICS_APP', '/Applications/Folio.app')))
    parser.add_argument('--receipt', type=Path, default=Path(os.environ.get('SOP_FOLIO_BASICS_RECEIPT', ROOT / 'perf/build-receipt.json')))
    args = parser.parse_args()
    spec = json.loads(os.environ['SOP_PRODUCT_BASICS_SPEC'])
    assert spec['app_id'] == os.environ['SOP_APP_ID'] == 'folio-mac'
    out = Path(os.environ['SOP_OUT_DIR']).resolve()
    assert out.is_relative_to(ROOT / 'perf/acceptance')
    run = out / ('product-basics-' + uuid.uuid4().hex)
    run.mkdir(parents=True)
    meta = yaml.safe_load((ROOT / 'project.yaml').read_text())
    app = {'id': 'folio-mac', 'repo': ROOT, 'form': 'mac', 'bundle_id': meta['bundle_id'], 'sop': meta['sop']}
    checks, error, result, before = {}, None, {}, {}
    try:
        valid, reason = app_sop.verify_build_receipt(app, args.app.resolve(), args.receipt.resolve())
        if not valid:
            raise ValueError('拒绝未绑定当前源码的产品：' + reason)
        receipt_bytes = args.receipt.read_bytes()
        receipt = json.loads(receipt_bytes)
        before = app_sop.artifact_snapshot(args.app)
        env = dict(os.environ, FOLIO_LIFECYCLE_OUT=str(run / 'lifecycle'))
        tested = subprocess.run(['bash', str(ROOT / 'scripts/accept/lifecycle.sh'), str(args.app.resolve())], cwd=ROOT,
                                env=env, text=True, capture_output=True, timeout=280)
        (run / 'lifecycle.log').write_text(tested.stdout + tested.stderr)
        result_path = run / 'lifecycle/lifecycle.json'
        result = json.loads(result_path.read_text())
        checks = result['checks']
        for row in spec['features'].values():
            for key in row['required_checks']:
                if key not in checks:
                    raise ValueError('真实产品原件缺必测行为：' + key)
        valid, reason = app_sop.verify_build_receipt(app, args.app.resolve(), args.receipt.resolve())
        checks['settings.candidate_receipt_unchanged'] = valid and args.receipt.read_bytes() == receipt_bytes and app_sop.artifact_snapshot(args.app) == before
        checks['settings.isolated_suite_complete'] = tested.returncode == 0 and result.get('ok') is True
        checks['updates.private_preferences_removed'] = result.get('update_preference_domain_removed') is True
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        error = str(exc)
        checks['settings.real_product_execution'] = False
    required = [key for row in spec['features'].values() for key in row['required_checks']]
    passed = error is None and all(checks.get(key) is True for key in required) and all(checks.values())
    raw = {'schema_version': 1, 'app_id': spec['app_id'], 'spec_digest': spec['digest'], 'checks': checks,
           'subject': 'installed' if args.app.resolve() == Path('/Applications/Folio.app') else 'candidate',
           'app': str(args.app.resolve()), 'artifact': before, 'receipt': str(args.receipt.resolve()),
           'receipt_sha256': sha(args.receipt) if args.receipt.is_file() else None,
           'error': error, 'scope': 'Actual Folio process and bundled CLI; native controls/actions offscreen; production configuration reconcile via isolated cloud directory. Apple server cross-device transfer not tested.',
           'upstream': {'path': str((run / 'lifecycle/lifecycle.json').relative_to(ROOT)),
                        'sha256': sha(run / 'lifecycle/lifecycle.json') if (run / 'lifecycle/lifecycle.json').is_file() else None}}
    raw_path = run / 'raw.json'
    raw_path.write_text(json.dumps(raw, ensure_ascii=False, indent=2) + '\n')
    features = {}
    for key in spec['features']:
        names = [name for name in checks if name.startswith(key + '.')]
        features[key] = {'result': 'passed' if names and all(checks[n] is True for n in names) else 'failed',
                         'method': 'ui_automation' if key in ('settings', 'shortcuts') else 'real_product',
                         'evidence': str(raw_path.relative_to(ROOT)), 'evidence_sha256': sha(raw_path), 'checks': names}
    detail = {'schema_version': 1, 'app_id': spec['app_id'], 'spec_digest': spec['digest'], 'features': features,
              'summary': f'Folio {raw["subject"]} 基础功能 {"通过" if passed else "失败"}；固定 14 项实际行为；隔离云链路',
              'scope': raw['scope'], 'error': error}
    (out / 'product_basics.detail.json').write_text(json.dumps(detail, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'summary': detail['summary'], 'failed': [k for k, v in checks.items() if v is not True], 'error': error}, ensure_ascii=False))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
