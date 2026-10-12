# Folio Mac App Store 商店版 · 2026-10-12

## 进度

- 已完成：任务书与两份样板报告；商店工程、10 张图标、独立编辑器资源、xcodegen 和 spec_lint；共享生命周期逐字节校验通过；APP_STORE 条件隔开更新器/CLI，设置接 KVS/导入导出与文件夹书签。
- 已完成验证：两种条件 typecheck 退出 0；隔离的原 test.sh --core-only 全套退出 0；xcodebuild 成功、spec_lint、版本/资源检查通过；沙盒自检文档/配置/索引/图谱/相对图片写入全通过。
- 正在做：本轮已完成；源码/工程本地提交 `76327e15d395d5e168c7b5d9d137c3fa9b177510`，本报告作为单独交接提交。
- 下一步：本会话停止执行；归档上传和屏幕验收由主会话沿原入口接续。
- 卡点：没有编译或核心数据流程阻挡；真实面板授权、KVS 正式能力及正常 GUI 行为按本轮无干扰限制未测。截止 `2026-10-12 21:17:44 +08:00`（30 分钟）。

## 本轮边界与完成条件

只写本产品 `Sources/`（不改 `Sources/Shared/`）、`store/`、本报告和 `/private/tmp/mas-store/`。不改 iOS、Tests、build.sh、project.yaml、README、网站；保留他人改动、暂存和后台。共享资源为已安装 Xcode 工具链、构建负载与 LaunchServices；商店构建最多 `-jobs 4`，每次构建立即注销产物，不正常启动 App。

目标：同一源码通过 `APP_STORE` 生成无 CLI / 无更新器的沙盒商店版；保留下载版行为；建立文件/文件夹安全作用域授权、KVS 配置同步与可导入导出的迁移入口。通过原测试与两种条件的 typecheck、xcodegen / xcodebuild build / spec_lint；检查 Info.plist、权限和可执行文件；仅在可靠离屏入口可用时验证沙盒容器启动与读写。不能无干扰执行的 GUI/TCC 步骤明确未测。

本轮不归档、不上传、不装机、不上屏；最终报告记录实际命令、结果与接续条件。

## 验证过程记录

- `bash store/build-editor.sh`：`Editor resources bundled locally.`；在 store/Generated 的独立工作目录运行现有 Editor/build.mjs，使用原依赖，只生成商店资源，不改根 Resources。
- `bash store/check.sh`：`ok (version 1.2.1, 5 entitlements, fresh editor resources)`；`xcodegen`：生成 Folio.xcodeproj；`spec_lint.py /Users/tianli/Apps/folio/store`：1 target 规格干净。
- `vendor-lifecycle.py --target-source-dir Sources/Shared --platform mac --cli --check`：`Lifecycle sources match: Sources/Shared`。
- 原核心测试第一次放在 `/private/tmp`，原 DocumentIOTests 的“image lands beside the document”字符串路径断言遇到 Foundation `/private/tmp` → `/tmp` 规范化差异而失败。没有改生产读写行为或 Tests；改用 store/Generated/core-tests 隔离副本执行原测试，所有输出仍在允许的 store/ 内，原 test.sh 逐字节不变。
- 商店 target 为 macOS 14，原 `.defaultLaunchBehavior` 是 macOS 15 API。商店常规 Window 不使用该修饰器；下载版原修饰器保留。商店拒绝旧录制/UI 自测参数，提供在 SwiftUI 创建任何窗口前退出的 `--store-self-test`，只允许测试 bundle ID 的真实容器运行，避免 macOS 14 的普通窗口意外上屏。

## 改动与商店工程

