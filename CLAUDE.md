# CLAUDE.md — Folio

SwiftUI macOS app（脚手架生成自 macapp_scaffold），全 Swift，无外部 Python 后端。产品范围与实际架构先读本项目
`README.md` 和 `project.yaml`；上级 `~/Apps/CLAUDE.md` 是产品工作区约定。

## 命令行（agent 入口）

界面给人用，`folio` 给程序和 agent 用，共用同一业务层：`Sources/IndexEngine.swift`（索引、检索 `FolioIndexEngine.find`、
库位置 `resolveDatabase`、索引文件夹增删）、`Sources/GraphEngine.swift`（目录图谱）、`Sources/Models.swift`（会话记录
`SessionDisk`、文档读写 `DocumentIO.open/save`、插图 `DocumentIO.storeImage`；大纲 `MarkdownOutline` 在 GraphEngine.swift）。入口 `CLI/main.swift`，由 `scripts/build-cli.sh` 与上述三文件、`Sources/Shared` 四个生命周期文件和 `Sources/Lifecycle.swift` 一起编进
`Folio.app/Contents/Resources/bin/folio`（签名 `cyou.tianli.TLMarkdown.cli`，≤2 MB），`scripts/install-cli.py` 链接
`~/.local/bin/folio`。新增界面能力时同步补命令：读命令只读、支持 `--json`（`{ok: …}`）；写命令复用界面的校验；
退出码 0/1/2 = 成功/失败/用法错误。`session.json` 同一时刻只有一个写入者：窗口运行期间持有状态目录里的 `session.lock`，`folio settings set` / `folio recent …` 这时把修改放进 `requests/` 交给窗口（`EditorStore.apply`，与设置面板共用 `SessionEdits`，在 GraphEngine.swift 末尾），窗口没开时命令自己拿锁经 `SessionDisk` 改；其余命令对它只读。新增会改会话的命令走同一条通道，不直接写文件：`folio tabs close|restore|reload` 的规则在 `SessionTabs`（GraphEngine.swift 末尾，窗口的按钮也调它）。「配置与更新…」窗口里的各项是共用层 `Sources/Shared/AppLifecycleCLI.swift`（总部 swift-shared 的逐字节副本，不在这里改）：产品名、更新源、可迁移的键、隔离与导入前的核对只写在 `Sources/Lifecycle.swift` 一处，窗口、`folio config status|export|import|sync`、`folio update check|install` 都取它；`update install --yes`（窗口的「升级到新版…」）不改 session.json、不走窗口通道，隔离运行读隔离目录里的测试发行记录、只替换隔离目录里的 App（`FolioLifecycle.replacementProblem`），真替换的用例在 `cli_cases.py` 的 `upgrade_cases`（一次性的假 App，不碰装机版）；共用层会自己写 session.json，所以 `config import` 和真正拨开关的 `config sync` 在窗口开着时整条交给窗口执行（`SessionEdit.lifecycle` → `EditorStore.answerRequests`，执行后窗口立刻重读设置并存盘），没开时命令拿会话锁自己执行，App 里因此不接 `AppLifecycleCLI.follow`；不带子命令的 `folio config` 仍是索引配置。带窗口的回写自检是 `bash scripts/accept/lifecycle.sh`（`--lifecycle-self-test`，离屏、隔离、不构建）。命令清单、JSON 结构与
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
./build.sh --build-only   # 只构建（adhoc 试构建，留在 build/，不运行、不安装），并出 build/trial/TLMarkdown-<版本>-<构建>-trial.zip
./build.sh                # = --verify：构建 + 隔离的编辑器与文件打开测试，不安装
./build.sh --install      # 正式发行等级：Developer ID 签名 → 测试 → 公证 → 装订 → 出 ZIP → 装 /Applications
FOLIO_PREBUILT=<trial.zip> ./build.sh --install   # 不重新编译，接手另一台 Mac 的 --build-only 产物，只做签名之后的步骤
python3 scripts/verify-install.py                      # 同上，另写 Chapter 装机回执（源码没变就跳过）
python3 scripts/release_grade.py install <Folio-…zip>  # 另一台 Mac 装同一份包
python3 scripts/release_grade.py check /Applications/Folio.app   # 只读：这份 App 是不是发行等级
```

## 装机与分发只有一个等级

Folio 是给所有人用的产品，装进 `/Applications` 的和放出去下载的是同一份包，任何一台 Mac 拿到都能直接打开。等级写在
`scripts/release_grade.py` 一处，`build.sh --install`、`scripts/package-release.py` 和第二台 Mac 的安装都过它：

- 包内每个 Mach-O（主程序和 `Resources/bin/folio`）都是 `Developer ID Application: tianli Zeng (B9LJH93LA4)`，带 hardened runtime 和安全时间戳；
- 已提交 Apple 公证并通过，票据已装订；`spctl --assess --type execute --verbose=2` 读到 `source=Notarized Developer ID`；
- 包内没有带设备清单的描述文件。Folio 现在不带描述文件；以后要加 iCloud 容器、钥匙串组这类能力，用 Developer ID 的直接分发描述文件（没有 `ProvisionedDevices`），不用 Apple Development 签名，也不把“把某台设备加进清单”当修法。
- adhoc 和 Apple Development 签名只算试构建：`--build-only` / `--verify` 的产物留在 `build/`，安装器和打包脚本都拒收。

编译不需要证书，默认分两段：在 Mini 上 `./build.sh --build-only`（多核编译），把 `build/trial/` 里的 ZIP 送到有证书的 Mac（`build/` 不随两机同步），那边用 `FOLIO_PREBUILT=<那个 ZIP>` 跑 `--install` 或 `scripts/verify-install.py`。接手时 `package-release.py --adopt` 核对提交、源码指纹和构建号，不是同一份提交和源码就拒绝；有证书的 Mac 也可以不带 `FOLIO_PREBUILT` 自己从头编译。

`--install` 的顺序：命令行与 App 用 Developer ID 签名 → 对签好的包跑编辑器与文件打开测试 → `~/Apps/mackit/scripts/notarize.py` 提交公证并等结果（凭据沿总部 asc 入口，不落在本仓）→ 装订 → `package-release.py` 出 `build/release/Folio-<版本>-<构建>-arm64.zip` 与 `release.json` → `release_grade.py install` 把这份 ZIP 装进 `/Applications`（旧版移进废纸篓）并接上 `~/.local/bin/folio`。公证是把包交给 Apple 的公证服务，不等于对外发布；官网、GitHub Release 仍是另外的发布动作。

- 证书只在有 Developer ID 私钥的 Mac（现在是 Air）的登录钥匙串里。纯 SSH 会话里 `codesign` 报 `errSecInternalComponent`，`--install` 要在那台 Mac 的登录会话里跑（终端，或登录会话里的一次性 LaunchAgent）；没有证书的 Mac 上 `--install` 在构建前就退出，并提示改装现成的 ZIP。
- 两台 Mac 装同一份 ZIP，不各自构建：主程序 SHA-256 要相同。
- 构建号是提交数。同一个版本加构建号只对应一份内容：已装的就是这个构建号时 `--install` 拒绝重出，先提交再装。
- 官网页面的“未公证 / 首次打开”说明还是 adhoc 时期的文案：`scripts/build-site.py` 读到 `release.json` 里签名状态已变会停下，下次发布官网前先改 `site/` 的安装说明，再改那条断言。

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
