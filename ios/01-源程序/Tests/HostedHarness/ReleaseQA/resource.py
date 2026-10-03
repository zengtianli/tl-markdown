#!/usr/bin/env python3
"""Folio normal Release, production -folio-demo, canonical final ABI; default dry."""
import argparse,ast,contextlib,datetime,fcntl,hashlib,importlib.util,json,os,re,shutil,signal,subprocess,sys,time
from pathlib import Path
sys.dont_write_bytecode=True
QA_DIR=Path(__file__).resolve().parent
ROOT=QA_DIR
ATTEMPT=None
sys.path.insert(0,str(ROOT))
import guard
import budget as attempt_budget
guard.reject_environment()  # sim_lane captures LOCK_DIR during import, so reject first
REPO=QA_DIR.parents[2]
PYTHON='/Users/tianli/Dev/.venv/bin/python'
PINS={
 '/Users/tianli/Apps/.claude/skills/app-lightweight/scripts/measure.py':'9b4f3cb22190a295fade42759bdb19f27da7c5dbd13449e78cb14743472ed94c',
 '/Users/tianli/Apps/.claude/skills/app-lightweight/scripts/platform_measure.py':'09a2cc684be508ceb576a0da6957871aacc18fdaa25402720033277dd92057b6',
 '/Users/tianli/Dev/tools/dev/lib/tools/macapp/ios/sim_lane.py':'ba7cbd20ded10311bdc948675314205e5be797537da2eb9ae33ac2844e1d3d34',
 '/Users/tianli/Apps/chapter/engine/app_sop.py':'c82518099ac3206e9b9b66c74c54824c6c05a7390ee515b694446ed2f82b2c89',
 str(REPO/'Tests/HostedHarness/run.py'):'6f1af3fa63fd4c224e0a027da30cc7ba4fb4e4f6ad46e6394759d41d767135d8'}
LANE=Path(list(PINS)[2]);MEASURE=Path(list(PINS)[1])
PHONE='12B97992-764F-4AAE-9C54-C41E5BEADA0B'
NAMES={'ipad':'Folio Resource iPad 20261003','vision':'Folio Resource Vision 20261003'}
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
SPAWNING=False;PENDING_INTERRUPT=None

def module(name,path):
 spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);sys.modules[name]=value
 raw=Path(path).read_bytes();exec(compile(raw,str(path),'exec'),value.__dict__);return value

sys.path.insert(0,str(LANE.parent));sys.path.insert(0,'/Users/tianli/Apps/chapter/engine')
lane=module('sim_lane',LANE)
guard.check_lane(lane)
import app_sop as sop
original_process=module('folio_original_process_helpers',Path(list(PINS)[4]))

def receipt(platform):
 sdk='iphone' if platform=='ipad' else platform
 return Path(json.loads((ROOT/'receipts.json').read_text())[sdk])

def inputs(platform):
 for path,expected in PINS.items():
  if sha(path)!=expected:raise RuntimeError('final ABI changed: '+path)
 app=sop.load_apps('folio')[0];current=sop.lane_inputs(app,platform)
 built=lane.reuse_build(receipt(platform),'folio',REPO,platform,'FolioMobile','Release',False)
 if built['compilation_conditions'] or built['configuration']!='Release':raise RuntimeError('ordinary Release required')
 path=Path(built['app_path']);demo=path/'demo.md'
 if any(path.glob('PlugIns/*.xctest')):raise RuntimeError('hosted package rejected')
 cfg=(app['sop']['platforms'])[platform]
 if cfg.get('launch_args')!=['-folio-demo']:raise RuntimeError('exact production demo argument changed')
 files={str(p.relative_to(path)):sha(p) for p in sorted(path.rglob('*')) if p.is_file() and not p.is_symlink()}
 return {'tools':PINS,'wrapper_sha256':sha(__file__),'guard_sha256':sha(QA_DIR/'guard.py'),'qa_files':{p.name:sha(p) for p in sorted(QA_DIR.glob('*.py'))},'platform':platform,'source':{'sha256':current['input_sha256'],'file_count':current['file_count']},'monitor_code':sop.monitor_inputs(app,{})['bindings']['code'],'receipt':str(receipt(platform)),'receipt_sha256':sha(receipt(platform)),'sdk':built['sdk'],'executable_sha256':built['executable_sha256'],'app_path':str(path),'app_files':files,'demo_sha256':sha(demo),'demo_matches_frozen_input':sha(demo)==current['files']['ios/01-源程序/Fixtures/demo.md'],'launch_args':['-folio-demo'],'recovery_directory':'Library/Application Support/FolioMobile-Demo','ready_scene':'markdown','ordinary_release':True}