- `Sources/IndexEngine.swift`：仅 APP_STORE 的 HOME 推导改取 `NSHomeDirectory()`，保证状态和索引进入容器，避免从 shell 继承的真实 HOME 指向本人下载版数据。
- `Sources/Models.swift`：追加 APP_STORE 专用 `FolioFileGrants`，安全作用域书签保存到容器 `file-grants.json`，恢复时使用 `.withoutUI`，持有作用域至进程结束；授权文件和授权目录分开判断。书签不加入导出/iCloud。文档缺授权及向相对目录写图时给出明确原因。
- `Sources/ViewModel.swift`：恢复会话前恢复书签；打开面板/Finder/拖入/另存为及索引/图谱目录选择保存授权；未授权最近文件保留待授权路径并提供“允许这个文件夹…”；产品自己的配置导出/导入只读写面板选择的文件，不创建其父目录。索引根未授权时停止并提示重新选择，不静默忽略。
- `Sources/ContentView.swift`：商店版的文件夹授权提示/按钮，设置中 KVS 开关与导出/导入；商店不显示任意路径输入的自定义数据库字段，索引固定在容器。下载版原 UI 不变。
- `Sources/Lifecycle.swift`：更新源、CLI 命令层和仅命令使用的导入拒绝器不进 APP_STORE；可迁移的原 5 个阅读键保持不变，导入仍验证必要字段与类型。
- `Sources/TLMarkdownApp.swift`：商店不显示“配置与更新 / 检查更新”，不安装共享更新窗口，只启动共享配置对象；不编译依赖嵌套 CLI 的生命周期自测；追加受测试 bundle ID 和真实 Sandbox 环境约束的 `--store-self-test`，在 SwiftUI 创建窗口前退出。常规商店 Window 支持 macOS 14，下载版保留 macOS 15 窗口抑制行为。
- `Sources/GraphEngine.swift`：仅商店生成的图谱刷新说明改成从 Folio 文件菜单重新生成；仅商店按授权完整路径直接 `open(...O_NOFOLLOW...)`，避免逐级读取无权限的祖先目录。扫描仍排除软链条目、最终文件仍拒软链、写入仍通过目录 fd 原子替换；不使用例外权限。
- `Sources/Shared/` 全部原样保留。商店 source 集排除 AppLifecycle / AppLifecycleUI / AppLifecycleCLI 三文件，仅编译共享 AppConfiguration（KVS）。没有 CLI 源码、二进制或软链资源。
- `store/project.yml`：唯一 macOS application target `Folio`，现有包名 `cyou.tianli.TLMarkdown`，可执行文件 `TLMarkdown`，显示名 Folio；macOS 14.0，arm64，Swift 5.0，版本 1.2.1、初始构建号 1，自动签名 / 团队 B9LJH93LA4 / Hardened Runtime，`APP_STORE APP_LIFECYCLE_KVS`。系统库 AppKit、SwiftUI、WebKit、UniformTypeIdentifiers、ImageIO、SQLite，均为原源码自动链接的系统依赖。
- `store/build-editor.sh`：净环境 + 绝对 node 路径，复用原 Editor/build.mjs 和既有依赖，在独立 store/Generated 工作目录生成 Editor 与第三方许可，不改变根 Resources。它是 Xcode pre-build phase；首次 xcodegen 前先运行一次，确保资源路径存在。
- `store/check.sh` / `check.py`：检查原发行版本、每个原 Info 键、APP_STORE/沙盒/无例外权限、图标和编辑器源码指纹；缺少或过期产物时失败并给准备入口。`verify-core.sh` 在 store/Generated 中对原源码/测试建立一次性副本，执行逐字节相同的原 test.sh --core-only，避免修改根 build/ 和 Tests。
- `store/Assets.xcassets`：10 张原正式图标的 16–1024 像素派生 PNG；逐张验证尺寸；Contents.json 的 mac / size / scale 齐全。`ExportOptions.plist` 与 Initials 样板逐字节相同。生成的 Info.plist、entitlements、xcodeproj 和 Generated 由 .gitignore 排除。

## 最终权限（审核用途）

| 权限 | 用途 |
|---|---|
| `com.apple.security.app-sandbox` | Mac App Store 沙盒要求，状态、索引、恢复草稿进入本 App 容器。 |
| `com.apple.security.files.user-selected.read-write` | 打开/另存文稿，用户选择索引或图谱文件夹，保存插图，以及配置导出/导入。 |
| `com.apple.security.files.bookmarks.app-scope` | 保存用户允许的文件/文件夹授权，继续上次阅读、最近文件、目录索引及相对图片跨启动使用。 |
| `com.apple.security.network.client` | 用户 Markdown 中的网络图片由 WebKit 访问其原地址；没有分析追踪或 App 自更新请求。 |
| `com.apple.developer.ubiquity-kvstore-identifier` | 默认关闭的“使用 iCloud 记住配置”，通过共享层的 KVS 同步原 5 项阅读设置。 |

