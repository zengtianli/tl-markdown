#!/bin/bash
set -euo pipefail
STORE="$(cd "$(dirname "$0")" && pwd)"
exec "${PYTHON:-$HOME/Dev/.venv/bin/python}" "$STORE/check.py" "$@"