def canonical_args(platform):
 path=receipt(platform)
 args=['--app','folio','--repo',str(REPO),'--platform',platform,'--reuse-size-build',str(path),'--reuse-runtime-build',str(path),'--runs','5','--warmup-settle','45','--settle','45','--idle-seconds','60','--with-helpers','--lock-wait','0','--load-wait','0']
 args+=['--udid',PHONE] if platform=='iphone' else ['--name',NAMES[platform]]
 if platform in ('iphone','ipad'):args+=['--orientation','portrait' if platform=='iphone' else 'landscape']
 if platform=='iphone':args+=['--sync-ios']
 return args

@contextlib.contextmanager
def observation_context(platform,destination,before):
 """Observe original returns only. No new ready wait, timer, launch or metric code."""
 observations=[];events=[]
 expected_text=(Path(before['app_path'])/'demo.md').read_text()
 journal=guard.AdmissionJournal(lane,platform,destination)
 OriginalReady=lane.ReadyStream;OriginalSession=lane.Session;original_boot=lane.boot
 class ObservedReady(OriginalReady):
  def _wait(self,predicate,timeout):
   line=super()._wait(predicate,timeout)
   if line and line.startswith('{'):
    try:
     event=json.loads(line)
     if 'lane-ready' in event.get('eventMessage',''):events.append({'raw':line,'event':event})
    except ValueError:pass
   return line
 class ObservedSession(OriginalSession):
  def __enter__(self):
   if ATTEMPT:ATTEMPT.require('Session admission')
   journal.session=self
   return super().__enter__()
  def install(self,*args,**kwargs):
   if ATTEMPT:ATTEMPT.require('install')
   return super().install(*args,**kwargs)
  def baseline(self,*args,**kwargs):
   if ATTEMPT:ATTEMPT.require('baseline')
   return super().baseline(*args,**kwargs)
  def launch(self,*args,**kwargs):
   if ATTEMPT:ATTEMPT.require('launch')
   index=len(observations);event_at=len(events)
   returned=super().launch(*args,**kwargs)
   argument_list=args[1] if len(args)>1 else kwargs['args']
   if argument_list.count('-folio-demo')!=1:raise RuntimeError('actual launch did not use exact production demo flag')
   if returned.get('errors') or returned.get('ready_signal')!='os_log' or not returned.get('frame'):raise RuntimeError('original launch lacks actual clean frame/log readiness')
   actual_events=events[event_at:]
   if len(actual_events)!=1 or not re.search(r'\blane-ready\s+markdown(?:\s|$)',actual_events[0]['event'].get('eventMessage','')):raise RuntimeError('original ready event not markdown; welcome cannot pass Editor resources')
   image=destination/('launch-'+str(index)+'.png');shutil.copyfile(returned['frame'].path,image)
   if not lane.frame_ready(returned['verdict']):raise RuntimeError('original frame verdict not stable/nonblank')
   container=Path(lane.simctl('get_app_container',self.udid,args[0],'data').stdout.strip()).resolve()
   allowed=(Path.home()/'Library/Developer/CoreSimulator/Devices'/self.udid/'data/Containers/Data/Application').resolve()
   if not container.is_relative_to(allowed):raise RuntimeError('actual App container outside owned device')
   state=container/'Library/Application Support/FolioMobile-Demo';session=state/'session.json'
   data=json.loads(session.read_text());documents=data['documents']
   if len(documents)!=1 or data.get('activeID')!=documents[0]['id'] or documents[0].get('path') is not None or documents[0].get('diskData') is not None or documents[0]['text']!=expected_text:raise RuntimeError('App did not persist the actual isolated unnamed production demo draft')
   if (state/'bookmarks.json').exists() or (state/'asset-folders.json').exists():raise RuntimeError('unexpected permission metadata; no fabricated Files grants permitted')
   observations.append({'index':index,'udid':self.udid,'pid':returned['pid'],'pid_started':lane.pid_started(returned['pid']),'actual_args':argument_list,'ready_seconds':returned['ready_seconds'],'ready_signal':returned['ready_signal'],'actual_ready':actual_events[0],'frame':str(image),'frame_sha256':sha(image),'verdict':returned['verdict'],'session_sha256':sha(session),'demo_state':'App-created session.json, one active unnamed draft, exact bundled demo text, no grant metadata'})
   (destination/'observations.json').write_text(json.dumps(observations,ensure_ascii=False,indent=2)+'\n')
   return returned
 def observed_boot(udid,timeout):
  if ATTEMPT:ATTEMPT.require('boot')
  journal.before_boot(udid)
  return original_boot(udid,timeout)
 lane.ReadyStream=ObservedReady;lane.Session=ObservedSession;lane.boot=observed_boot
 try:
  yield journal,observations
 finally:
  lane.ReadyStream=OriginalReady;lane.Session=OriginalSession;lane.boot=original_boot