没有 temporary-exception、Apple Events、完全磁盘访问或 Downloads 固定目录权限。

## 功能差异、同步与迁移

- 同一包名、免费商店版，与现有 Developer ID / GitHub 版共用生产编辑器、文档读写、检索和图谱源码；正常商店启动不自动弹文件夹授权，只有用户点击允许/选择时进入系统面板。
- 商店不带 `folio` CLI，也不提供自更新菜单/窗口/命令。更新由 App Store 提供。图谱仍生成离线 HTML，通过文件菜单重新生成，不提供 CLI 刷新脚本。
- 文档仅从打开面板、拖入、Finder 文档事件获取；文档同目录的图片、图谱和索引要求用户允许文件夹。文档本身的授权不冒充父目录授权；权限不足时显示允许入口，草稿仍保留。
- 任意自定义索引路径输入在商店隐藏，默认容器索引保留；用户可选择多个授权文件夹索引。
- 配置选 `APP_LIFECYCLE_KVS`：原 iCloud Drive 文件通道不适合沙盒，既有共享 KVS 已提供相同可迁移键合同；无需另造同步层。开关默认关闭，KVS 描述文件/跨设备送达没有在 ad-hoc 副本验证。
- 下载版配置在真实主目录 Application Support，商店不会扫描或自动导入它。迁移：在下载版“配置与更新…”导出 JSON，再在商店“设置…”导入阅读配置。只迁移字体、字号、正文宽度、恢复开关、图片目录名；文稿、会话、草稿、索引、书签授权各自留在本机，需重新选择文稿/文件夹。

## 最终验证命令与真实结果

执行机：Mac mini，原 xcode_env 选择 Xcode 27.0 / macOS SDK 27.0。没有设置手写 DEVELOPER_DIR、允许 provision 更新或建立签名身份。

1. `bash store/verify-core.sh`：原 `scripts/test.sh --core-only` 退出 0。最后为 `Graph engine checks passed (28)`、CLI `{"ok":true,"mode":"functionality","scope":"synthetic CLI and shared engine"}`、`Production I/O and store checks passed; no windows, clipboard or browser tests run.`。日志 `/private/tmp/mas-store/folio-core-tests.log`。包括原 I/O、检索、store、watcher、编辑器结构、索引、图谱与真 CLI 回归。
2. 下载版：`xcrun swiftc -swift-version 5 -typecheck -target arm64-apple-macos15.0 -sdk "$SDK" Sources/*.swift Sources/Shared/*.swift`，退出 0。商店：同命令改目标 14.0、`-D APP_STORE -D APP_LIFECYCLE_KVS`、共享文件只含 AppConfiguration.swift，退出 0；日志在 `folio-evidence/typecheck-download.log` / `typecheck-store.log`。保留原共享层 Sendable / 废弃 API 编译 warning，Swift 5 下不是错误。
3. `xcodegen`、`spec_lint.py /Users/tianli/Apps/folio/store`、`bash store/check.sh` 均通过。对临时规格把版本改成 0.0.0，check.py 退出 1，错误 `Store version differs from root Info.plist`；没有改实际版本。
4. 正式构建命令（前面 source 原 xcode_env.sh / scrub_env.sh）：
   ```sh
   scrub_env_run xcodebuild -project /Users/tianli/Apps/folio/store/Folio.xcodeproj -scheme Folio \
     -configuration Release -destination 'generic/platform=macOS' \
     -derivedDataPath /private/tmp/mas-store/folio-dd -jobs 4 CODE_SIGNING_ALLOWED=NO build
   ```
   退出 0，`** BUILD SUCCEEDED **`，日志 `/private/tmp/mas-store/folio-evidence/xcodebuild.log`。使用 EXIT trap 每次立即 `lsregister -u`，没有 archive / export / upload。
