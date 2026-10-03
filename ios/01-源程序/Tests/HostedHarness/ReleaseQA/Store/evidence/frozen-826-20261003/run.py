#!/usr/bin/env python3
"""Folio one granted launch or Store image, genuine owned-device creation; default dry."""
import argparse
import datetime
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
QA = HERE.parent
sys.path.insert(0,str(QA)); sys.path.insert(0,str(HERE))
import guard
guard.reject_environment()
import devices
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    value=importlib.util.module_from_spec(spec);sys.modules[name]=value
    exec(compile(path.read_bytes(),str(path),'exec'),value.__dict__);return value
recipe=load('folio_owned_store_resource',QA/'resource.py')
lane,process=recipe.lane,recipe.original_process
SHOTS=Path('/Users/tianli/Dev/tools/dev/lib/tools/macapp/ios/store_shots.py')
SHOTS_SHA='419173c33d066193190aa1b2738e26a5298373271bdcb6251d258f1c994b9c73'
SPAWNING=False;PENDING_INTERRUPT=None

def inputs(work,platform,purpose):
    recipe.ROOT=work
    if recipe.sha(SHOTS)!=SHOTS_SHA:raise RuntimeError('canonical Store dimensions ABI changed')
    config=json.loads((work/'owned-config.json').read_text())
    prior=config.get('prior_owners',{}).get(platform)
    return {'production':recipe.inputs(platform),'wrapper_sha256':recipe.sha(__file__),
            'store_qa_files':{p.name:recipe.sha(p) for p in sorted(HERE.glob('*.py'))},
            'platform':platform,'purpose':purpose,'request':devices.rule(platform,purpose),
            'prior_owner':prior,'prior_owner_sha256':recipe.sha(prior) if prior else None,
            'dimension_abi':{'path':str(SHOTS),'sha256':SHOTS_SHA},'launch_args':['-folio-demo']}

def worker(work,platform,purpose,destination,before,attempt):
    controller=int(os.environ.get('FOLIO_RESOURCE_OBSERVER_OWNER_PID','0'))
    if controller!=os.getppid() or lane.pid_started(controller)!=os.environ.get('FOLIO_RESOURCE_OBSERVER_OWNER_STARTED'):
        raise RuntimeError('worker parent PID/start mismatch')
    if not destination.resolve().is_relative_to((work/'owned-runs').resolve()):raise RuntimeError('artifact path outside own workdir')
    recipe.ATTEMPT=attempt
    owner=devices.register(recipe,platform,purpose,destination,before['prior_owner'])
    info=lane.bundle_info(Path(before['production']['app_path']))
    shots=load('folio_owned_store_dimensions',SHOTS)
    with recipe.observation_context(platform,destination,before['production']) as (journal,observations):
        journal.selected(owner['actual_device'])
        with lane.Session(platform,owner['actual_device']['udid'],label='Folio owned '+purpose+' '+platform,lock_wait=0,load_wait=0) as session:
            installed=session.install(Path(before['production']['app_path']))
            baseline,stable=session.baseline()
            returned=session.launch(info['bundle_id'],['-folio-demo'],'auto',60,baseline,info['executable'])
            if len(observations)!=1:raise RuntimeError('single actual Markdown observation required')
            frame=Path(observations[0]['frame']);dimensions=shots.png_size(frame)
            problems=shots.validate(platform,[frame])
            capture={'purpose':purpose,'platform':platform,'owner':str(destination/'owner.json'),'owner_sha256':recipe.sha(destination/'owner.json'),
                     'install_seconds':installed,'baseline_stable':stable,'launch':observations[0],
                     'dimensions':dimensions,'display_type':shots.display_type(platform,dimensions),
                     'store_validation_errors':problems,'store_dimension_abi_sha256':SHOTS_SHA,
                     'scope':'one ordinary Release synthetic production-demo Markdown first screen, original returned PNG; no scaling/UI events/Files/WC/resource/upload claim'}
            guard.atomic_json(destination/'capture.json',capture)
            session.terminate(info['bundle_id'])
        if purpose=='store' and problems:raise RuntimeError('actual Store image rejected: '+'; '.join(problems))
    return 0

