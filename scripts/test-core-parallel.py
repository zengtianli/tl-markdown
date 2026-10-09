#!/usr/bin/env python3
"""Run the existing test.sh core blocks concurrently, without copying their tests.

The original shell script remains the suite definition. Reject an unexpected
layout rather than silently omitting a block. Outputs/data directories in its
eight independent blocks are distinct; no windows, devices or ports are used.
"""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import hashlib
import os
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def blocks(text):
    prefix, rest = text.split('if [ "${1:-}" = "--main-editor" ]; then', 1)
    core = rest.split('\nfi\n', 1)[1].split('if [ "${1:-}" = "--core-only" ]; then', 1)[0]
    markers = [
        ('document_io', 'xcrun swiftc "${ENGINES[@]}" Sources/Models.swift Tests/DocumentIOTests.swift'),
        ('note_search', 'xcrun swiftc -parse-as-library "${ENGINES[@]}" Sources/Models.swift Tests/NoteSearchTests.swift'),
        ('store', 'xcrun swiftc -parse-as-library "${ENGINES[@]}" Sources/Models.swift Sources/ViewModel.swift Sources/BackendClient.swift Tests/StoreTests.swift'),
        ('watcher', 'xcrun swiftc -parse-as-library "${ENGINES[@]}" Sources/Models.swift Sources/ViewModel.swift Sources/BackendClient.swift Tests/WatcherTests.swift'),
        ('structure', '(cd Editor && node --test structure-tests.mjs)'),
        ('engines', 'for suite in IndexEngine GraphEngine; do'),
        ('cli', '# The shipped command line (the agent\'s surface):'),
    ]
    positions = []
    for name, marker in markers:
        if core.count(marker) != 1:
            raise ValueError(f"test.sh layout changed: {name}; update the block adapter")
        positions.append(core.index(marker))
    if positions != sorted(positions) or core[:positions[0]].strip():
        raise ValueError('test.sh has unrecognised core setup or block ordering')
    result = []
    for i, (name, marker) in enumerate(markers):
        body = core[positions[i]:positions[i + 1] if i + 1 < len(positions) else len(core)]
        if name == 'engines':
            for suite in ('IndexEngine', 'GraphEngine'):
                result.append((suite, body.replace(marker, f'for suite in {suite}; do', 1)))
        else:
            result.append((name, body))
    # The prefix resolves DIR from $0; bash -c's command_name points to the
    # original script, keeping its Xcode selection and production paths intact.
    return prefix, result


def main():
    if sys.argv[1:]:
        raise SystemExit('Usage: python3 scripts/test-core-parallel.py')
    source = ROOT / 'scripts/test.sh'
    original = source.read_bytes()
    prefix, suites = blocks(original.decode())
    out = ROOT / 'build/core-parallel'
    out.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    workers = min(os.cpu_count() or 1, len(suites))
    print(f'Core suite: {len(suites)} blocks, {workers} workers; test.sh SHA256 {hashlib.sha256(original).hexdigest()}', flush=True)

    def run(entry):
        name, body = entry
        begin = time.monotonic()
        log = out / f'{name}.log'
        with log.open('w') as stream:
            command = prefix + '\n' + body
            proc = subprocess.run(['/bin/bash', '-c', command, str(source)], cwd=ROOT,
                                  stdout=stream, stderr=subprocess.STDOUT, timeout=600)
        return name, proc.returncode, time.monotonic() - begin, log

    failed = False
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(run, suite): suite[0] for suite in suites}
        for future in as_completed(futures):
            name = futures[future]
            try:
                name, code, duration, log = future.result()
            except Exception as exc:
                failed = True
                print(f'FAIL {name}: {exc}', flush=True)
                continue
            failed |= code != 0
            print(f'{"PASS" if code == 0 else "FAIL"} {name}: exit {code}, {duration:.1f}s, {log.relative_to(ROOT)}', flush=True)
            if code:
                print(log.read_text()[-4000:], flush=True)
    if source.read_bytes() != original:
        failed = True
        print('FAIL test.sh changed during this run', flush=True)
    print(f'Core suite {"failed" if failed else "passed"} in {time.monotonic() - started:.1f}s; no windows, clipboard or browser tests run.', flush=True)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
