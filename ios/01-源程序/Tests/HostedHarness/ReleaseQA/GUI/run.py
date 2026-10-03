#!/usr/bin/env python3
"""Root-CUA GUI slot held by original Session; default dry, ordinary Release reuse."""
import argparse
import contextlib
import datetime
import fcntl
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import stat
import subprocess
import sys
import threading
import time
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent;QA=HERE.parent
sys.path.insert(0,str(QA));sys.path.insert(0,str(QA/'Store'));sys.path.insert(0,str(HERE))
import guard
guard.reject_environment()
import fixtures
# Use the existing resource recipe loader, not Python's builtin resource module.
import importlib.util
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);sys.modules[name]=value
    exec(compile(Path(path).read_bytes(),str(path),'exec'),value.__dict__);return value
recipe=load('folio_gui_original_resource',QA/'resource.py')
devices=load('folio_gui_original_devices',QA/'Store/devices.py')
lane,process=recipe.lane,recipe.original_process
SPAWNING=False;PENDING_INTERRUPT=None

def inputs(work,platform):
    recipe.ROOT=work
    production=recipe.inputs(platform)
    if production['source']!={'sha256':'8309e99023c5314768151efa4498d8f0b249dc35d86d6e303eff794ca71275e0','file_count':62}:
        raise RuntimeError('GUI Scene recipe requires reviewed new62/8309 source; no silent rebind')
    config=json.loads((work/'owned-config.json').read_text());prior=config.get('prior_owners',{}).get(platform)
    info=plistlib.loads((Path(production['app_path'])/'Info.plist').read_bytes())
    if (info.get('UIApplicationSceneManifest') or {}).get('UIApplicationSupportsMultipleScenes') is not True:
        raise RuntimeError('actual ordinary Release Info.plist lacks new multiple-Scene flag; old SDK rejected')
    return {'production':production,'platform':platform,'purpose':'store',
            'request':devices.rule(platform,'store'),'prior_owner':prior,
            'prior_owner_sha256':recipe.sha(prior) if prior else None,
            'gui_files':{p.name:recipe.sha(p) for p in sorted(HERE.glob('*.py'))},
            'store_files':{p.name:recipe.sha(p) for p in sorted((QA/'Store').glob('*.py'))},
            'fixture':fixtures.manifest(),'scene_manifest':info.get('UIApplicationSceneManifest'),
            'file_sharing_enabled':info.get('UIFileSharingEnabled'),'launch_args':['-folio-demo'],
            'gui_policy':'only Root CUA actual UI; no synthesized events, GUI launch, GUI kill, or fabricated permissions'}

@contextlib.contextmanager
def fixture_server():
    payload=fixtures.archive()
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path=='/FolioGUIFixture.zip':
                data=payload;kind='application/zip';self.send_response(200)
                self.send_header('Content-Disposition','attachment; filename="FolioGUIFixture.zip"')
            elif self.path=='/':
                data='<meta charset="utf-8"><h1>Folio 虚构夹具</h1><p><a href="/FolioGUIFixture.zip">下载 FolioGUIFixture.zip</a></p><p>请在 Files 的本机 Downloads 中解压，通过 Folio 系统选择器打开。</p>'.encode();kind='text/html; charset=utf-8';self.send_response(200)
            else:self.send_error(404);return
            self.send_header('Content-Type',kind);self.send_header('Content-Length',str(len(data)))
            self.send_header('Cache-Control','no-store');self.end_headers();self.wfile.write(data)
        def log_message(self,*args):pass
    server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
    thread=threading.Thread(target=server.serve_forever,kwargs={'poll_interval':.1},daemon=True);thread.start()
    try:yield 'http://127.0.0.1:'+str(server.server_port)+'/'
    finally:server.shutdown();server.server_close();thread.join(2)

