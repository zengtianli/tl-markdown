"""Folio recipe-only ownership journal and bounded failure observation; no shared edits."""
import contextlib
import hashlib
import json
import os
from pathlib import Path
import signal
import stat

CANONICAL_LOCK = Path.home() / 'Library/Caches/sim-lane/lock'
PHONE = '12B97992-764F-4AAE-9C54-C41E5BEADA0B'
OWNER_NAMES = {'iphone': 'Folio Integration', 'ipad': 'Folio Resource iPad 20261003',
               'vision': 'Folio Resource Vision 20261003'}
OWNER_TYPES = {'iphone': 'iPhone-17-Pro', 'ipad': 'iPad-Pro-13-inch-M5-12GB',
               'vision': 'Apple-Vision-Pro-4K'}

def reject_environment(environment=None):
    """Must run before importing sim_lane, whose LOCK_DIR captures the environment."""
    environment = os.environ if environment is None else environment
    if environment.get('SIM_LANE_EXTRA_LOCK'):
        raise RuntimeError('SIM_LANE_EXTRA_LOCK override rejected; original canonical chain only')
    override = environment.get('SIM_LANE_LOCK')
    if override and Path(override).expanduser().resolve() != CANONICAL_LOCK.resolve():
        raise RuntimeError('SIM_LANE_LOCK override rejected before sim_lane import')

def check_lane(lane):
    if lane.LOCK_DIR.resolve() != CANONICAL_LOCK.resolve():
        raise RuntimeError('imported sim_lane uses a noncanonical directory gate')

def atomic_json(path, value):
    path = Path(path)
    temp = path.with_name(path.name + '.writing-' + str(os.getpid()))
    with temp.open('x') as output:
        json.dump(value, output, ensure_ascii=False, indent=2)
        output.write('\n'); output.flush(); os.fsync(output.fileno())
    os.replace(temp, path)
    fd = os.open(path.parent, os.O_RDONLY)
    try: os.fsync(fd)
    finally: os.close(fd)

def owned_device(platform, device):
    if device.get('name') != OWNER_NAMES[platform] or device.get('device_type') != OWNER_TYPES[platform]:
        raise RuntimeError('actual dedicated device owner/name/type differs')
    if platform == 'iphone' and device.get('udid') != PHONE:
        raise RuntimeError('phone must be the existing explicitly owned UDID')
    ending = 'xrOS-27-0' if platform == 'vision' else 'iOS-27-0'
    if not device.get('runtime', '').endswith(ending) or not device.get('available'):
        raise RuntimeError('actual dedicated device runtime/availability differs')
    return {k: device[k] for k in ('udid', 'name', 'device_type', 'runtime', 'available')}

def lock_snapshot(lock):
    path = lock.path
    metadata = path.lstat()
    if not stat.S_ISDIR(metadata.st_mode) or path.is_symlink():
        raise RuntimeError('canonical lock is not an ordinary directory')
    raw = (path / 'sim_lane.json').read_bytes()
    return {'path': str(path.resolve()), 'dev': metadata.st_dev, 'ino': metadata.st_ino,
            'record': json.loads(raw), 'record_sha256': hashlib.sha256(raw).hexdigest()}

