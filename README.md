# Folio

[English](README_EN.md)

本地 Markdown 阅读与编辑工具。默认使用 SwiftUI 窗口 + AppKit NSTextView 原生编辑器，日常读写不创建 WebKit 进程。优先低内存和输入响应；Swift 管理文件、保存与恢复记录。

## 使用

- ⌘O 打开文件，⌘N 新建，⌘S 保存，⌘⇧S 另存为。
- 默认原生属性排版：标题、强调、代码、引用与链接；当前行显示 Markdown 标记，其余行隐藏部分标记。工具栏可切完整源码。
- ⌘F 搜索替换，⌘B 加粗，⌘I 斜体，⌘K 插入链接。
- 命名文件自动保存；未命名内容存为本地恢复草稿。
- 左侧最近文件可固定、重新定位或移除；标题大纲可跳转。
- 图片可拖入、粘贴或从菜单插入，默认保存至文档旁 `assets/`。
- 本地独立图片段落使用 ImageIO 缩略图原生显示。表格在主编辑区为等宽 Markdown，复杂嵌套语法不保证 Typora 级呈现。
- ⌘⇧P / 工具栏「完整预览」手动打开只读快照，显示网格表格、公式、Mermaid、远程／行内图片和脚注。仅此窗口使用本地 WebKit 组件；关闭解除引用，辅助进程由系统回收，GPU 服务可能延迟退出。预览不会随主文档自动更新，重新打开取得最新快照。

## 构建

```sh
cd /Users/tianli/Apps/mac/folio/Editor
npm ci
cd /Users/tianli/Apps/mac/folio
bash build.sh --install
```

运行时无需 Node、Python 或服务器。可选预览的 JS/CSS/字体全部打包。构建复用总部 Xcode 选择器、图标工厂和 CodingKey 检查；未从其他 App 导入代码。

验证：`bash scripts/test.sh`（本机 Xcode、Node 与 Chrome）。`build.sh` 还会从系统发起文件打开，核对隔离会话的实际文档内容；失败会阻止安装。安装包位于 `/Applications/Folio.app`，保留现有 Markdown 默认打开方式。

## 数据

原文是本地 UTF-8 `.md`。历史、设置与恢复草稿位于 `~/Library/Application Support/TLMarkdown/session.json`（仅当前用户可读写）。删除最近记录不会删除原文。外部修改冲突时停止自动保存，重新载入会保留当前修改为独立草稿。

## 可选预览依赖

CodeMirror / Lezer、markdown-it 与插件、DOMPurify、highlight.js、KaTeX、Mermaid。版本见 `Editor/package-lock.json`。许可随构建产物分发。

默认编辑区仅使用系统 AppKit、SwiftUI 与 ImageIO，没有第三方编辑器依赖。`Tests/NativeEditorTests.swift` 测试真实原生类；`Editor/tests.mjs` 只证明可选预览组件能力，不能混称原生测试。

## 需求与验证

范围来源：`/Users/tianli/Apps/handoffs/md-editor-requirements.md`。原生化、内存与性能证据见 `/Users/tianli/Apps/handoffs/md-editor-native-performance.md`。`handoffs/verification.md` 为最初 WebKit 版本历史验收；不代表当前原生功能范围。