def main():
    global SPAWNING,PENDING_INTERRUPT
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workdir',required=True,type=Path)
    parser.add_argument('--platform',required=True,choices=['iphone','ipad','vision'])
    parser.add_argument('--purpose',choices=['launch','store'],default='store')
    parser.add_argument('--slot-seconds',type=int,default=600)
    parser.add_argument('--execute',action='store_true');parser.add_argument('--worker',type=Path,help=argparse.SUPPRESS)
    args=parser.parse_args();attempt=recipe.attempt_budget.Attempt(args.slot_seconds,worker=bool(args.worker))
    recipe.ATTEMPT=attempt;work=args.workdir.resolve()
    if work.is_relative_to(recipe.REPO.parents[1]):raise RuntimeError('workdir must be outside Folio family')
    before=inputs(work,args.platform,args.purpose)
    expected=json.loads((work/'owned-binding.json').read_text())['cases'][args.purpose+'/'+args.platform]
    if before!=expected:raise RuntimeError('owned QA/source/ordinary SDK/owner receipt binding changed')
    if args.worker:return worker(work,args.platform,args.purpose,args.worker,before,attempt)
    if not args.execute:
        print(json.dumps({'status':'dry-only-no-device','inputs':before,'actual_udid':None if args.purpose=='store' or args.platform!='iphone' else devices.PHONE,
                          'owner_pending':True,'creation':'original directory+load wait0 under Chapter file NB; actual before inventory, original ensure created:true, actual identity/Shutdown readback, owner receipt',
                          'attempt':'one platform only, 0..600 total budget including cleanup/final inputs; in-flight natural boundary, no next after deadline',
                          'execute_requires':'NEW explicit Root sole native grant; no default device, resize, UI events, build or automatic retry',
                          'scope':'launch single Markdown frame; Store additionally requires canonical actual size/alpha; no complete Store/upload/Files/OS Scene/WK resources pass'},ensure_ascii=False,indent=2));return 0
    if process.gui_processes():raise RuntimeError('Simulator/AppSimulator GUI present')
    destination=work/'owned-runs'/(datetime.datetime.now().astimezone().strftime('%Y%m%d-%H%M%S')+'-'+args.purpose+'-'+args.platform+'-'+str(os.getpid()))
    destination.mkdir(parents=True,exist_ok=False);log=destination/'operation.log'
    child=None;identity='';observed={};held=False;errors=[]
    controller={'pid':os.getpid(),'pid_started':lane.pid_started(os.getpid())}
    record={'status':'not-passed','before':before,'started_at':datetime.datetime.now().astimezone().isoformat()}
    global_lock=(recipe.sop.STATE_DIR/'lock').open('a')
    try:
        attempt.require('Chapter NB admission');fcntl.flock(global_lock,fcntl.LOCK_EX|fcntl.LOCK_NB);held=True
        with log.open('w') as output:
            PENDING_INTERRUPT=None;SPAWNING=True
            try:
                child=subprocess.Popen([recipe.PYTHON,str(Path(__file__).resolve()),'--workdir',str(work),'--platform',args.platform,'--purpose',args.purpose,'--slot-seconds',str(args.slot_seconds),'--worker',str(destination)],
                    stdout=output,stderr=subprocess.STDOUT,start_new_session=True,
                    env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1','FOLIO_RESOURCE_OBSERVER_OWNER_PID':str(controller['pid']),
                         'FOLIO_RESOURCE_OBSERVER_OWNER_STARTED':controller['pid_started'],**attempt.environment()})
                identity=lane.pid_started(child.pid);observed[child.pid]=identity
            finally:SPAWNING=False
            if PENDING_INTERRUPT is not None:
                signum,PENDING_INTERRUPT=PENDING_INTERRUPT,None
                raise InterruptedError('signal during child registration '+str(signum))
            while child.poll() is None:
                for pid in process.group_members(child.pid):observed.setdefault(pid,lane.pid_started(pid))
                if process.gui_processes():raise RuntimeError('Simulator/AppSimulator GUI appeared')
                if attempt.expired():record['budget_crossed_during_existing_child']=True
                time.sleep(.25)
        record['exit_code']=child.returncode
        if process.gui_processes():raise RuntimeError('Simulator/AppSimulator GUI appeared at natural child boundary')
        if child.returncode:raise RuntimeError('single operation failed '+str(child.returncode)+'; no retry')
        record['capture']=json.loads((destination/'capture.json').read_text())
        record['capture_sha256']=recipe.sha(destination/'capture.json')
        record['status']='candidate'
    except BaseException as error:errors.append(type(error).__name__+': '+str(error))
    finally:
        with guard.cleanup_signals_blocked():
            try:
                if held:
                    record['cleanup']=devices.cleanup_owned(recipe,args.platform,args.purpose,child,identity,observed,destination,controller,before['production'])
                else:record['cleanup']={'clear':True,'errors':[],'device':'file NB busy, worker never started'}
                record['cleanup']['chapter_global_held_during_observation']=held
                guard.atomic_json(destination/'cleanup.json',record['cleanup']);record['cleanup_sha256']=recipe.sha(destination/'cleanup.json')
                if not record['cleanup']['clear']:errors.append('own terminal cleanup incomplete: '+json.dumps(record['cleanup']['errors']))
            except BaseException as error:errors.append('own cleanup '+type(error).__name__+': '+str(error))
            finally:global_lock.close()
        try:record['after']=inputs(work,args.platform,args.purpose);record['input_stable']=record['after']==before
        except BaseException as error:errors.append('final inputs '+str(error))
        if not record.get('input_stable'):errors.append('inputs changed')
        record.update(errors=errors,process_group=observed,log=str(log),log_sha256=recipe.sha(log) if log.exists() else None,
                      finished_at=datetime.datetime.now().astimezone().isoformat())
        attempt.finalize(record,errors,'candidate','passed-'+args.purpose+'-single-release-markdown-image-scope-only')
        guard.atomic_json(destination/'result.json',record);print(json.dumps(record,ensure_ascii=False,indent=2))
    return 0 if record['status'].startswith('passed-') else 1

def interrupted(signum,frame):
    global PENDING_INTERRUPT
    if SPAWNING:PENDING_INTERRUPT=signum;return
    raise InterruptedError('signal '+str(signum))
if __name__=='__main__':
    signal.signal(signal.SIGTERM,interrupted);signal.signal(signal.SIGINT,interrupted);sys.exit(main())