def json_file(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size>1_000_000:raise RuntimeError('ordinary bounded JSON required: '+str(path))
    return json.loads(path.read_bytes())

def actual_state(session,bundle,before):
    raw=lane.simctl('get_app_container',session.udid,bundle,'data').stdout.strip()
    container=Path(raw).resolve()
    allowed=(Path.home()/'Library/Developer/CoreSimulator/Devices'/session.udid/'data/Containers/Data/Application').resolve()
    if not container.is_relative_to(allowed):raise RuntimeError('actual Folio container outside own device')
    path=container/before['production']['recovery_directory']/'session.json'
    return path,json_file(path)

def checkpoint(session,bundle,before,destination,name):
    if not re.fullmatch(r'[a-zA-Z0-9_-]{1,48}',name):raise RuntimeError('simple checkpoint name required')
    image=destination/('gui-'+name+'.png')
    if image.exists():raise RuntimeError('checkpoint cannot overwrite previous evidence')
    session.shot(image)  # original actual screenshot, not GUI events
    path,state=actual_state(session,bundle,before)
    documents=[]
    for document in state['documents']:
        value={k:document.get(k) for k in ('id','title','path','revision','dirty')}
        value['text_sha256']=hashlib.sha256(document.get('text','').encode()).hexdigest()
        documents.append(value)
    value={'name':name,'udid':session.udid,'frame':str(image),'frame_sha256':recipe.sha(image),
           'actual_app_created_session':str(path),'session_sha256':recipe.sha(path),'activeID':state.get('activeID'),
           'documents':documents,'scope':'actual screenshot and production state readback; manual Root CUA interpretation still required'}
    guard.atomic_json(destination/('checkpoint-'+name+'.json'),value)
    return value

def conflict(session,bundle,before,request,destination):
    # Only explicit Root request for the synthetic Files document, while original Session is held.
    path,state=actual_state(session,bundle,before)
    docs=[d for d in state['documents'] if d.get('id')==request.get('document_id')]
    if len(docs)!=1 or not docs[0].get('text','').startswith(fixtures.TITLE):raise RuntimeError('only selected fictional document may conflict')
    source=Path(docs[0]['path'])
    root=(Path.home()/'Library/Developer/CoreSimulator/Devices'/session.udid/'data').resolve()
    resolved=source.resolve()
    if source.name!='folio-gui.md' or not resolved.is_relative_to(root/'Containers') or source.is_symlink():raise RuntimeError('synthetic source is not within own Simulator containers')
    # FD relative walk rejects user/provider symlinks below the verified actual device root.
    fd=os.open(root,os.O_RDONLY|os.O_DIRECTORY)
    try:
        for part in resolved.relative_to(root).parts[:-1]:
            nextfd=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=fd);os.close(fd);fd=nextfd
        leaf=os.open(resolved.name,os.O_RDWR|os.O_NOFOLLOW,dir_fd=fd)
        try:
            metadata=os.fstat(leaf)
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_size>100_000:raise RuntimeError('bounded ordinary fixture required')
            prior=os.read(leaf,100_001)
            if hashlib.sha256(prior).hexdigest()!=request.get('expected_sha256'):raise RuntimeError('explicit current fixture SHA differs; no write')
            if not prior.decode('utf-8-sig').startswith(fixtures.TITLE):raise RuntimeError('source is not the fictional fixture')
            external=b'\xef\xbb\xbf'+fixtures.EXTERNAL_TEXT.encode()
            os.lseek(leaf,0,0);os.write(leaf,external);os.ftruncate(leaf,len(external));os.fsync(leaf)
        finally:os.close(leaf)
    finally:os.close(fd)
    result={'action':'explicit-root-synthetic-external-conflict','path':str(resolved),
            'before_sha256':hashlib.sha256(prior).hexdigest(),'after_sha256':hashlib.sha256(external).hexdigest(),
            'scope':'own fictional file only; production permission metadata never written'}
    guard.atomic_json(destination/'external-conflict.json',result);return result

