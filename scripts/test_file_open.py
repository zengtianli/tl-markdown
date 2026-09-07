#!/usr/bin/env python3
"""Exercise the signed app through LaunchServices, using disposable session state.

No direct EditorStore calls or diagnostic open bypass: the observed session is
written by the production file-open path. Run against a non-installed build.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import time
import uuid


def pids(executable):
    rows = subprocess.check_output(["/bin/ps", "-axo", "pid=,comm="], text=True)
    return {int(pid) for row in rows.splitlines() if row.strip()
            for pid, command in [row.strip().split(None, 1)] if command == str(executable)}


def wait_for(predicate, message, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(0.1)
    raise AssertionError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    app = args.app.resolve()
    if app.is_relative_to(Path("/Applications")):
        parser.error("Use a build product, not the user's installed application")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    if pids(executable):
        parser.error("This build is already running; will not reuse or stop an existing session")
    run = Path(__file__).resolve().parents[1] / "build/file-open-tests" / uuid.uuid4().hex
    run.mkdir(parents=True)
    fixtures = [(run / "冷启动 中文 空格.md", "# Cold launch\n独立文件内容 A\n"),
                (run / "运行中.markdown", "# Warm launch\n独立文件内容 B\n"),
                (run / "第二份 md.md", "# Multiple files\n独立文件内容 C\n")]
    for path, content in fixtures:
        path.write_text(content)
    session = run / "state/session.json"
    owned = set()

    def snapshot_matches(expected, active=None):
        if not session.exists():
            return False
        state = json.loads(session.read_text())
        documents = state.get("documents", [])
        expected_paths = {str(path) for path, _ in expected}
        if {doc.get("path") for doc in documents} != expected_paths or len(documents) != len(expected):
            return False
        for path, content in expected:
            if not any(doc.get("path") == str(path) and doc.get("text") == content for doc in documents):
                return False
        selected = next((doc for doc in documents if doc.get("id") == state.get("activeID")), {})
        return selected.get("path") in ({str(active)} if active else expected_paths)

    try:
        subprocess.run(["/usr/bin/open", "-n", "-g", "-a", str(app),
                        "--env", f"TL_MARKDOWN_STATE_DIR={session.parent}", str(fixtures[0][0])], check=True)
        owned = wait_for(lambda: pids(executable), "LaunchServices did not launch the tested executable")
        assert len(owned) == 1, f"Unexpected process count: {owned}"
        wait_for(lambda: snapshot_matches(fixtures[:1]), "Cold open returned but target document was not loaded")
        print("PASS cold LaunchServices open: Unicode/spaces .md", flush=True)
        subprocess.run(["/usr/bin/open", "-g", "-a", str(app), *[str(p) for p, _ in fixtures[1:]]], check=True)
        wait_for(lambda: snapshot_matches(fixtures), "Warm multi-file open did not load both documents")
        print("PASS warm LaunchServices open: .markdown and multiple files", flush=True)
        subprocess.run(["/usr/bin/open", "-g", "-a", str(app), str(fixtures[0][0])], check=True)
        wait_for(lambda: snapshot_matches(fixtures, fixtures[0][0]), "Reopening did not select the existing document")
        print("PASS reopen selects existing tab without duplicates", flush=True)
        assert all(path.read_text() == content for path, content in fixtures), "Opening changed fixture bytes"
        print(f"PASS source bytes unchanged; evidence: {session}", flush=True)
    finally:
        # Only this test's process, with isolated state. Never pkill the app family.
        for pid in owned & pids(executable):
            os.kill(pid, signal.SIGTERM)
        if owned:
            wait_for(lambda: not (owned & pids(executable)), "Test process did not exit", timeout=5)


if __name__ == "__main__":
    main()
