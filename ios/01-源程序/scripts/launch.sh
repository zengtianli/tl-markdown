#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
platform="${1:?usage: Chapter launch wrapper requires iphone|ipad|vision}"
shift
case "$platform" in iphone|ipad|vision) ;; *) exit 2 ;; esac
test "${SOP_PLATFORM:-}" = "$platform"
: "${SOP_PLATFORM_LAUNCH:?run through Chapter accept so its original-input fingerprint and receipt are supplied}"
# No private fixture server or new device tools: same builtin serial lane and demo argument.
exec python3 "$SOP_PLATFORM_LAUNCH" "$@"
