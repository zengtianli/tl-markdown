#!/bin/bash
set -euo pipefail
ACCEPT_NAME=privacy
source "$(dirname "$0")/_common.sh"
trap 'rm -rf "$ACCEPT_WORK"' EXIT
accept_compile_store Tests/PrivacyAcceptance.swift
"$ACCEPT_WORK/check" "$ACCEPT_WORK"
bash "$ACCEPT_ROOT/scripts/accept/cli.sh" privacy
accept_detail 'Runtime privacy checks against production SessionDisk/DocumentIO/NoteIndex/RichEditorBridge: private session permissions and state separation; synthetic SQLite bytes and metadata unchanged by search; invalid image destinations rejected without outside writes; nonpersistent WebKit data store; remote programmatic navigation cancelled; mdasset serves approved image bytes but refuses non-image content and unknown document identities. No real notes, external requests, input synthesis, or packet capture; explicit external-link opening and full process network behavior are outside this check.'