class AdmissionJournal:
    """Observe actual original device selection and held gate before original boot."""
    def __init__(self, lane, platform, destination):
        self.lane, self.platform, self.destination = lane, platform, Path(destination)
        self.device = self.session = None
        self.owner = {'pid': int(os.environ['FOLIO_RESOURCE_OBSERVER_OWNER_PID']),
                      'pid_started': os.environ['FOLIO_RESOURCE_OBSERVER_OWNER_STARTED']}
        self.worker = {'pid': os.getpid(), 'pid_started': lane.pid_started(os.getpid())}
        if self.owner['pid'] != os.getppid() or lane.pid_started(self.owner['pid']) != self.owner['pid_started']:
            raise RuntimeError('journal controller PID/start differs')
        self.value = {'controller': self.owner, 'worker': self.worker, 'platform': platform,
                      'destination': str(self.destination.resolve()), 'phase': 'no-device-selection'}

    def selected(self, device):
        identity = owned_device(self.platform, device)
        if device.get('state') != 'Shutdown':
            raise RuntimeError('dedicated device is not Shutdown before admission')
        self.device = dict(device)
        self.value.update(device=identity, state_before=device['state'], phase='selected-no-boot')
        atomic_json(self.destination / 'admission.json', self.value)

    def before_boot(self, udid):
        if self.device is None or self.session is None or udid != self.device['udid'] or udid != self.session.udid:
            raise RuntimeError('original boot lacks a selected dedicated device/Session')
        locks = self.session.locks
        if len(locks) != 1 or locks[0].path.resolve() != CANONICAL_LOCK.resolve() or not locks[0].held:
            raise RuntimeError('original Session did not acquire the canonical directory gate')
        actual = lock_snapshot(locks[0])
        rec = actual['record']
        if rec.get('pid') != self.worker['pid'] or rec.get('pid_started') != self.worker['pid_started'] or rec.get('label') != self.session.label:
            raise RuntimeError('held original directory lock does not identify this worker')
        self.value.update(phase='boot-admitted', locks=[actual], session_work=str(self.session.work.resolve()))
        atomic_json(self.destination / 'admission.json', self.value)

@contextlib.contextmanager
def cleanup_signals_blocked():
    """A second external signal cannot release the global gate midway through cleanup."""
    old = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM, signal.SIGINT})
    try: yield
    finally:
        # Pending signals are discarded after bounded cleanup; record already retains first signal.
        for signum in (signal.SIGTERM, signal.SIGINT):
            if signum in signal.sigpending(): signal.sigwait({signum})
        signal.pthread_sigmask(signal.SIG_SETMASK, old)