5. `PYTHONPATH=…/macapp/ios python -B` 只调 `asc_release.project_identity`：`{'scheme':'Folio','bundle_id':'cyou.tianli.TLMarkdown','marketing_version':'1.2.1'}`；未调用联网 main 或任何 ASC 写入。
6. 产物核验：原 Info 键缺失 `[]`；唯一原键值差异 LSMinimumSystemVersion `15.0 → 14.0`（任务书指定），文档类型及 UTI 全保留；新增分类 productivity 和 `ITSAppUsesNonExemptEncryption:false`。包内 executable 位文件和 Mach-O 都只有 `Contents/MacOS/TLMarkdown`，没有 CLI 或其软链。Editor / graph-view / 欢迎文档 / 第三方许可齐全。记录 `/private/tmp/mas-store/folio-evidence/artifact.json`。
7. 独立测试副本在 `/private/tmp/mas-store/folio-test/Folio.app`，改 ID 为 `test.tianli.folio.store`，测试 Info 添加 LSUIElement；以 `codesign --force --sign - --options runtime --entitlements …` 签名，深度验签退出 0。`codesign -d --entitlements :-` 显示 Sandbox、user-selected.read-write、bookmarks.app-scope、network.client 四项。测试副本唯一省略 KVS entitlement，因为它是需要正式描述文件的受限能力；正式 store/project.yml 保留该项，不放宽权限。
8. 只直接执行测试副本 `Contents/MacOS/TLMarkdown --store-self-test`，退出 0：`APP_SANDBOX_CONTAINER_ID=test.tianli.folio.store`；HOME / 状态目录真实位于 `~/Library/Containers/test.tianli.folio.store/Data/…`；`document_save_reopen / config_export_import / relative_image_write / graph_created / session_in_container / ungranted_path_rejected / editor_present / cli_absent` 全 true，`index_count:1`、`ok:true`。最终进程 2991，`window_count:0 / app_active:false / activation_policy:2`（prohibited），证明无窗口、未激活。JSON `/private/tmp/mas-store/folio-evidence/store-self-test.json`；stderr 为空。图片验证是插图字节与相对引用写入，未声称视觉解码成功。
9. 构建产物和测试副本逐一 `lsregister -u`；已注销构建包再次注销返回 `-10814`，未把该返回当成功证据。最终 `lsregister -dump` 落盘后读取，`/(private/)?tmp/mas-store/folio-` 命中 **0**，证据 `folio-evidence/launchservices-final.txt`；没有其他正在运行的本轮进程。未清理其他会话或旧版本的登记。

## 沙盒日志与未测范围

`/usr/bin/log show --last 5m --style compact --predicate 'eventMessage CONTAINS "Sandbox:"'` 保存为 `folio-evidence/sandbox-denies.log`。

- 首次测试进程 84311：`file-read-data /Users`。来自图谱 descriptor 从根逐级读父目录的实现；这不是文件夹授权问题。商店改直接访问已授权绝对路径后，最终进程 88837 图谱通过，不再有该文件读取拒绝。下载版反软链逐级 walk 保持原实现。
- 最终进程 88837：只有 `iokit-open-user-client AppleNVMeEANUC`。发生在启动早期，本产品没有直接 IOKit 调用；与 Sift 样板相同，推测为系统框架设备信息探测，核心自检通过，没有为它追加权限。
- 最后补齐窗口证据的进程 2991：`sandbox-final.log` 同样只出现上述 AppleNVMeEANUC 一条，文件读取/写入 deny 为 0；没有继续重跑有效业务验收。
- 另有 ScopedBookmarkAgent(1195) 对 core-tests/build 的拒绝，属于原核心测试期间的独立系统代理进程，非商店测试进程；核心 suite 最终全通过。未取调用栈，不把这几条推断为业务故障或“所有拒绝均能看到”。

未测：真实系统打开/保存面板、Finder 双击与拖入授权、用户私有文件夹书签跨启动与文件移动后的恢复、相对图片视觉呈现、商店设置页布局与常规 GUI 操作、macOS 14 真机运行、KVS 开关及跨设备同步、正式签名/描述文件/归档/上传/审核。原因分别是本轮禁止上屏与系统授权面板、无正式 KVS 描述文件、明确分工不归档上传；源码/typecheck/离屏数据证明不冒充这些验收。

