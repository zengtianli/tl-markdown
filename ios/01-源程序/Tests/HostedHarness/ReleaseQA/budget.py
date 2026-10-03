"""Folio total attempt budget: natural in-flight boundary, no new stage afterward."""
import math
import os
import time

class Attempt:
    def __init__(self, seconds=600, worker=False, clock=None):
        self.clock = clock or time.monotonic
        self.started = self.clock()
        self.seconds = float(seconds)
        if worker:
            self.started = float(os.environ['FOLIO_QA_STARTED_MONOTONIC'])
            if float(os.environ['FOLIO_QA_SLOT_SECONDS']) != self.seconds:
                raise RuntimeError('worker total budget differs from controller')
        if not math.isfinite(self.started) or not math.isfinite(self.seconds) or not 0 < self.seconds <= 600:
            raise RuntimeError('finite total attempt budget must be 0..600 seconds')

    def elapsed(self): return self.clock() - self.started
    def expired(self): return self.elapsed() >= self.seconds
    def require(self, stage):
        if self.expired():
            raise TimeoutError('total budget reached before next ' + stage + '; no next operation')
    def environment(self):
        return {'FOLIO_QA_STARTED_MONOTONIC':repr(self.started), 'FOLIO_QA_SLOT_SECONDS':repr(self.seconds)}
    def finalize(self, record, errors, candidate, passed):
        # Called only after own cleanup, Chapter file NB release, and final source/SDK binding read.
        elapsed = self.elapsed()
        record['total_budget'] = {'seconds':self.seconds, 'elapsed_seconds':elapsed,
                                  'includes':'initial input freeze, admission, child natural finish, own cleanup, file NB release, final inputs',
                                  'over_budget':elapsed >= self.seconds,
                                  'deadline_does_not_kill_existing_child':True}
        if elapsed >= self.seconds: errors.append('total attempt budget exceeded after cleanup/final inputs')
        record['status'] = passed if record['status'] == candidate and not errors else 'failed-or-deferred'

