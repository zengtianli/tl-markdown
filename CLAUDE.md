# CLAUDE.md — Folio

SwiftUI macOS app（脚手架生成自 macapp_scaffold），全 Swift，无外部 Python 后端。产品范围与实际架构先读本项目
`README.md` 和 `project.yaml`；上级 `~/Apps/CLAUDE.md` 是产品工作区约定。

## 命令行（agent 入口）

界面给人用，`folio` 给程序和 agent 用，共用同一业务层：`Sources/IndexEngine.swift`（索引、检索 `FolioIndexEngine.find`、
库位置 `resolveDatabase`、索引文件夹增删）、`Sources/GraphEngine.swift`（目录图谱）、`Sources/Models.swift`（会话记录
`SessionDisk`、文档读写 `DocumentIO.open/save`、插图 `DocumentIO.storeImage`；大纲 `MarkdownOutline` 在 GraphEngine.swift）。入口 `CLI/main.swift`，由 `scripts/build-cli.sh` 与上述三文件一起编进
`Folio.app/Contents/Resources/bin/folio`（签名 `cyou.tianli.TLMarkdown.cli`，≤2 MB），`scripts/install-cli.py` 链接
`~/.local/bin/folio`。新增界面能力时同步补命令：读命令只读、支持 `--json`（`{ok: …}`）；写命令复用界面的校验；
退出码 0/1/2 = 成功/失败/用法错误。`session.json` 只由运行中的 App 写，命令行对它只读。命令清单、JSON 结构与
仅界面的手势见 `docs/cli.md`；界面功能逐项对照登记在 `project.yaml` 的 `sop.agent_cli`（手机端在 ios 组件），增删界面功能或命令时同步改；真二进制回归在 `scripts/accept/cli_cases.py`（`scripts/test.sh --core-only` 也会跑）。

新需求先读 playbook：`~/Dev/tools/configs/playbooks/native-console-app.md`（决策树 + 全部坑单）。

## 构建

产品主页在 `site/`；版本和安装包从 `scripts/package-release.py` 的实际产物派生，站群仅消费 `build/site/site-manifest.json` 白名单。完整媒体契约在 `docs/demo/录制说明.md`。`--preview` 输出不可发布。源码已按9月12日决定公开，许可沿用随仓 `LICENSE`；网站继续只消费白名单，用户状态、录制原片与临时验证资料不随站点发布。

`build.sh --build-only` 不运行 GUI 与文件打开测试，不安装。`scripts/test.sh --core-only` 运行无窗口的生产文件与 store 回归。当前 HARNESS 的输入隔离规则优先，不能为了执行旧测试脚本而抢占用户焦点或剪贴板。最终 GUI 由隔离 Computer Use 验证，必须如实记录其覆盖。

`FOLIO_BACKGROUND=1` 只有与独立 `TL_MARKDOWN_STATE_DIR` 同时提供才生效：抑制默认 SwiftUI Window，AppDelegate 用不能成为 key/main 的 nonactivating NSPanel 挂载同一 ContentView。普通启动不改变。录制副本由 `prepare-demo.py` 复制、改独立 bundle ID、删除文件关联、嵌入 LSEnvironment 并重签；不以桌面全局输入驱动录制。

隔离模式的 `applicationShouldTerminateAfterLastWindowClosed` 必须返回 false：定时窗口录屏收尾会触发 AppKit 最后窗口检查，SwiftUI 默认会退出仅剩手工 NSPanel 的进程。此路径已由独立 `state/termination.json` 调用栈确认；automatic termination opt-out 不能替代。普通单个 Window 仍维持关窗退出，显式 Quit 仍 flush。诊断文件只在隔离状态目录写事件来源与调用栈，不写文档。

项目目录为 `/Users/tianli/Apps/folio`。Bundle ID、内部构建 target 与用户数据目录保持兼容，避免丢失默认文件关联和已有会话。

```bash
cd ~/Apps/folio
./build.sh          # 构建 + 装 /Applications（Xcode 自动挑，见下）
```

**别自己写 `DEVELOPER_DIR=/Applications/Xcode.app/...`。** 本机 `xcode-select` 指向
CommandLineTools（`xcodebuild` 在那儿直接报 requires Xcode），而盘上可能同时躺着好几个
Xcode、其中一些已被当前 macOS 判为不支持。该用哪个由总部 SSOT 现算：

```bash
source /Users/tianli/Dev/tools/dev/lib/tools/macapp/xcode_env.sh && xcode_env_use macosx
# build.sh 里已经内置这一行；想单独看它挑了谁：
python3 /Users/tianli/Dev/tools/dev/lib/tools/macapp/xcode_env.py list
```

## 硬约束（与范本 ssot-console 一致）

- `build.sh` 对签名后的真实 .app 自动运行 `scripts/test_file_open.py`：通过 LaunchServices 验证冷启动、运行中多文件、Unicode/空格、两种扩展名和重复打开；读取隔离会话中真实文档内容。失败不安装。发布时再通过 CUA 核对安装版窗口内容；组件测试或 open 返回 0 不能替代。

- bundle id `cyou.tianli.TLMarkdown`；部署目标见 pbxproj `MACOSX_DEPLOYMENT_TARGET`。
- 核心读写用生产代码测试，不维持占位后端；CLI 与界面共用 Sources 里的实现，不另写第二套。
- 新增源文件要动 pbxproj 4 处（PBXBuildFile / PBXFileReference / Sources group / Sources build
  phase），CLI 需要时还要加进 `scripts/build-cli.sh`—— 小增量优先 append 进 Sources 现有 7 个文件，MARK 分节。
- UI 坑单（语义色零硬编码 / 禁 `fixedSize(h:false,v:true)` / detail 根 minWidth 600 / 并发 drain /
  GUI PATH 注入）已以代码+注释固化在 Sources/ 里，删注释前先读 playbook。
