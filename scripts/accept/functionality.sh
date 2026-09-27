#!/bin/bash
set -euo pipefail
ACCEPT_NAME=functionality
source "$(dirname "$0")/_common.sh"
trap 'rm -rf "$ACCEPT_WORK"' EXIT
accept_compile_store Tests/FunctionalityAcceptance.swift
"$ACCEPT_WORK/check" "$ACCEPT_WORK"
accept_detail 'Production EditorStore/DocumentIO/NoteSearchModel: Unicode and spaced .md/.markdown files; exact UTF-8/BOM/CRLF preservation; timed autosave; background-tab save isolation; duplicate open and tab selection; session/recent restoration; real synthetic FTS5 and short-query search; result-open production action. No GUI input or real note index used; renderer/caret behavior belongs to native_ui.'
