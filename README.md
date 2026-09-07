# Folio

[English](README_EN.md)

本地 Markdown 阅读与编辑工具。SwiftUI 窗口内默认使用单栏即时渲染编辑区，Swift 管理文件、保存与恢复记录。完整渲染使用打包的 WebKit 组件，会创建辅助进程；不再沿用旧原生版的低内存测量值。

## 使用

- ⌘O 打开文件，⌘N 新建，⌘S 保存，⌘⇧S 另存为。
- 默认显示排版好的标题、表格、链接、图片、公式与图表。点击对应段落编辑 Markdown，移到其他段落后立即恢复排版；工具栏可切完整源码。
- ⌘F 搜索替换，⌘B 加粗，⌘I 斜体，⌘K 插入链接。
- 命名文件自动保存；未命名内容存为本地恢复草稿。
- 左侧最近文件可固定、重新定位或移除；标题大纲可跳转。
- 图片可拖入、粘贴或从菜单插入，默认保存至文档旁 `assets/`。
- 主编辑区直接显示网格表格和引用式链接；引用定义在渲染模式隐藏，在源码模式可编辑。
- ⌘⇧P / 工具栏「完整预览」可另开只读实时预览，适合对照阅读；日常编辑无需打开此窗口。

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

`Tests/NativeEditorTests.swift` 验证保留的原生编辑实现；`Editor/tests.mjs` 验证当前主编辑区使用的渲染和编辑组件。安装版还需通过真实窗口验证主编辑路径。

## 需求与验证

范围来源：`/Users/tianli/Apps/handoffs/md-editor-requirements.md`。原生化、内存与性能证据见 `/Users/tianli/Apps/handoffs/md-editor-native-performance.md`。`handoffs/verification.md` 为最初 WebKit 版本历史验收；不代表当前原生功能范围。
