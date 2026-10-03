#!/usr/bin/env python3
"""Read-only ordinary Release reuse verification and independent external QA binding."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
QA = Path(__file__).resolve().parent
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec); sys.modules[name] = module
    exec(compile(path.read_bytes(), str(path), 'exec'), module.__dict__); return module
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workdir', required=True, type=Path)
    parser.add_argument('--iphone-receipt', required=True, type=Path)
    parser.add_argument('--vision-receipt', type=Path)
    args = parser.parse_args()
    work = args.workdir.resolve(); repo = QA.parents[2]
    if work.is_relative_to(repo.parents[1]): raise RuntimeError('workdir must be outside Folio family')
    work.mkdir(parents=True, exist_ok=False)
    receipts = {'iphone':str(args.iphone_receipt.resolve())}
    if args.vision_receipt: receipts['vision'] = str(args.vision_receipt.resolve())
    (work/'receipts.json').write_text(json.dumps(receipts,indent=2)+'\n')
    resource = load('folio_repo_qa_resource', QA/'resource.py'); resource.ROOT = work
    platforms = ['iphone','ipad'] + (['vision'] if args.vision_receipt else [])
    values = {platform:resource.inputs(platform) for platform in platforms}
    if any(v['source']['file_count'] != 62 or v['source']['sha256'] != '4aa36541a84d29210c411184eaae6a7312bc37d13691be75521f7d9190b3b79d' for v in values.values()):
        raise RuntimeError('this freeze requires actual 62/4aa source; obtain a new reviewed recipe rather than silently rebind')
    (work/'resource-binding.json').write_text(json.dumps({'platforms':values,'scope':'QA-only current ordinary Release source freeze'},ensure_ascii=False,indent=2)+'\n')
    thin = load('folio_repo_qa_thin', QA/'thin.py'); thin.ROOT = work; thin.recipe.ROOT = work
    (work/'thin-binding.json').write_text(json.dumps({'platforms':{p:thin.inputs(p) for p in platforms},'scope':'single ordinary Release Markdown launch/capture only'},ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'status':'prepared-only-no-device', 'workdir':str(work), 'platforms':platforms,
                      'independent_qa_files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(QA.glob('*.py'))},
                      'source':values['iphone']['source']},ensure_ascii=False,indent=2))
if __name__ == '__main__': main()
