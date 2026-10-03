#!/usr/bin/env python3
"""Pure temporary fake-Lane counterexamples. No real gate, process, device or app."""
import contextlib
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import devices

class PureDevices(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='folio-owned-pure.')
        self.root = Path(self.temp.name); self.events = []
        self.wanted = devices.rule('iphone','store')
        self.actual = {**self.wanted,'udid':'SYNTHETIC-PURE-UID','state':'Shutdown','available':True}
        self.inventory = []; self.readback_override = None
        self.guard = SimpleNamespace(CANONICAL_LOCK=self.root/'synthetic-gate',PHONE=devices.PHONE,
            OWNER_NAMES={},OWNER_TYPES={},atomic_json=self.write_json,lock_snapshot=lambda lock:{'path':str(lock.path.resolve()),'record':{'pid':os.getpid(),'pid_started':'synthetic-start'}})
        self.lock = SimpleNamespace(path=self.guard.CANONICAL_LOCK,release=self.release)
        self.lane = SimpleNamespace(lock_chain=lambda label:[self.lock],pid_started=lambda pid:'synthetic-start',
            max_load_default=lambda:75,acquire=self.acquire,simctl=self.inventory_read,
            ensure_device=self.ensure,device_info=self.readback,Lock=lambda *args: self.lock)
        self.recipe = SimpleNamespace(lane=self.lane,guard=self.guard,ATTEMPT=SimpleNamespace(require=lambda stage:self.events.append('budget:'+stage)),
            inputs=lambda platform:{'synthetic':'pure-source-binding'},PINS={'synthetic-lane':'pure-sha'},LANE='synthetic-lane',
            sha=lambda path:__import__('hashlib').sha256(Path(path).read_bytes()).hexdigest())
        self.env = patch.dict(os.environ,{'FOLIO_RESOURCE_OBSERVER_OWNER_PID':str(os.getppid()),'FOLIO_RESOURCE_OBSERVER_OWNER_STARTED':'synthetic-start'})
        self.env.start()
    def tearDown(self):self.env.stop();self.temp.cleanup()
    def write_json(self,path,value):Path(path).write_text(json.dumps(value))
    def acquire(self,*args):self.events.append('original-acquire');self.lock.path.mkdir()
    def release(self):self.events.append('original-own-release');self.lock.path.rmdir()
    def inventory_read(self,*args):
        self.assertTrue(self.lock.path.exists());self.events.append('original-inventory')
        return SimpleNamespace(stdout=json.dumps({'devices':{self.wanted['runtime']:self.inventory}}))
    def ensure(self,platform,device_type,name,runtime):
        self.assertTrue(self.lock.path.exists());self.events.append('original-ensure')
        self.assertEqual((platform,device_type,name,runtime),('iphone',self.wanted['device_type'],self.wanted['name'],self.wanted['runtime']))
        self.inventory=[dict(self.actual)]
        return {**self.actual,'created':True}
    def readback(self,uid):
        self.assertTrue(self.lock.path.exists());self.events.append('actual-readback')
        self.assertEqual(uid,self.actual['udid']);return self.readback_override or dict(self.actual)
    def destination(self,name):path=self.root/name;path.mkdir();return path
    def register(self,name,prior=None):return devices.register(self.recipe,'iphone','store',self.destination(name),prior)
    def test_creation_is_gated_and_bound(self):
        owner=self.register('first')
        self.assertTrue(owner['creation_before_absent']);self.assertEqual(owner['creation_gate']['before_name_matches'],[])
        self.assertEqual(owner['ensure_return']['udid'],owner['actual_device']['udid'])
        self.assertEqual(owner['worker'],{'pid':os.getpid(),'pid_started':'synthetic-start'})
        self.assertLess(self.events.index('original-acquire'),self.events.index('original-ensure'))
        self.assertLess(self.events.index('actual-readback'),self.events.index('original-own-release'))
        self.assertFalse(self.lock.path.exists())
    def test_same_name_without_owner_never_reclaims_or_creates(self):
        self.inventory=[dict(self.actual)]
        with self.assertRaisesRegex(RuntimeError,'without an explicit genuine'):self.register('foreign')
        self.assertNotIn('original-ensure',self.events);self.assertNotIn('actual-readback',self.events)
        self.assertFalse(self.lock.path.exists())
    def test_owner_reuse_preserves_original_creation_twice(self):
        first=self.register('first');second=self.register('second',self.root/'first/owner.json')
        third=self.register('third',self.root/'second/owner.json')
        self.assertEqual(third['actual_device']['udid'],first['actual_device']['udid'])
        self.assertFalse(second['creation_before_absent']);self.assertFalse(third['ensure_return']['created'])
        self.assertEqual(third['original_creation'],first);self.assertEqual(self.events.count('original-ensure'),1)
    def test_changed_original_uid_rejected(self):
        self.register('first');path=self.root/'first/owner.json';value=json.loads(path.read_text())
        value['ensure_return']['udid']='SYNTHETIC-FOREIGN-UID';self.write_json(path,value)
        with self.assertRaisesRegex(RuntimeError,'created UDID evidence'):self.register('changed',path)
        self.assertEqual(self.events.count('original-ensure'),1)
    def test_creation_readback_failure_retains_real_incomplete_evidence(self):
        self.readback_override={**self.actual,'name':'SYNTHETIC-WRONG-NAME'}
        with self.assertRaisesRegex(RuntimeError,'name/type/runtime differs'):self.register('mismatch')
        destination=self.root/'mismatch'
        self.assertTrue((destination/'creation-returned.json').exists());self.assertFalse((destination/'owner.json').exists())
        result={'clear':True,'errors':[]}
        devices.creation_tail(self.recipe,SimpleNamespace(pid=os.getpid()),'synthetic-start',destination,result)
        self.assertFalse(result['clear']);self.assertIn('registration incomplete',result['errors'][0])
        self.assertFalse(self.lock.path.exists())
    def cleanup_setup(self,destination):
        child=SimpleNamespace(pid=7);controller={'pid':8,'pid_started':'synthetic-parent'}
        self.recipe.original_process=SimpleNamespace()
        def cleanup(*args):
            self.events.append('original-bound-child-cleanup')
            return {'clear':True,'errors':[],'scope':'synthetic original guard stub'}
        self.guard.cleanup=cleanup
        return child,controller
    def test_malformed_owner_still_runs_bound_child_cleanup(self):
        destination=self.destination('bad-owner');(destination/'owner.json').write_text('{bad')
        child,controller=self.cleanup_setup(destination)
        result=devices.cleanup_owned(self.recipe,'iphone','store',child,'synthetic-child',{},destination,controller,{'synthetic':'source'})
        self.assertIn('original-bound-child-cleanup',self.events);self.assertFalse(result['clear'])
        self.assertIn('owner receipt:',result['errors'][0])
    def test_missing_owner_actual_journal_allows_only_bound_identity_cleanup(self):
        destination=self.destination('missing-owner');child,controller=self.cleanup_setup(destination)
        self.write_json(destination/'admission.json',{'controller':controller,'worker':{'pid':7,'pid_started':'synthetic-child'},
            'platform':'iphone','destination':str(destination.resolve()),'phase':'boot-admitted','device':self.actual})
        result=devices.cleanup_owned(self.recipe,'iphone','store',child,'synthetic-child',{},destination,controller,{'synthetic':'source'})
        self.assertEqual(self.guard.PHONE,self.actual['udid']);self.assertIn('original-bound-child-cleanup',self.events)
        self.assertFalse(result['clear']);self.assertIn('owner receipt missing',result['errors'][0])
    def test_foreign_journal_never_changes_device_policy_or_skips_child_cleanup(self):
        destination=self.destination('foreign-journal');child,controller=self.cleanup_setup(destination)
        self.write_json(destination/'admission.json',{'controller':{'pid':99},'platform':'iphone','device':self.actual})
        result=devices.cleanup_owned(self.recipe,'iphone','store',child,'synthetic-child',{},destination,controller,{'synthetic':'source'})
        self.assertEqual(self.guard.PHONE,devices.PHONE);self.assertIn('original-bound-child-cleanup',self.events)
        self.assertFalse(result['clear']);self.assertTrue(any('admission identity:' in e for e in result['errors']))

if __name__=='__main__':unittest.main(verbosity=2)
