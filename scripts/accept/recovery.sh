#!/bin/bash
set -euo pipefail
ACCEPT_NAME=recovery
source "$(dirname "$0")/_common.sh"
accept_compile_store Tests/RecoveryAcceptance.swift
"$ACCEPT_WORK/check" "$ACCEPT_WORK"
accept_detail "真实 EditorStore/DocumentIO：外部冲突阻止自动保存、重新载入保留本地副本、会话重建恢复草稿、关闭草稿恢复、只读文件保存失败、损坏会话保留及持久化失败提示；无窗口。关闭草稿恢复使用预存会话，不覆盖人工关闭确认对话框。"
