"""Folio-only dedicated device creation receipts; original lane gate and ensure_device."""
import datetime
import json
import os
from pathlib import Path

PHONE = '12B97992-764F-4AAE-9C54-C41E5BEADA0B'
RULES = {
    'iphone': {'name':'Folio Store iPhone 20261003', 'device_type':'iPhone-17-Pro-Max', 'runtime':'com.apple.CoreSimulator.SimRuntime.iOS-27-0'},
    'ipad': {'name':'Folio Resource iPad 20261003', 'device_type':'iPad-Pro-13-inch-M5-12GB', 'runtime':'com.apple.CoreSimulator.SimRuntime.iOS-27-0'},
    'vision': {'name':'Folio Resource Vision 20261003', 'device_type':'Apple-Vision-Pro-4K', 'runtime':'com.apple.CoreSimulator.SimRuntime.xrOS-27-0'},
}

def rule(platform, purpose):
    value = dict(RULES[platform])
    if platform == 'iphone' and purpose == 'launch':
        value.update(name='Folio Integration', device_type='iPhone-17-Pro', udid=PHONE)
    return value

def match(device, wanted):
    if any(device.get(k) != wanted[k] for k in ('name','device_type','runtime')):
        raise RuntimeError('actual dedicated device name/type/runtime differs')
    if wanted.get('udid') and device.get('udid') != wanted['udid']:
        raise RuntimeError('explicit actual dedicated UDID differs')
    if not device.get('available') or device.get('state') != 'Shutdown':
        raise RuntimeError('actual dedicated device must be available and Shutdown')

def prior_owner(path, wanted, actual_matches):
    if path is None: raise RuntimeError('dedicated name already present without an explicit genuine prior owner receipt')
    owner = json.loads(Path(path).read_text())
    original = owner.get('original_creation') or owner
    if owner.get('family') != 'folio' or original.get('family') != 'folio' or original.get('creation_before_absent') is not True or original.get('ensure_return',{}).get('created') is not True:
        raise RuntimeError('prior owner was not a genuine before-absent original creation')
    identity = owner['actual_device']; match(identity, {**wanted,'udid':identity['udid']})
    original_identity = original['actual_device']; match(original_identity, {**wanted,'udid':identity['udid']})
    if original.get('ensure_return',{}).get('udid') != identity['udid'] or original.get('creation_gate',{}).get('before_name_matches') != []:
        raise RuntimeError('prior owner lacks actual before-absent inventory/created UDID evidence')
    if len(actual_matches) != 1 or actual_matches[0].get('udid') != identity['udid']:
        raise RuntimeError('actual same-name devices do not match the prior creation UDID')
    return owner

def configure_guard(guard, platform, purpose, owner):
    wanted = rule(platform, purpose); actual = owner['actual_device']; match(actual, wanted)
    guard.OWNER_NAMES = {**guard.OWNER_NAMES, platform:wanted['name']}
    guard.OWNER_TYPES = {**guard.OWNER_TYPES, platform:wanted['device_type']}
    if platform == 'iphone': guard.PHONE = actual['udid']