def observe_worker(platform,destination,before):
 with observation_context(platform,destination,before) as (journal,observations):
  canonical=module('folio_canonical_platform_measure',MEASURE)
  original_selection=canonical.measurement_device
  def observed_selection(*args,**kwargs):
   if ATTEMPT:ATTEMPT.require('device selection')
   actual=original_selection(*args,**kwargs);journal.selected(actual);return actual
  canonical.measurement_device=observed_selection
  try:return canonical.main(canonical_args(platform))
  finally:canonical.measurement_device=original_selection

def main():
 global SPAWNING,PENDING_INTERRUPT,ROOT,ATTEMPT
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--platform',choices=['iphone','ipad','vision'],required=True);parser.add_argument('--execute',action='store_true');parser.add_argument('--worker',type=Path);parser.add_argument('--slot-seconds',type=int,default=600);parser.add_argument('--workdir',type=Path,required=True)
 options=parser.parse_args();ATTEMPT=attempt_budget.Attempt(options.slot_seconds,worker=bool(options.worker));ROOT=options.workdir.resolve()
 if ROOT.is_relative_to(REPO.parents[1]):raise RuntimeError('workdir must be outside Folio source family')
 before=inputs(options.platform);expected=json.loads((ROOT/'resource-binding.json').read_text())
 if before!=expected['platforms'][options.platform]:raise RuntimeError('recipe source/SDK/package/ABI binding changed; no rebind')
 if options.worker:
  owner=int(os.environ.get('FOLIO_RESOURCE_OBSERVER_OWNER_PID','0'))
  if owner!=os.getppid() or lane.pid_started(owner)!=os.environ.get('FOLIO_RESOURCE_OBSERVER_OWNER_STARTED'):raise RuntimeError('worker has no matching owning controller identity')
  if not options.worker.resolve().is_relative_to(ROOT/'runs'):raise RuntimeError('worker artifact path outside own tree')
  return observe_worker(options.platform,options.worker,before)
 plan={'status':'dry-only-no-device','inputs':before,'command':[PYTHON,str(MEASURE),*canonical_args(options.platform)],'observation':'pure wraps original ReadyStream._wait result and Session.launch returned frame; binary copy only; no changed wait/launch/metrics/args','scope':'ordinary Release synthetic isolated document via production newDocument and SessionDisk, original Editor in default reading=true mode. welcome launch is separate. No keyboard-edit/large-document resource, Files grant/OS scene/user input/WC/store claim','gate':'Root-only heavy slot, Chapter NB flock then canonical Session lock/load wait0','helper_rule':'actual UDID/PID/start verified WebContent total required; unproven launchd XPC fails closed','future_seed_primitive':'original CLI --state <isolated> new <text> remains available in source, not built/installed here; no hand-written session schema'}
 if not options.execute:print(json.dumps(plan,ensure_ascii=False,indent=2));return 0
 if original_process.gui_processes():raise RuntimeError('GUI present; no heavy started')
 directory=ROOT/'runs'/(datetime.datetime.now().astimezone().strftime('%Y%m%d-%H%M%S')+'-'+options.platform+'-'+str(os.getpid()));directory.mkdir(parents=True,exist_ok=False)
 record={'status':'not-passed','before':before,'started_at':datetime.datetime.now().astimezone().isoformat(),'operations':[]};errors=[];child=None;identity='';observed={};log=directory/'canonical.log'
 controller={'pid':os.getpid(),'pid_started':lane.pid_started(os.getpid())};global_held=False
 global_lock=(sop.STATE_DIR/'lock').open('a')
 try:
  ATTEMPT.require('Chapter NB admission')
  fcntl.flock(global_lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
  global_held=True
  with log.open('w') as output:
   PENDING_INTERRUPT=None
   SPAWNING=True
   try:
    child=subprocess.Popen([PYTHON,str(Path(__file__).resolve()),'--platform',options.platform,'--worker',str(directory),'--workdir',str(ROOT),'--slot-seconds',str(options.slot_seconds)],stdout=output,stderr=subprocess.STDOUT,env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1','FOLIO_RESOURCE_OBSERVER_OWNER_PID':str(controller['pid']),'FOLIO_RESOURCE_OBSERVER_OWNER_STARTED':controller['pid_started'],**ATTEMPT.environment()},start_new_session=True)
    identity=lane.pid_started(child.pid);observed[child.pid]=identity
   finally:SPAWNING=False
   if PENDING_INTERRUPT is not None:
    signum,PENDING_INTERRUPT=PENDING_INTERRUPT,None
    raise InterruptedError('signal during child registration '+str(signum))
   while child.poll() is None:
    for pid in original_process.group_members(child.pid):observed.setdefault(pid,lane.pid_started(pid))
    if original_process.gui_processes():raise RuntimeError('Simulator/AppSimulator GUI appeared')
    if ATTEMPT.expired():record['budget_crossed_during_existing_child']=True
    time.sleep(.25)
  record['exit_code']=child.returncode
  if original_process.gui_processes():raise RuntimeError('Simulator/AppSimulator GUI appeared at worker exit')
  if child.returncode:raise RuntimeError('original resource operation exit '+str(child.returncode)+'; no retry')
  observations=json.loads((directory/'observations.json').read_text())
  if len(observations)!=7:raise RuntimeError('actual discarded + five counted + idle Editor launches missing')
  doc=json.loads((REPO/'perf/platforms'/str(options.platform+'.json')).read_text());raw_path=REPO/doc['runtime_measurement']['evidence'];raw=json.loads(raw_path.read_text());m=raw['measurement'];proof=m['idle'].get('provenance') or {}
  if raw['input_sha256']!=before['source']['sha256'] or raw['build']['configuration']!='Release' or raw['build']['executable_sha256']!=before['executable_sha256'] or raw['build']['sdk']!=before['sdk']:raise RuntimeError('actual measurement source/ordinary binary/SDK differs from bound input')
  if not m.get('with_helpers') or proof.get('main',{}).get('pid')!=observations[-1]['pid'] or any(s['pid']!=o['pid'] or s['ready_seconds']!=o['ready_seconds'] for s,o in zip(m['samples'],observations[:6])):raise RuntimeError('canonical measured PIDs/readiness do not bind the actual observed Editor launches')
  if not proof.get('verified') or proof.get('udid')!=m['udid'] or not any('WebContent' in p.get('name','') for p in m['idle'].get('processes',[])):raise RuntimeError('actual App-owned WebContent total unproven; no resource pass')
  if raw['tool_sha256']!={'measure.py':PINS[list(PINS)[0]],'platform_measure.py':PINS[str(MEASURE)],'sim_lane.py':PINS[str(LANE)]} or sha(raw_path)!=doc['runtime_measurement']['evidence_sha256']:raise RuntimeError('canonical resource evidence bindings changed')
  if doc['speed']['runs']!=5 or doc['speed']['discarded_runs']!=1 or m['settle_s']!=45 or m['idle']['window_s']!=60 or m['device_selection'].get('shutdown_verified') is not True:raise RuntimeError('canonical 5-run/45/60/owned shutdown contract not met')
  budget={'memory_mb':150,'cpu_pct':.5,'download_mb':12,'cold_launch_ms':2000 if options.platform=='vision' else 1500};actual={'memory_mb':doc['idle']['memory_mb'],'cpu_pct':doc['idle']['cpu_pct'],'download_mb':doc['size']['download_mb'],'cold_launch_ms':doc['speed']['cold_launch_ms']}
  record.update(resource_evidence=str(raw_path),resource_evidence_sha256=sha(raw_path),observations_sha256=sha(directory/'observations.json'),actual=actual,budget=budget)
  if any(type(actual[k]) not in (int,float) or not 0<=actual[k]<=v for k,v in budget.items()):raise RuntimeError('actual Editor resources/startup budget exceeded')
  record['status']='candidate-pass-cleanup-pending'
 except BaseException as error:errors.append(type(error).__name__+': '+str(error))
 finally:
  with guard.cleanup_signals_blocked():
   try:
    record['cleanup']=guard.cleanup(lane,original_process,child,identity,observed,directory,controller) if global_held else {'clear':True,'device':'global NB not acquired; worker never started'}
    record['cleanup']['chapter_global_held_during_observation']=global_held
    guard.atomic_json(directory/'cleanup.json',record['cleanup'])
    record['cleanup_sha256']=sha(directory/'cleanup.json')
    if not record['cleanup']['clear']:errors.append('own cleanup incomplete: '+json.dumps(record['cleanup']['errors'],ensure_ascii=False))
   except BaseException as error:errors.append('own process/device cleanup: '+str(error))
   finally:global_lock.close()  # only after actual own-device terminal / lock observation
  try:record['after']=inputs(options.platform);record['input_stable']=record['after']==before
  except BaseException as error:errors.append('final readonly validation: '+str(error))
  if not record.get('input_stable'):errors.append('input changed')
  record.update(finished_at=datetime.datetime.now().astimezone().isoformat(),process_group=observed,log=str(log),log_sha256=sha(log) if log.exists() else None,errors=errors)
  ATTEMPT.finalize(record,errors,'candidate-pass-cleanup-pending','passed-ordinary-release-editor-simulator-resource-scope-only')
  (directory/'result.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n');print(json.dumps(record,ensure_ascii=False,indent=2))
 return 0 if record['status'].startswith('passed-') else 1

def interrupted(signum,frame):
 global PENDING_INTERRUPT
 if SPAWNING:
  PENDING_INTERRUPT=signum;return  # register real child PID/start before same finally cleanup
 raise InterruptedError('signal '+str(signum))
if __name__=='__main__':
 signal.signal(signal.SIGTERM,interrupted);signal.signal(signal.SIGINT,interrupted)
 sys.exit(main())
