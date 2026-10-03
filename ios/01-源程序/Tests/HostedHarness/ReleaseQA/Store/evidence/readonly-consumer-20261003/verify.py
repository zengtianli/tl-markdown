#!/usr/bin/env python3
"""Read-only validation of one existing Folio Store result; no device/API/lock calls."""
import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import sys

sys.dont_write_bytecode=True
STORE=Path('/Users/tianli/Apps/folio/ios/01-源程序/Tests/HostedHarness/ReleaseQA/Store')
RULES={
 'iphone':('Folio Store iPhone 20261003','iPhone-17-Pro-Max','com.apple.CoreSimulator.SimRuntime.iOS-27-0'),
 'ipad':('Folio Resource iPad 20261003','iPad-Pro-13-inch-M5-12GB','com.apple.CoreSimulator.SimRuntime.iOS-27-0'),
 'vision':('Folio Resource Vision 20261003','Apple-Vision-Pro-4K','com.apple.CoreSimulator.SimRuntime.xrOS-27-0')}
SOURCE='4aa36541a84d29210c411184eaae6a7312bc37d13691be75521f7d9190b3b79d'
SHOTS=Path('/Users/tianli/Dev/tools/dev/lib/tools/macapp/ios/store_shots.py')
SHOTS_SHA='419173c33d066193190aa1b2738e26a5298373271bdcb6251d258f1c994b9c73'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()

