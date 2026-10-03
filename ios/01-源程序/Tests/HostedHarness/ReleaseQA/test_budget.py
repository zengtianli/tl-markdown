#!/usr/bin/env python3
"""Only two requested pure late-boundary counterexamples; no native gates or runtime."""
import json
from budget import Attempt

class Clock:
    now = 0.0
    def __call__(self): return self.now

def case(name, child_finish, cleanup_finish):
    clock = Clock(); attempt = Attempt(600, clock=clock)
    attempt.require('existing child start')
    clock.now = child_finish
    record = {'status':'candidate', 'exit_code':0, 'child_finish_seconds':child_finish}
    blocked = False
    if clock.now >= 600:
        try: attempt.require('next operation')
        except TimeoutError: blocked = True
        assert blocked
    # Existing child completed naturally. Successful cleanup and source reads can cross the bound.
    clock.now = cleanup_finish
    record['own_cleanup_complete'] = record['file_nb_released'] = record['final_inputs_stable'] = True
    errors = []; attempt.finalize(record, errors, 'candidate', 'passed')
    assert record['status'] == 'failed-or-deferred' and record['total_budget']['over_budget'] and errors
    return {'case':name, 'next_operation_blocked_at_boundary':blocked, 'errors':errors, 'result':record}

if __name__ == '__main__':
    print(json.dumps({'scope':'pure total budget only, no real timing/perf/gates/device', 'cases':[
        case('late exit0 natural boundary', 600.1, 600.2),
        case('exit0 in time, final cleanup/input crosses budget', 599.9, 600.1)]},indent=2))

