#!/usr/bin/env python3
"""Freeze six independent owned launch/Store dry cases using actual ordinary SDK receipts."""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent;QA=HERE.parent
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--workdir',required=True,type=Path)
    p.add_argument('--iphone-receipt',required=True,type=Path);p.add_argument('--vision-receipt',required=True,type=Path)
    p.add_argument('--prior-owner',action='append',default=[],help='platform=/explicit/genuine/owner.json')
    a=p.parse_args();owners={}
    for value in a.prior_owner:
        platform,path=value.split('=',1)
        if platform not in ('iphone','ipad','vision') or platform in owners:raise RuntimeError('unique platform prior-owner required')
        owners[platform]=str(Path(path).resolve())
    subprocess.run([sys.executable,'-B',str(QA/'prepare.py'),'--workdir',str(a.workdir),'--iphone-receipt',str(a.iphone_receipt),'--vision-receipt',str(a.vision_receipt)],check=True,stdout=subprocess.DEVNULL)
    work=a.workdir.resolve();(work/'owned-config.json').write_text(json.dumps({'prior_owners':owners},indent=2)+'\n')
    spec=importlib.util.spec_from_file_location('folio_owned_prepare_run',HERE/'run.py');module=importlib.util.module_from_spec(spec);sys.modules[spec.name]=module
    exec(compile((HERE/'run.py').read_bytes(),str(HERE/'run.py'),'exec'),module.__dict__)
    cases={purpose+'/'+platform:module.inputs(work,platform,purpose) for purpose in ('launch','store') for platform in ('iphone','ipad','vision')}
    (work/'owned-binding.json').write_text(json.dumps({'scope':'six prepared source/ordinary SDK bound owned cases; no actual owner yet','cases':cases},ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'status':'prepared-only-no-device','workdir':str(work),'cases':list(cases),'binding_sha256':module.recipe.sha(work/'owned-binding.json')},ensure_ascii=False,indent=2))
if __name__=='__main__':main()
