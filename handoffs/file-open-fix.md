# Folio 外部文件打开修复

旧安装版本实测：`open -a /Applications/Folio.app /Users/tianli/Apps/mac/tl-markdown/README.md` 返回成功，但窗口没有 README 标签、正文仍为原文件。

将 AppDelegate 的 legacy `application(_:openFiles:)` 换成 `application(_:open:)` URL 数组回调，保留 store 初始化前的 pending 队列。文件读取、去重和报错仍走 EditorStore.open。

Release 构建实测：冷启动打开 README.md 成功；运行中一次传入 README_EN.md 和 handoffs/english-name-refresh.md，两份都出现标签，后者正文可见。验证使用 LaunchServices 的 open -a 和 CUA 窗口回读，不以命令退出码代替打开成功。

构建复用总部 xcode_env.sh 与 check_codingkeys.py。系统 Markdown 默认应用查得仍为 Typora；本修复不修改用户默认应用偏好。