def register(recipe, platform, purpose, destination, prior=None):
    """Run only in a real future owning child, with parent Chapter global NB held."""
    lane, guard = recipe.lane, recipe.guard
    wanted = rule(platform, purpose)
    recipe.ATTEMPT.require('owned creation directory/load admission')
    locks = lane.lock_chain('Folio owned creation ' + purpose + ' ' + platform)
    worker = {'pid':os.getpid(), 'pid_started':lane.pid_started(os.getpid())}
    controller = {'pid':int(os.environ['FOLIO_RESOURCE_OBSERVER_OWNER_PID']),
                  'pid_started':os.environ['FOLIO_RESOURCE_OBSERVER_OWNER_STARTED']}
    if controller['pid'] != os.getppid() or lane.pid_started(controller['pid']) != controller['pid_started']:
        raise RuntimeError('creation parent PID/start mismatch')
    acquired = False
    try:
        lane.acquire(locks, wanted.get('udid'), 0, 0, lane.max_load_default()); acquired = True
        gate = {'controller':controller, 'worker':worker, 'phase':'creation-admitted-no-boot',
                'platform':platform, 'purpose':purpose, 'request':wanted,
                'locks':[guard.lock_snapshot(lock) for lock in locks], 'at':datetime.datetime.now().astimezone().isoformat()}
        if len(gate['locks']) != 1 or Path(gate['locks'][0]['path']) != guard.CANONICAL_LOCK.resolve():
            raise RuntimeError('creation must hold the original canonical directory gate')
        guard.atomic_json(destination/'creation-gate.json', gate)
        recipe.ATTEMPT.require('actual dedicated device inventory')
        raw = lane.simctl('list','devices','--json').stdout
        data = json.loads(raw); matches = []
        for runtime, rows in data.get('devices',{}).items():
            matches.extend({**row,'runtime':runtime} for row in rows if row.get('name') == wanted['name'])
        gate.update(before_inventory_sha256=__import__('hashlib').sha256(raw.encode()).hexdigest(),
                    before_name_matches=matches)
        guard.atomic_json(destination/'creation-gate.json',gate)
        if wanted.get('udid'):
            actual = lane.device_info(wanted['udid']); match(actual,wanted)
            owner = {'family':'folio','platform':platform,'purpose':purpose,'basis':'explicit Root-owned existing Folio Integration phone',
                     'creation_before_absent':False,'ensure_return':None,'actual_device':actual}
        else:
            if matches:
                previous = prior_owner(prior,wanted,matches)
                returned = {'created':False,'udid':previous['actual_device']['udid']}
            else:
                recipe.ATTEMPT.require('original ensure_device creation')
                returned = lane.ensure_device(platform,wanted['device_type'],wanted['name'],wanted['runtime'])
                if returned.get('created') is not True or any(returned.get(k) != wanted[k] for k in ('name','device_type','runtime')):
                    raise RuntimeError('before-absent original ensure did not return actual expected creation')
                guard.atomic_json(destination/'creation-returned.json',{'gate':gate,'ensure_return':returned})
            recipe.ATTEMPT.require('actual created device owner readback')
            actual = lane.device_info(returned['udid']); match(actual,{**wanted,'udid':returned['udid']})
            owner = {'family':'folio','platform':platform,'purpose':purpose,
                     'basis':'actual before-absent original ensure_device + actual readback' if not matches else 'explicit genuine prior owner receipt + actual same UID readback',
                     'creation_before_absent':not matches,'ensure_return':returned,'actual_device':actual,
                     'previous_owner':str(Path(prior).resolve()) if prior else None,
                     'previous_owner_sha256':recipe.sha(prior) if prior else None}
            if matches:
                # Preserve the original creation proof rather than invent a second creation.
                owner['original_creation'] = previous.get('original_creation') or previous
        owner.update(controller=controller,worker=worker,source=recipe.inputs(platform),creation_gate=gate,
                     native_sha256=recipe.PINS[str(recipe.LANE)],creation_gate_sha256=recipe.sha(destination/'creation-gate.json'))
        guard.atomic_json(destination/'owner.json',owner)
        configure_guard(guard,platform,purpose,owner)
        return owner
    finally:
        if acquired:
            for lock in reversed(locks): lock.release()  # original release of this child's held live gate

def configure_from_receipt(recipe, platform, purpose, destination, controller, child, started, source):
    path = destination/'owner.json'
    if not path.exists(): return None
    owner = json.loads(path.read_text())
    if owner.get('family') != 'folio' or owner.get('platform') != platform or owner.get('purpose') != purpose:
        raise RuntimeError('owner receipt purpose/family/platform differs')
    if owner.get('controller') != controller or owner.get('worker') != {'pid':child.pid,'pid_started':started} or owner.get('source') != source:
        raise RuntimeError('owner receipt source/parent/child identity differs')
    configure_guard(recipe.guard,platform,purpose,owner)
    return owner