def require(condition,message):
 if not condition:raise ValueError(message)

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--result',required=True,type=Path)
 p.add_argument('--expect-platform',required=True,choices=RULES)
 a=p.parse_args();path=a.result.resolve();root=path.parent
 tracked={path:sha(path)};r=json.loads(path.read_text())
 require(r.get('status')=='passed-store-single-release-markdown-image-scope-only','not an actual passed single Store result; launch/phone/preparation cannot substitute')
 before=r['before'];production=before['production'];platform=a.expect_platform
 require(before.get('purpose')=='store' and before.get('platform')==platform,'purpose/platform mismatch')
 require(r.get('input_stable') is True and r.get('after')==before and r.get('exit_code')==0 and not r.get('errors'),'failed/unstable actual input or process result')
 budget=r['total_budget'];elapsed=float(budget['elapsed_seconds']);limit=float(budget['seconds'])
 require(math.isfinite(elapsed) and math.isfinite(limit) and 0<=elapsed<limit<=600 and budget.get('over_budget') is False,'total budget missing or exceeded')
 require(production['source']=={'sha256':SOURCE,'file_count':62} and production['ordinary_release'] is True and production['launch_args']==['-folio-demo'],'wrong source or ordinary production scene')
 for base,files in ((STORE,before['store_qa_files']),(STORE.parent,production['qa_files'])):
  for name,h in files.items():
   f=base/name;require(sha(f)==h,'current independent QA bytes changed: '+name);tracked[f]=h
 require(len(before['store_qa_files'])==4 and len(production['qa_files'])==6,'independent QA input count differs')
 for name,h in production['tools'].items():
  f=Path(name);require(sha(f)==h,'canonical pinned ABI changed');tracked[f]=h
 receipt=Path(production['receipt']);require(sha(receipt)==production['receipt_sha256'],'ordinary SDK receipt changed');tracked[receipt]=sha(receipt)
 sdk=json.loads(receipt.read_text())
 require(sdk.get('ok') is True and sdk.get('configuration')=='Release' and sdk.get('compilation_conditions')==[] and sdk.get('source_layout',{}).get('input_sha256')==SOURCE,'ordinary Release SDK conditions/source differ')
 require(sdk['sdk']==production['sdk'] and sdk['executable_sha256']==production['executable_sha256'],'SDK/executable binding differs')
 app=Path(production['app_path'])
 for name,h in production['app_files'].items():
  f=app/name;require(f.is_file() and not f.is_symlink() and sha(f)==h,'compiled app input changed: '+name);tracked[f]=h
 for name,key in (('capture.json','capture'),('cleanup.json','cleanup')):
  f=root/name;require(sha(f)==r[key+'_sha256'],'original '+name+' changed');tracked[f]=sha(f)
  require(json.loads(f.read_text())==r[key],'embedded '+key+' differs from original')
 capture=r['capture'];cleanup=r['cleanup'];owner_path=root/'owner.json'
 require(sha(owner_path)==capture['owner_sha256'],'actual owner receipt changed');tracked[owner_path]=sha(owner_path)
 owner=json.loads(owner_path.read_text());actual=owner['actual_device']
 require(owner.get('family')=='folio' and owner.get('platform')==platform and owner.get('purpose')=='store' and owner.get('source')==production,'actual owner/source/purpose differs')
 require(tuple(actual.get(k) for k in ('name','device_type','runtime'))==RULES[platform] and actual.get('available') is True and actual.get('udid'),'dedicated actual identity differs')
 origin=owner.get('original_creation') or owner
 require(origin.get('creation_before_absent') is True and origin.get('ensure_return',{}).get('created') is True and origin['ensure_return']['udid']==actual['udid'] and origin['actual_device']['udid']==actual['udid'] and origin['creation_gate']['before_name_matches']==[],'missing genuine original before-absent creation')
 admission_path=root/'admission.json';tracked[admission_path]=sha(admission_path);admission=json.loads(admission_path.read_text())
 require(admission.get('phase')=='boot-admitted' and admission.get('controller')==owner['controller'] and admission.get('worker')==owner['worker'] and admission.get('destination')==str(root) and admission.get('platform')==platform,'actual boot journal identity differs')
 identity={k:actual[k] for k in ('udid','name','device_type','runtime','available')}
 require(admission.get('device')==identity,'actual selected journal identity differs')
 require(cleanup.get('clear') is True and not cleanup.get('errors') and cleanup.get('chapter_global_held_during_observation') is True,'actual own cleanup is incomplete')
 require(cleanup['worker']['pid']==owner['worker']['pid'] and cleanup['worker']['pid_started']==owner['worker']['pid_started'] and cleanup['worker']['remaining_group']=={},'actual own child/group differs or remains')
 final=cleanup['device_after_cleanup'];require(final.get('state')=='Shutdown' and all(final.get(k)==v for k,v in identity.items()),'actual recorded terminal identity/Shutdown differs')
 require(cleanup.get('directory_lock_final')=='absent' and cleanup.get('original_session_work_final',{}).get('exists') is False,'actual original own gate/workspace tail remains')
 require(not cleanup.get('remainsOwnGate') and not cleanup.get('creation_release_tail_sha256') and not (root/'creation-release-tail.json').exists(),'failed own gate tail cannot pass')
 launch=capture['launch'];event=launch['actual_ready']['event']
 require(launch['actual_args']==['-folio-demo'] and launch['ready_signal']=='os_log' and event['eventMessage']=='lane-ready markdown' and event['processID']==launch['pid'],'actual production Markdown ready missing')
 verdict=launch['verdict'];require(verdict.get('non_blank') is True and verdict.get('stable') is True and verdict.get('changed_from_baseline') is not False,'original frame is not ready/nonblank/stable')
 image=root/'launch-0.png';require(sha(image)==launch['frame_sha256'],'original PNG changed');tracked[image]=sha(image)
 require(capture.get('store_validation_errors')==[] and capture.get('purpose')=='store' and capture.get('platform')==platform,'actual Store validation failed')
 require(sha(SHOTS)==SHOTS_SHA,'canonical Store validator ABI changed');tracked[SHOTS]=SHOTS_SHA
 spec=importlib.util.spec_from_file_location('folio_readonly_store_shots',SHOTS);shots=importlib.util.module_from_spec(spec);spec.loader.exec_module(shots)
 require(list(shots.png_size(image))==capture['dimensions'] and not shots.validate(platform,[image]),'original unscaled image fails canonical size/alpha')
 log=Path(r['log']);require(log.resolve()==(root/'operation.log').resolve() and sha(log)==r['log_sha256'],'original operation log changed');tracked[log]=sha(log)
 require(all(sha(f)==h for f,h in tracked.items()),'read-only validation inputs changed during check')
 print(json.dumps({'status':'verified-existing-single-store-image-scope-only','platform':platform,'result_sha256':tracked[path],'original_png_sha256':tracked[image],'actual_device':actual,'dimensions':capture['dimensions'],'recorded_terminal':'source-bound original final guard Shutdown/group-empty/own-gate-cleared; no fresh device query','scope':'one unscaled ordinary Release production-demo image, not complete Store set/Files/OS Scene/median/resources/upload','verifier_sha256':sha(__file__)},ensure_ascii=False,indent=2))

if __name__=='__main__':
 try:main()
 except Exception as error:
  print(json.dumps({'status':'not-verified','error':type(error).__name__+': '+str(error)},ensure_ascii=False),file=sys.stderr);sys.exit(1)
