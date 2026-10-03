#!/usr/bin/env python3
"""Prepare one GUI slot from genuine ordinary Release receipts; no device APIs/gates."""
import argparse
import json
from pathlib import Path
import sys
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--workdir',required=True,type=Path)
    p.add_argument('--iphone-receipt',required=True,type=Path)
    p.add_argument('--vision-receipt',required=True,type=Path)
    p.add_argument('--prior-owner',action='append',default=[])
    a=p.parse_args()
    sys.path.insert(0,str(HERE));import run
    work=a.workdir.resolve()
    if work.is_relative_to(run.recipe.REPO.parents[1]):raise RuntimeError('workdir must be outside Folio family')
    owners={}
    for value in a.prior_owner:
        platform,path=value.split('=',1)
        if platform not in ('iphone','ipad','vision') or platform in owners:raise RuntimeError('unique explicit platform prior owner required')
        owners[platform]=str(Path(path).resolve())
    work.mkdir(parents=True,exist_ok=False)
    run.guard.atomic_json(work/'receipts.json',{'iphone':str(a.iphone_receipt.resolve()),'vision':str(a.vision_receipt.resolve())})
    run.guard.atomic_json(work/'owned-config.json',{'prior_owners':owners})
    values={p:run.inputs(work,p) for p in ('iphone','ipad','vision')}
    run.guard.atomic_json(work/'gui-binding.json',{'scope':'prepared GUI session only; not actual Files/Scene acceptance','platforms':values})
    (work/'FolioGUIFixture.zip').write_bytes(run.fixtures.archive())
    print(json.dumps({'status':'prepared-only-no-device','workdir':str(work),'binding_sha256':run.recipe.sha(work/'gui-binding.json'),
                      'source':values['iphone']['production']['source'],'scene_manifest':values['ipad']['scene_manifest'],
                      'fixture':run.fixtures.manifest()},ensure_ascii=False,indent=2))
if __name__=='__main__':main()