def cleanup(lane, process_helpers, child, child_started, observed, destination, controller):
    """Called while Chapter global NB is held. No foreign device/lock operations."""
    result = {'scope': 'own worker/device only', 'clear': False, 'actions': [], 'errors': []}
    cleanup_lock = None; protect_gate = False
    try:
        try:
            process_helpers.stop_group(child, child_started, observed)
        except Exception as error:
            # Preserve original helper error. Its stale pre-poll ps row is not current terminal state.
            # No further signals/retry: continue ONLY if the following actual end/group checks pass.
            result['original_stop_group_error'] = type(error).__name__ + ': ' + str(error)
        if child is None:
            return {**result, 'clear': True, 'worker': 'not-started', 'device': 'not-admitted'}
        child.poll()
        remaining = process_helpers.group_members(child.pid)
        result['worker'] = {'pid': child.pid, 'pid_started': child_started, 'exit_code': child.returncode,
                            'remaining_group': {pid: lane.pid_started(pid) for pid in remaining}}
        if child.returncode is None or remaining or (lane.pid_alive(child.pid) and lane.pid_started(child.pid) == child_started):
            raise RuntimeError('owned child/group has not ended; no fallback device operation')
        journal_path = Path(destination) / 'admission.json'
        if not journal_path.exists():
            return {**result, 'clear': True, 'device': 'no durable boot admission; original boot was never invoked'}
        value = json.loads(journal_path.read_text())
        if value.get('controller') != controller or value.get('worker') != {'pid': child.pid, 'pid_started': child_started} or value.get('destination') != str(Path(destination).resolve()):
            raise RuntimeError('actual admission journal is not this controller/child identity')
        result['journal_sha256'] = hashlib.sha256(journal_path.read_bytes()).hexdigest()
        if value['phase'] == 'selected-no-boot':
            lock = lane.Lock(CANONICAL_LOCK, 'Folio selected-before-boot terminal check')
            if lock.path.exists() or lock.path.is_symlink():
                current = lock_snapshot(lock); result['directory_lock_final'] = current
                rec = current['record']
                if rec.get('pid') == child.pid and rec.get('pid_started') == child_started:
                    result['own_lock_stale'] = lock.stale(set())
                    raise RuntimeError('own directory lock remains from acquire→journal interruption; no expected-owner atomic release API')
                result['foreign_directory_untouched'] = True
            else: result['directory_lock_final'] = 'absent'
            return {**result, 'clear': True, 'device': 'selected but original boot never invoked'}
        if value['phase'] != 'boot-admitted':
            raise RuntimeError('unknown actual journal admission phase')
        expected = owned_device(value['platform'], value['device'])
        locks = value['locks']
        if len(locks) != 1 or Path(locks[0]['path']) != CANONICAL_LOCK.resolve():
            raise RuntimeError('journal canonical chain differs')
        lock = lane.Lock(CANONICAL_LOCK, locks[0]['record']['label'])
        if lock.path.exists() or lock.path.is_symlink():
            current = lock_snapshot(lock)
            result['directory_lock'] = current
            if current != locks[0]:
                raise RuntimeError('canonical directory lock changed/foreign; leave device and lock untouched')
        else:
            result['directory_lock'] = 'absent: original Session released its gate'
            # Reuse original atomic acquisition but never reclaim any stale/foreign directory.
            class NoReclaimLock(lane.Lock):
                def stale(self, booted, want_udid=None): return False
            cleanup_lock = NoReclaimLock(CANONICAL_LOCK, 'Folio controller own-device terminal check')
            if not cleanup_lock.try_acquire(set()):
                raise RuntimeError('canonical gate acquired by another owner; no fallback device operation')
            protect_gate = True  # boot-admitted journal; unknown terminal stays protected until actual Shutdown
            result['controller_cleanup_lock'] = lock_snapshot(cleanup_lock)
        actual = lane.device_info(expected['udid'])  # original bounded simctl list (120 s)
        if owned_device(value['platform'], actual) != expected:
            raise RuntimeError('actual dedicated device identity changed; no shutdown')
        result['device_before_cleanup'] = actual
        if actual.get('state') != 'Shutdown':
            result['actions'].append('original sim_lane.shutdown(own UDID), maximum 180 s')
            try: lane.shutdown(expected['udid'])
            except Exception as error: result['shutdown_error'] = str(error)
        final = lane.device_info(expected['udid'])  # original bounded read, even if shutdown raised
        result['device_after_cleanup'] = final
        if owned_device(value['platform'], final) != expected or final.get('state') != 'Shutdown':
            raise RuntimeError('owned device has no actual Shutdown terminal proof')
        protect_gate = False
        work = Path(value['session_work'])
        result['original_session_work_final'] = {'path': str(work), 'exists': work.exists()}
        if work.exists():
            result['original_session_work_final']['owner'] = json.loads((work / lane.OWNER_FILE).read_text())
            result['original_session_work_final']['remaining'] = 'original Session finally did not remove its workspace; not pruned by controller'
        if cleanup_lock is None and (lock.path.exists() or lock.path.is_symlink()):
            final_lock = lock_snapshot(lock)
            result['directory_lock_final'] = final_lock
            if final_lock != locks[0]:
                raise RuntimeError('final directory lock changed/foreign; never remove it')
            result['own_lock_stale'] = lock.stale(set())
            raise RuntimeError('own stale directory lock remains: original API has no expected-owner/inode release; canonical next admission may reclaim, owner action required')
        result['directory_lock_final'] = 'absent'
        if work.exists():
            raise RuntimeError('original own Session workspace remains; no zero-tail claim')
        result['clear'] = True
    except Exception as error:
        result['errors'].append(type(error).__name__ + ': ' + str(error))
    finally:
        if cleanup_lock is not None and cleanup_lock.held:
            try:
                actual = lock_snapshot(cleanup_lock)
                if actual != result['controller_cleanup_lock']:
                    raise RuntimeError('controller cleanup gate identity changed; leave foreign directory untouched')
                if protect_gate:
                    cleanup_lock.keep(expected['udid'])  # Root authorized only our freshly atomically acquired gate
                    result['remainsOwnGate'] = lock_snapshot(cleanup_lock)
                    result['controller_cleanup_lock_final'] = 'kept by original Lock.keep(own UDID); failed, owner action required'
                    result['clear'] = False
                else:
                    cleanup_lock.release()  # original release of our live, freshly acquired gate only
                    result['controller_cleanup_lock_final'] = 'released by original Lock.release'
            except Exception as error:
                result['clear'] = False
                result['errors'].append('cleanup gate: ' + str(error))
    return result