def worker(work,platform,destination,before,attempt):
    controller=int(os.environ['FOLIO_RESOURCE_OBSERVER_OWNER_PID'])
    if controller!=os.getppid() or lane.pid_started(controller)!=os.environ['FOLIO_RESOURCE_OBSERVER_OWNER_STARTED']:raise RuntimeError('worker parent identity mismatch')
    if not destination.resolve().is_relative_to((work/'gui-runs').resolve()):raise RuntimeError('destination outside own work')
    recipe.ATTEMPT=attempt
    owner=devices.register(recipe,platform,'store',destination,before['prior_owner'])
    info=lane.bundle_info(Path(before['production']['app_path']))
    with recipe.observation_context(platform,destination,before['production']) as (journal,observations):
        journal.selected(owner['actual_device'])
        with lane.Session(platform,owner['actual_device']['udid'],label='Folio Root CUA GUI '+platform,lock_wait=0,load_wait=0) as session:
            session.install(Path(before['production']['app_path']));baseline,stable=session.baseline()
            session.launch(info['bundle_id'],['-folio-demo'],'auto',60,baseline,info['executable'])
            attempt.require('Root GUI waiting phase')
            with fixture_server() as url:
                ready={'phase':'ready-for-root-cua','udid':session.udid,'worker_pid':os.getpid(),'worker_started':lane.pid_started(os.getpid()),
                       'controller_pid':controller,'controller_started':os.environ['FOLIO_RESOURCE_OBSERVER_OWNER_STARTED'],
                       'destination':str(destination),'fixture_url':url,'fixture':fixtures.manifest(),
                       'root_done':str(destination/'Root.done'),'root_request':str(destination/'Root.request.json'),
                       'budget_started_monotonic':attempt.started,'budget_seconds':attempt.seconds,
                       'scene_manifest':before['scene_manifest'],'scene_scope':'blocked missing actual Release SceneManifest' if not before['scene_manifest'] else 'manual real OS Scene still pending',
                       'launch':observations[0],'gui':'Root may now open exact owned Simulator via CUA; runner sends no input events'}
                guard.atomic_json(destination/'ready.json',ready)
                seen=set()
                while True:
                    attempt.require('next GUI control observation')
                    done=destination/'Root.done'
                    if done.exists():
                        value=json_file(done)
                        if value.get('ready_sha256')!=recipe.sha(destination/'ready.json') or value.get('root_cua_only') is not True:raise RuntimeError('Root.done must bind actual ready and real CUA scope')
                        guard.atomic_json(destination/'root-gui-observation.json',value);break
                    request=destination/'Root.request.json'
                    if request.exists():
                        digest=recipe.sha(request)
                        if digest not in seen:
                            value=json_file(request)
                            if value.get('ready_sha256')!=recipe.sha(destination/'ready.json'):raise RuntimeError('Root request not bound to this actual GUI session')
                            attempt.require('explicit Root '+str(value.get('action')))
                            if value.get('action')=='checkpoint':result=checkpoint(session,info['bundle_id'],before,destination,value['name'])
                            elif value.get('action')=='external-conflict':result=conflict(session,info['bundle_id'],before,value,destination)
                            else:raise RuntimeError('unsupported Root action; no UI automation available')
                            guard.atomic_json(destination/'request-result.json',{'request_sha256':digest,'result':result});seen.add(digest)
                    time.sleep(.2)
            session.terminate(info['bundle_id'])
    return 0

