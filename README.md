# TL Markdown

本地 Markdown 阅读与编辑工具。原生 SwiftUI 窗口，CodeMirror 6 编辑组件。

## 使用

- ⌘O 打开文件，⌘N 新建，⌘S 保存，⌘⇧S 另存为。
- 默认即时渲染。点击正文块编辑其 Markdown，切换到其他块后恢复排版；工具栏可切源码。
- ⌘F 搜索替换，⌘B 加粗，⌘I 斜体，⌘K 插入链接。
- 命名文件自动保存；未命名内容存为本地恢复草稿。
- 左侧最近文件可固定、重新定位或移除；标题大纲可跳转。
- 图片可拖入、粘贴或从菜单插入，默认保存至文档旁 `assets/`。

## 构建

```sh
cd /Users/tianli/Apps/mac/tl-markdown/Editor
npm ci
cd /Users/tianli/Apps/mac/tl-markdown
bash build.sh --install
```

运行时无需 Node、Python 或联网。JS/CSS/字体全部打包。构建复用总部 Xcode 选择器、图标工厂和 CodingKey 检查；未从其他 App 导入代码。

验证：`bash scripts/test.sh`（本机 Xcode、Node 与 Chrome）。安装包位于 `/Applications/TL Markdown.app`，不会替换现有 Markdown 默认打开方式。

## 数据

原文是本地 UTF-8 `.md`。历史、设置与恢复草稿位于 `~/Library/Application Support/TLMarkdown/session.json`（仅当前用户可读写）。删除最近记录不会删除原文。外部修改冲突时停止自动保存，重新载入会保留当前修改为独立草稿。

## 编辑组件依赖

CodeMirror / Lezer、markdown-it 与插件、DOMPurify、highlight.js、KaTeX、Mermaid。版本见 `Editor/package-lock.json`。许可随构建产物分发。

## 需求与验证

范围来源：`/Users/tianli/Apps/handoffs/md-editor-requirements.md`。验收证据在 `handoffs/verification.md`；性能目标须以实测为准。