def configure_from_journal(recipe, platform, purpose, destination, controller, child, started):
    """A real boot-admission journal remains usable if permission/owner metadata is unreadable.

    This configures only this private guard instance. It never creates a device,
    claims a static UID, alters the journal, or substitutes a Shutdown result.
    The original guard still verifies the held gate and actual terminal identity.
    """
    path = destination/'admission.json'
    if not path.exists(): return False
    value = json.loads(path.read_text())
    if value.get('controller') != controller or value.get('worker') != {'pid':child.pid,'pid_started':started} or value.get('destination') != str(destination.resolve()) or value.get('platform') != platform:
        raise RuntimeError('fallback admission does not bind this parent/child/platform/path')
    if value.get('phase') not in ('selected-no-boot','boot-admitted'):
        raise RuntimeError('fallback admission has no actual selected device')
    actual = value['device']; wanted = rule(platform,purpose)
    if any(actual.get(k) != wanted[k] for k in ('name','device_type','runtime')) or not actual.get('available') or not actual.get('udid'):
        raise RuntimeError('fallback actual admission differs from dedicated device policy')
    if wanted.get('udid') and actual['udid'] != wanted['udid']:
        raise RuntimeError('fallback explicit phone UID differs')
    recipe.guard.OWNER_NAMES = {**recipe.guard.OWNER_NAMES, platform:wanted['name']}
    recipe.guard.OWNER_TYPES = {**recipe.guard.OWNER_TYPES, platform:wanted['device_type']}
    if platform == 'iphone': recipe.guard.PHONE = actual['udid']
    return True

def cleanup_owned(recipe, platform, purpose, child, started, observed, destination, controller, source):
    """Metadata failure must never skip the original bound-child/group cleanup."""
    metadata_errors = []
    try:
        if child:
            owner = configure_from_receipt(recipe,platform,purpose,destination,controller,child,started,source)
            if owner is None and (destination/'admission.json').exists():
                raise RuntimeError('owner receipt missing after actual selected admission')
    except Exception as error:
        metadata_errors.append('owner receipt: '+type(error).__name__+': '+str(error))
        try:
            if child: configure_from_journal(recipe,platform,purpose,destination,controller,child,started)
        except Exception as fallback:
            metadata_errors.append('admission identity: '+type(fallback).__name__+': '+str(fallback))
    # ALWAYS invoked, including malformed/missing owner metadata. Guard first
    # stops the own PID/start group and proves it ended before any device access.
    result = recipe.guard.cleanup(recipe.lane,recipe.original_process,child,started,observed,destination,controller)
    if metadata_errors:
        result['clear'] = False
        result['errors'].extend(metadata_errors)
    try: creation_tail(recipe,child,started,destination,result)
    except Exception as error:
        result['clear'] = False
        result['errors'].append('creation terminal: '+type(error).__name__+': '+str(error))
    return result

def creation_tail(recipe, child, started, destination, cleanup):
    """Observe any killed-child creation lock, even if boot journal never existed."""
    if child is None: return
    lock = recipe.lane.Lock(recipe.guard.CANONICAL_LOCK,'Folio creation terminal')
    if lock.path.exists() or lock.path.is_symlink():
        actual = recipe.guard.lock_snapshot(lock); rec = actual['record']
        cleanup['creation_directory_terminal'] = actual
        if rec.get('pid') == child.pid and rec.get('pid_started') == started:
            cleanup['clear'] = False
            cleanup['errors'].append('own creation directory lock remains; no expected-owner atomic release API')
        else: cleanup['creation_foreign_directory_untouched'] = True
    if (destination/'creation-returned.json').exists() and not (destination/'owner.json').exists():
        cleanup['clear'] = False
        cleanup['errors'].append('actual create returned but owner readback/registration incomplete; boot was never admitted, owner followup required')