def main():
    global SPAWNING,PENDING_INTERRUPT
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--workdir',required=True,type=Path)
    p.add_argument('--platform',required=True,choices=['iphone','ipad','vision']);p.add_argument('--slot-seconds',type=int,default=600)
    p.add_argument('--execute',action='store_true');p.add_argument('--worker',type=Path,help=argparse.SUPPRESS)
    a=p.parse_args();attempt=recipe.attempt_budget.Attempt(a.slot_seconds,worker=bool(a.worker));recipe.ATTEMPT=attempt
    work=a.workdir.resolve();before=inputs(work,a.platform)
    if before!=json_file(work/'gui-binding.json')['platforms'][a.platform]:raise RuntimeError('source/ordinary SDK/QA/owner binding changed')
    if a.worker:return worker(work,a.platform,a.worker,before,attempt)
    if not a.execute:
        print(json.dumps({'status':'dry-only-no-device','inputs':before,'scope':'future ordinary Release Root-CUA Files GUI session; no current GUI/Files/Scene/resource PASS',
                          'entry':'original global NB + directory/load0 + actual creation/prior-owner + journal before boot; same Session held until bound Root.done, <=600 incl cleanup',
                          'fixture_route':'Root CUA Safari -> localhost synthetic ZIP -> actual Files Downloads -> unzip -> production file/folder pickers',
                          'scene_blocker':not bool(before['scene_manifest']),'execute_requires':'NEW explicit Root sole native GUI grant'},ensure_ascii=False,indent=2));return 0
    destination=work/'gui-runs'/(datetime.datetime.now().astimezone().strftime('%Y%m%d-%H%M%S')+'-'+a.platform+'-'+str(os.getpid()))
    destination.mkdir(parents=True,exist_ok=False);log=destination/'operation.log'
    print(json.dumps({'run_directory':str(destination),'ready_path':str(destination/'ready.json')},ensure_ascii=False),flush=True)
    child=None;identity='';observed={};held=False;errors=[]
    controller={'pid':os.getpid(),'pid_started':lane.pid_started(os.getpid())}
    record={'status':'not-completed','before':before,'started_at':datetime.datetime.now().astimezone().isoformat()}
    lock=(recipe.sop.STATE_DIR/'lock').open('a')
    try:
        attempt.require('Chapter NB admission');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);held=True
        with log.open('w') as output:
            PENDING_INTERRUPT=None;SPAWNING=True
            try:
                child=subprocess.Popen([recipe.PYTHON,str(Path(__file__).resolve()),'--workdir',str(work),'--platform',a.platform,'--slot-seconds',str(a.slot_seconds),'--worker',str(destination)],
                    stdout=output,stderr=subprocess.STDOUT,start_new_session=True,
                    env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1','FOLIO_RESOURCE_OBSERVER_OWNER_PID':str(controller['pid']),
                         'FOLIO_RESOURCE_OBSERVER_OWNER_STARTED':controller['pid_started'],**attempt.environment()})
                identity=lane.pid_started(child.pid);observed[child.pid]=identity
            finally:SPAWNING=False
            if PENDING_INTERRUPT is not None:
                signum,PENDING_INTERRUPT=PENDING_INTERRUPT,None;raise InterruptedError('signal during child registration '+str(signum))
            while child.poll() is None:
                for pid in process.group_members(child.pid):observed.setdefault(pid,lane.pid_started(pid))
                if attempt.expired():record['budget_crossed_during_existing_child']=True
                time.sleep(.25)
        record['exit_code']=child.returncode
        if child.returncode:raise RuntimeError('single GUI worker failed '+str(child.returncode)+'; no retry')
        record['root_observation']=json_file(destination/'root-gui-observation.json')
        record['root_observation_sha256']=recipe.sha(destination/'root-gui-observation.json');record['status']='candidate-completed'
    except BaseException as error:errors.append(type(error).__name__+': '+str(error))
    finally:
        with guard.cleanup_signals_blocked():
            try:
                record['cleanup']=devices.cleanup_owned(recipe,a.platform,'store',child,identity,observed,destination,controller,before['production']) if held else {'clear':True,'errors':[],'device':'file NB busy; no worker started'}
                record['cleanup']['chapter_global_held_during_observation']=held
                guard.atomic_json(destination/'cleanup.json',record['cleanup']);record['cleanup_sha256']=recipe.sha(destination/'cleanup.json')
                if not record['cleanup']['clear']:errors.append('own terminal cleanup incomplete: '+json.dumps(record['cleanup']['errors']))
            except BaseException as error:errors.append('own cleanup '+type(error).__name__+': '+str(error))
            finally:lock.close()
        try:record['after']=inputs(work,a.platform);record['input_stable']=record['after']==before
        except BaseException as error:errors.append('final inputs '+str(error))
        if not record.get('input_stable'):errors.append('input changed')
        record.update(errors=errors,process_group=observed,log=str(log),log_sha256=recipe.sha(log) if log.exists() else None,
                      finished_at=datetime.datetime.now().astimezone().isoformat(),scope='completed GUI holding session only; Root manual evidence decides individual Files outcomes; Scene/perf/Store not inferred')
        attempt.finalize(record,errors,'candidate-completed','completed-gui-session-awaiting-root-scope-review')
        guard.atomic_json(destination/'result.json',record);print(json.dumps(record,ensure_ascii=False,indent=2))
    return 0 if record['status'].startswith('completed-') else 1

def interrupted(signum,frame):
    global PENDING_INTERRUPT
    if SPAWNING:PENDING_INTERRUPT=signum;return
    raise InterruptedError('signal '+str(signum))
if __name__=='__main__':
    signal.signal(signal.SIGTERM,interrupted);signal.signal(signal.SIGINT,interrupted);sys.exit(main())