## Review notes (English)

1. Launch Folio and choose **Open…** (⌘O), then select a UTF-8 `.md` or `.markdown` document. The bundled **Open Example Document** is also available without external file permission.
2. Edit a paragraph, press **Save** (⌘S), and reopen the same document to confirm the text. Use **Save As…** for a new document. The source toggle and outline are in the editor toolbar/sidebar.
3. For relative images or writing illustrations beside the document, click **Allow this Folder…** and select the containing folder. The grant is kept locally as a security-scoped bookmark.
4. In **Settings…**, add a folder under **Index Folders**, then choose **Update Index**. Use **Search All Notes** (⌘⇧F); choose **File → Generate Directory Graph…** for an offline graph of an allowed folder.
5. **Export Reading Configuration… / Import Reading Configuration…** transfer only reading settings. Optional iCloud settings sync is off by default. This App Store build has no bundled CLI or self-updater; updates come from the App Store.

## 现有真实截图（不是本轮商店实拍）

- `/Users/tianli/Apps/folio/perf/acceptance/native_ui-editor.png`
- `/Users/tianli/Apps/folio/perf/acceptance/native_ui-source.png`
- `/Users/tianli/Apps/folio/perf/acceptance/native_ui-settings.png`
- `/Users/tianli/Apps/folio/perf/acceptance/native_ui-index-empty.png`
- `/Users/tianli/Apps/folio/docs/demo/media/folio-editor.png`（更旧的演示首图）。

均为原下载版真实界面，主会话做商店截图时需说明版本和新设置区差异；本轮没有制作或上屏录制新截图。

## 主会话在本轮范围外的接续

- 在 App Store Connect 准备同包名的 macOS 记录、免费定价；在原 App ID 打开 KVS 能力并按现有上传入口自动签名。归档/上传由主会话执行，不从本报告推导本轮上传授权。
- 首次归档前 `bash store/build-editor.sh && bash store/check.sh`，然后原 `push-testflight.sh --platform macos /Users/tianli/Apps/folio/store`。该命令会外发，本轮未执行。归档中间产物和 archive 仍需按原脚本立即注销 LaunchServices。
- `project.yaml` 登记商店变体与 CLI 差异；build.sh 若要常态校验商店版本可接 `store/check.sh`；README/官网及商店描述补功能差异。未在本轮修改这些文件。
- `Tests/` 可为书签恢复/权限引导和商店配置导入增加生产函数回归；真实面板授权、书签重启恢复、KVS 配置同步及商店新设置布局沿产品验收处理，不通过例外权限或正常启动自动测试来绕过本轮隔离要求。
- 独立测试容器 `~/Library/Containers/test.tianli.folio.store` 留作验证证据，没有从 shell 删除容器来触发系统授权。其中仅本轮合成文稿/索引/设置，未触碰真实 `cyou.tianli.TLMarkdown` 容器或装机实例。

本轮产物在 `/private/tmp/mas-store/folio-dd` 与 `folio-test`（均已注销），工程在 `store/`；诊断证据在 `/private/tmp/mas-store/folio-evidence`，核心测试日志在 `/private/tmp/mas-store/folio-core-tests.log`。这些临时文件会随系统清理消失，复跑入口已列明。未归档、未上传、未装机、未打开普通商店窗口；他人差异与后台保持。

## 提交与完成状态

源码/工程提交：`76327e15d395d5e168c7b5d9d137c3fa9b177510`，`store: add sandboxed Folio Mac App Store build variant`。仅 7 个产品 Sources 文件和新 store 工程/脚本/图标，共 26 文件；未提交 Sources/Shared、iOS、perf、project.yaml 等其他会话差异，未推送。生成的 Info/entitlements/xcodeproj/Generated 均未入库，10 张 PNG 已强制纳入指定暂存。

本轮工程、编译、核心数据沙盒验证和交接已完成；正式商店签名、归档、上传、真实授权与界面/KVS 验收是主会话的后续分工，未冒充完成。Chapter 原 claims 留给派出者释放。
