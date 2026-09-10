#!/usr/bin/env python3
"""Read a completed demonstration's real saved file; no app control."""
from pathlib import Path
import argparse
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("run", type=Path)
args = parser.parse_args()
receipt = json.loads((args.run / "input.json").read_text())
source = (ROOT / "docs" / "demo" / "写作样例.md").read_bytes()
assert hashlib.sha256(source).hexdigest() == receipt["source_sha256"], "Demo source changed since preparation"
actual = (args.run / receipt["document"]).read_text()
change = receipt["replacement"]
expected = source.decode().replace(change["before"], change["after"], 1)
assert actual == expected, "Saved Markdown differs from the one intended edit; inspect it before publishing"
print("PASS: the real Markdown contains the intended edit and preserves every other character.")
