# Chapter 维护：装机 1.2.0 (68)、主页数字重部署、自动部署修复（2026-10-01 上午）

## 已完成

- **自动部署失败的根因（已修）**：`sop.site_build` 是 `python3 scripts/build-site.py --out build/site`，不带 `--release` 时默认读 `build/release/release.json`，那是 1.0.1 (27) 的旧包，于是 Chapter 的 deploy_page 报「measures 1.2.0 (57), release is 1.0.1 (27)」。`build-site.py` 不带 `--release` 时改为选 `perf/lightweight.json` 实测过的那个已打包发行（`build/release*/release.json` 的版本、构建号、下载字节数一致），没有实测过的就取最新包并照旧拒绝构建。提交 `85f3d1d`。
- **回执输入收窄（已修）**：`scripts/verify-install.py` 的回执输入从 `scripts/*.py`、`scripts/*.sh` 改为 build.sh 实际调用的 `build-cli.sh`、`test.sh`、`package-release.py`、`test_file_open.py`、`install-cli.py`。改站点、演示、测量或验收脚本不再让装机回执失效、白涨构建号。同一提交 `85f3d1d`。
- **主页重部署 (57)**：`chapter sop run --app folio-mac --stage promo --retry` 用修好的默认值重建并部署，线上 `facts.json` 卡片为「安装包 3.1 MB（安装后 7.6 MB）· 空闲内存 125 MB · 空闲 CPU 0% · 速度 297 ms」，与 `perf/lightweight.json`（09-30 23:10 对 (57) 的重测）一致；page、card、page_icon、readme 全部 ok。
- **推送**：领先的 3 个提交（CLI 扩展、重测、README 数字）推到 GitHub；推送前按 `scripts/accept/cli_cases.py` 的禁用字符串清单扫描新增行，干净；仓库无 workflows/webhook。
- **装机 1.2.0 (68)**：`python3 scripts/verify-install.py`（build.sh --install 内主编辑区与 LaunchServices 文件打开测试通过），receipt 回读匹配；`folio --version` = `folio 1.2.0 (68)`。装前 Folio 没有运行。
- **验收**：native_ui、cli_entry、functionality、recovery、privacy、installed_icon（离屏读取系统显示图标，与源图标一致）、icon_review 在 (68) 上全部 passed，均由 Chapter 验收器自动判定。
- **发行包 (68)**：`package-release.py --app /Applications/Folio.app --out build/release-1.2.0`，`Folio-1.2.0-68-arm64.zip` 3,200,409 字节，SHA256 `18263b66…`，源码指纹 `caae8759…`；(57) 包移到 `build/release-1.2.0-57/`（线上仍是它）。`capture.json` 登记 `reused_for["1.2.0 (68)"]`，`check_media` 对 68 与 57 都通过。

## 待测量阶段

- 发布 (68) 需要先在空闲门下实测这个包：Chapter 登记的 `sop.measure`（`scripts/release/measure-sop.py`）会测 `build/release-1.2.0/Folio-1.2.0-68-arm64.zip` 并写入 `perf/lightweight.json`；之后 deploy_page 不带参数就会选中 (68) 构建并部署主页，release 项随之对齐。在此之前 Chapter 的 release 项为「发布版 57 落后于装机的当前构建 68」，这是如实的待办，不是故障。
- 注意 (68) 包比 (57) 大约 99 KB（CLI 新命令），实测后主页「安装包」数字会变。

## 未提交

- `perf/acceptance/homepage_*`、`media_playback*` 含本机绝对路径（Playwright 浏览器位置），公开仓不提交，留本地。

## 2026-10-05 晚 · Chapter 三项标准收尾（folio-mac / folio / md-index）

本轮不测性能、不重录、不改 Chapter 引擎。提交 `22ef79d`，已推送（`468f213..22ef79d`）。

- **登记测试**：folio-mac（任务 7cbf3f6b）与 folio（2be656ed）19:36–19:37 在当前代码通过。
- **账号形态**：`ios/01-源程序/project.yaml` 加 `sop.account.mode: none`。依据：`Sources/`、`Shared/` 里没有注册/登录/账号代码，`Shared/AppLifecycle.swift:129-135` 的 URLSession 只是更新检查。
- **Vision 商店截图**：`shots/appstore/vision/01-markdown-simulator-20261004.png` 是 10-04 18:40 `launch_vision` 无窗口模拟器截图的逐字节副本（3840×2160，lane 输入 `2f206556…` 与当前源码一致，共享规格 `store_shots.py vision` 通过）。它是 Debug 验收构建，不是 Release 商店构建，来源文件里写明了。本机 `.git/info/exclude` 有 `*.png`，与 iPhone/iPad 截图一样用 `git add -f` 入库。
- **推送**：20 个提交。仓库无 workflows、Pages、webhook，推送不触发构建或部署。新增行扫描：无凭据、无 ip-legal/Personal/Work/investment 引用；有 1592 行本机绝对路径（`/Users/tianli/Library/Caches`、`Apps/folio` 等，来自 10-04 已提交的 iOS 验收日志），与远端已有的 88 个 iOS 证据文件同类。第一次推送报 `unable to rewind rpc post data` 挂在已关闭的连接上，回读远端未变后改用 `-c http.version=HTTP/1.1 -c http.postBuffer=67108864` 重推一次成功。
- **folio functionality 未解（停在这里）**：`Tests/HostedHarness/run.py:147-152` 要求继承 `SOP_GLOBAL_LOCK_FD/PID/PID_STARTED`。Chapter `engine/app_sop.py:5310-5325` 的 `queue_accept` 自 a57bca9（10-04 23:47）起不再把全局锁传给验收，`_run_acceptor_locked`（4978-4996）会把这三个变量剔掉，所以经队列必然报 `Folio fixed queue identity/actual parent descriptor is required`（任务 cbc6793f）。引擎的行为是有意的（`test_app_sop.py:3333`）。与 10-04 的 copytree 旧失败无关。
- **functionality 改为产品侧适配（team-lead 定，20:00 前后）**：因引擎 a57bca9 不再提供继承锁，`run.py` 去掉了「真实祖先进程持锁」这层身份证明，改为：三个锁变量齐全则按原逻辑核验继承；三个都没有则本进程自己 NB 取 canonical 锁（最长 400 秒），证据里记 `chapter_lock.inherited: false`；只有一两个的残缺状态继续拒绝。`SOP_APP_ID/SOP_CHECK/SOP_REPO` 与拒绝 SIM_LANE 覆盖不变，功能断言一条没动。**后续**：引擎提供不占全局锁的队列身份凭证后恢复这层证明（team-lead 记在引擎待办）。
  - 直接改会永远被自己挡住：`chapter_accept` 取锁后内层 `main()`（原第 386 行）会再取一次，两个独立打开的文件描述互斥。`chapter_lock()` 现在对本进程已持有的锁返回同一 description 的 duplicate。
  - `binding.json` 钉着 `run.py` 与 README 的 sha256，已随改动更新，四个文件核对一致。
  - 不会与队列父进程互等：引擎取全局锁的三处（`app_sop.py:5315`、`5336`、`5528`）都是非阻塞或限时，父进程在子进程运行期间只读日志大小；子进程输出写文件，不等父进程。别的 `app_sop` 在这 400 秒内会得到 busy（75）。
  - 无构建实验（沙盒副本，门替换为立即 Busy）：残缺三种组合均被拒且不写任何文件；三个都没有时取到锁、内层借用成功、结束后锁已放开；完整继承（用引擎 `accept_global_lock_context` 造环境）仍被接受。真实托管运行尚未执行，结果见队列任务。
  - 提交 `4e2cb49`（已推送）。因 `Tests/**` 变了，folio 的登记测试重新排了一次：`430b9abae6ae4b84aa48da558870ad22`；functionality 按 README 的固定入口（带 `--tmpdir /private/tmp`）排了一次：`6b36608f7f27478bb5e16b757d980725`。19:59 入队时前面还有 43 个任务。被负载门推迟（75）就留在队列里，不重排、不 `--retry`，由安静那一轮接续。
- **md-index 常驻服务**：`com.tianli.md-index-graph` 在 launchd 里是 disabled 且未加载，没有进程，8791 不监听，错误日志最后写于 10-04 18:00。`scripts/runtime_readback.py:18` 在服务未加载时直接抛 `CalledProcessError`。没有 enable，没有重启，等本人决定这个服务是否继续常驻。
- **待测性能（本轮未测）**：Mac 线装机已是 1.2.1 (89) 且 build-receipt 匹配，`perf/lightweight.json` 仍是 1.2.0 (68)；iPhone/iPad/Vision 三条线实测输入旧于当前 `2f206556…`。10-04 20:38 的自动测量日志以 `KeyboardInterrupt` 结束（`app_registry.py:182` 目录枚举中被中断），不是产品断言失败。
- **Mac 测量前置修了一处**：`scripts/release/measure-sop.py` 原来只找 `build/release-1.2.1/Folio-1.2.1-89-arm64.zip`，而 (89) 的包在 `build/release-1.2.1-89/`（sha256 与 `release.json`、`SHA256SUMS.txt` 一致），空闲门一开就会以「没有发行包」退出 1。现在两个目录都找。只做了编译和路径解析核对，没有运行测量。

## 2026-10-06 夜 · 每项功能都能不点界面完成（folio 命令补缺与 sop.agent_cli）

需求见 `~/Apps/chapter/docs/PRD-agent-cli.md`，约定见 app 技能 `references/agent-cli.md`。本轮只动 Folio（Mac 与 ios 组件），不测性能、不发布、不推送。

- **新增命令**（`CLI/main.swift`，与界面同一实现，没有第二套）：
  - `folio status`：读回命令，一次给出版本、状态目录、index.json 与索引库、索引文件夹、窗口会话摘要（打开/未保存/冲突/最近/关闭的草稿）和阅读设置。
  - `folio read <文档>`、`folio write <文档>`：走 `DocumentIO.open/save`，保留原换行符与 BOM、原子写入、只读拒绝；文件不存在时新建。目标在窗口里有未保存修改或冲突时 `write` 退出 1，`--force` 才写（窗口标记冲突，不覆盖窗口里的修改）。
  - `folio outline <文档>`：侧栏大纲的标题解析从 `BackendClient.updateOutline` 原样挪成 `MarkdownOutline.headings`（放在 `Sources/GraphEngine.swift` 末尾：App、命令和测试都编它，而 ios 组件的受监测输入不含它，移动端证据不因此失效），界面与命令共用。
  - `folio open <文件>…`：按编辑器规则校验后用 `open -g` 后台交给 Folio 窗口；`-n` 只校验。
- **顶层帮助**补齐四样：读/写命令分列、`--json` 成功与失败的形状、退出码表、「仅在窗口中」与暂缺项。已有命令的 JSON 没改；失败仍是 `{ok:false, command, error(文字), usage}`，没有换成 `error:{code,message}`，因为 Chapter 与脚本在读现有形状。
- **对照登记**：`project.yaml` 的 `sop.agent_cli`，Mac 57 项 = 命令 25、human 18、missing 14；`ios/01-源程序/project.yaml` 16 项 = 命令 9、human 6、missing 1（指到同族 `folio`，`sop.cli` 原样）。功能从 `TLMarkdownApp.swift`（菜单）、`ContentView.swift`、`ViewModel.swift`、`BackendClient.swift`、`Shared/AppLifecycleUI.swift` 与 ios 的 `ContentView.swift`、`Shared/AppLifecycleMobile.swift` 逐项列出。
- **missing（Mac 14 项，同两个原因）**：
  - 写在 `session.json` 里的：正文字体、字号、宽度、启动恢复、图片目录、自定义索引文件、放大/缩小字号，最近记录的固定、移除/重新定位、清空。`session.json` 只由运行中的 App 写（里面还有未保存草稿），命令从外面改会被窗口下一次保存覆盖。要补得先让 App 接收外部请求（例如状态目录里的请求文件加分布式通知，App 用设置面板同一段代码应用后自己落盘；App 未运行时在下次启动应用），再加 `folio settings set`、`folio recent pin|remove|clear`。本轮没做：这条通道碰草稿所在的文件，需要并发和恢复测试，不适合赶在限时里。
  - 只在「配置与更新」窗口里的：iCloud 配置同步开关、配置导出/导入、检查更新、升级到新版。共享的 `AppConfiguration` 与更新检查只在 App 进程里调用。
  - ios 的 1 项是检查更新（移动版尚无发行渠道）。
- **验证**：`bash scripts/test.sh --core-only` 通过（含真二进制 `scripts/accept/cli_cases.py functionality`，新增 status/read/write/outline/open 的用例，全部在 `build/cli-tests/work` 的合成文件和隔离状态目录里，`open` 只跑 `-n`）；`cli_cases.py privacy` 通过（源码与二进制无本机路径，552 KB ≤ 2 MB）；`bash ios/01-源程序/scripts/test-core.sh` 通过。隔离目录里走了一遍 write → read → outline → roots add → index → search → status；错参数 `folio write --bogus --json` 退出 2 且输出 `ok:false`，不存在的文档退出 1。
- **没验的**：`folio open` 不带 `-n` 的真实打开（会让窗口上屏，本轮不许）；它调用的是 `test_file_open.py` 已覆盖的同一条 LaunchServices 路径。带窗口的 `NativeEditorTests`（含大纲回归）没跑，大纲的同一组围栏用例改由命令行用例覆盖，装机门里的主编辑区与文件打开检查照常跑。
- **装机与回读**：`python3 scripts/verify-install.py`（build.sh --install：主编辑区检查不上屏，文件打开检查用 `open -g -j` 隐藏启动的隔离副本）装了两次，现为 **1.2.1 (119)**，receipt 与当前构建输入匹配；上一版在 `~/.Trash/folio-previous-*`。装前装后 Folio 都没有运行，没有启动或重启它。回读：`folio --version` = `folio 1.2.1 (119)`，`folio --help` 退出 0 且含读/写、`--json`、退出码、仅在窗口中四段；`folio status --json` 解析出 `ok:true`、`app:/Applications/Folio.app`；`folio search --limit -1 --json` 退出 2 并输出 `ok:false` 与原因；两份登记里的每条命令都在装机版顶层帮助里找得到。
- **第二次装机的原因**：隔离验收时发现开发版二进制（`build/cli-tests/folio`）把仓库根的 `Info.plist` 当成所在 App，`status.app` 显示成上级目录，`open` 不带 `-n` 时会把文件交给一个不是 App 的路径。装在 `Folio.app` 里的二进制不受影响；已改为只有 `…/X.app/Contents` 才算 App，并补了断言（提交 `d845727`）。
- **提交**：`762efff`（命令、帮助、登记、文档、用例）、`d845727`（上述修正），加本节的交接提交；未推送。仓库里原有的五十多个未提交文件（`perf/acceptance/**` 等）没有动。
- **留给后面的**：Chapter 的 `agent_cli` 检查本轮没有跑（在 `~/Apps/chapter/engine` 里没找到这项检查），登记只用本地脚本核过「三选一」和「命令在帮助里」；missing 14 + 1 项如上；PRD 验收里的「界面改设置、命令读到新值，命令改回去、界面跟着变」后半句要等设置写命令。

## 2026-10-07 凌晨 · 命令入口第二轮：阅读设置与最近记录可读可改，按核验意见修正登记

上一轮（上节）之后有独立核验，本节逐条处理它的意见，并把上一轮留下的阅读设置与最近记录补上命令。只动 Folio，不测性能、不发布、不推送。

- **新增命令**（`CLI/main.swift`；规则写在 `Sources/GraphEngine.swift` 末尾的 `SessionEdits`，设置面板、⌘+ / ⌘- 与最近列表的菜单也用它）：
  - `folio settings`（读）与 `folio settings set <键> <值>…`：`font_family`、`font_size`（13–26，`larger` / `smaller` 同 ⌘+ / ⌘-）、`content_width`（560–1300、20 的倍数）、`restore_session`、`image_folder`、`note_index_path`（`default` 回默认索引）。范围与面板一致，不在范围内退出 2、什么都不改。
  - `folio recent`（读，带 `exists`）与 `folio recent pin|unpin|remove <文件>…`、`folio recent clear`。重新定位 = `recent remove` 旧路径 + `open` 新路径。
  - `folio open --example`：欢迎页「打开示例文档」的同一段复制规则（`ExampleDocument.install`）。
- **谁写 session.json**：同一时刻只有一个写入者。窗口启动时拿状态目录里的 `session.lock`（flock，进程结束即由内核释放）并一直持有；这时命令把修改放进 `requests/<id>.request.json`，窗口由目录事件唤醒（空闲时不轮询），用 `EditorStore.apply` 改自己的状态、立即存盘、写回 `<id>.reply.json`，编辑器和设置面板跟着已发布的值变（`applied_by: window`）。窗口没开时命令自己拿锁，经 `SessionDisk` 读出、修改、写回，标签、未保存正文、关闭的草稿原样保留（`applied_by: file`）。窗口 5 秒不应答，命令撤回请求并退出 1（`window_no_reply`）；超过 30 秒没人理的请求窗口直接丢弃，不会事后生效。锁空着但有 Folio 进程在跑（装新版之前启动的旧窗口，不持锁）时拒写（`window_outdated`），避免被旧窗口的下一次保存覆盖；这项检查只对默认状态目录做。
- **失败输出**加了 `code` 字段（只增不改）：`usage`、`invalid_value`、`not_found`、`window_unsaved`、`window_no_reply`、`window_outdated`、`session_unreadable` 等，其余 `failed`。原有的 `{ok, command, error(文字), usage}` 不变。
- **登记修正**（核验意见逐条）：
  - 关闭标签（含保留草稿并关闭）、恢复关闭的草稿到标签页、提示条上的「重新载入」，手机端的「重新载入并保留当前草稿」：由 human 改为 missing。它们改的是会话里的标签，不是只能真人做；还没接到上面那条窗口通道。
  - 「打开示例文档」由 human 改为 `folio open`（补了 `--example`）。
  - 手机端补登「点正文里的链接」（human）；「配置与更新（版本）」由 `folio status` 改为 missing——`folio status` 读的是 Mac 包的版本，读不到手机上装的。
  - 「配置与更新」窗口的五项（使用 iCloud 记住配置、导出配置、导入配置、检查更新、升级到新版）各占一行，原因统一写「共享生命周期模块暂无命令入口」；本产品不各自实现。
  - `folio --help` 的「仅在窗口中」与登记对齐：去掉「拖入」「拷贝 路径:行号」（登记里对应 `folio open`、`folio search`），补上未命名草稿、打开设置面板、关闭提示横幅、点正文里的链接、光标跳到命中行和手机端的几项；登记里每个 human 项都能在这段找到。
  - 帮助里「读取」一段改成准确说法：不改文档、配置、会话记录和索引内容；读索引库时 SQLite 会刷新库旁它自己的 `-shm` 文件（WAL 模式的只读连接都会，换成 immutable 打开会在界面正在更新索引时读到不一致的内容，所以没改）。
  - 现在的数：Mac 59 项 = 命令 36、human 15、missing 8；手机端 17 项 = 命令 8、human 6、missing 3。
- **验证**：
  - `bash scripts/test.sh --core-only` 退出 0，176 条 PASS。`Tests/StoreTests.swift` 用真 `EditorStore` 验窗口一侧：持锁、命令拿不到锁、`SessionRequests.send`（命令调用的同一个函数）发来的修改被应用到窗口状态并立即存盘、越界值被拒且不改、⌘- 与清空经窗口生效、过期请求被丢弃、应答后目录不留文件。`scripts/accept/cli_cases.py` 用真二进制在隔离状态目录验文件一侧：改五项设置后标签、未保存正文、冲突标记、关闭的草稿都在，文件权限 0600；到头的 `larger` / `smaller` 不变；十一种坏值退出 2 且文件字节不变；pin / unpin / remove / clear 的顺序与 `not_found`；有人持锁而不应答时退出 1、文件不变、请求被撤回；记录损坏时读写都退出 1 且不重写；`open --example` 从假应用包复制一次、不覆盖已改过的副本。`cli_cases.py privacy` 通过（二进制 620 KB ≤ 2 MB）。
  - 为让 `IndexEngine` / `GraphEngine` 两组测试能编过，`scripts/test.sh` 给它们加了 `Sources/Models.swift`（`SessionEdits` 用到其中的设置与最近文件类型）。
- **装机**：`python3 scripts/verify-install.py` 装为 **1.2.1 (121)**，receipt 与当前构建输入匹配（装机门里的主编辑区检查与隔离副本的文件打开检查通过）。装前装后 `defaults export cyou.tianli.TLMarkdown` 逐字节相同，`~/Library/Application Support/TLMarkdown` 的文件清单、大小、修改时间相同，Folio 装前装后都没有在运行，也没有启动它。回读：`folio --version` = `folio 1.2.1 (121)`；`folio settings --json`、`folio recent --json`、`folio status --json` 均 `ok:true`；`folio settings set font_size 99 --json` 退出 2、`code: invalid_value`，`folio recent forget x --json` 退出 2。没有对本人的状态目录跑任何写命令；读回之后只有 `md_index.db-shm` 的修改时间变了（见上）。
- **Chapter 自查**：`chapter sop accept --app folio-mac --check agent_cli` → 登记与帮助无问题，暂缺 8 项；`--app folio` → 暂缺 3 项。`chapter agent-cli --json` 两个组件都是 `status: missing`、`problems` 为空。
- **没做的**：
  - 关闭标签、恢复关闭的草稿、重新载入的命令。窗口里这三个动作带对话框、编辑器通知和文件监视，要先拆出不带界面的那一段，窗口和命令才能共用；通道已经有了（`SessionEdit` 加字段、`EditorStore.apply` 加分支），窗口没开时的文件一侧要与 `EditorStore.reload/close/restoreClosedDraft` 同一段代码。
  - 真窗口进程加真命令的端到端（窗口开着时命令改字号、界面当场变）没有实跑：要有上屏的窗口。窗口一侧是在测试进程里用同一个 `EditorStore` 验的。本人可以开着 Folio 跑一次 `folio settings set font_size larger` 再 `smaller` 看一眼。
  - 窗口没开时 `folio recent clear` 不清程序坞菜单里的系统最近文档（那是 AppKit 按应用记的，命令够不到）；帮助里写明了。
  - 共享生命周期五项与手机端版本读取，等共享模块的命令入口。
  - Mac mini 上的装机没有动。
- **提交**：`61bfa83`（命令、窗口通道、测试、登记、文档）与本节加装机回执的提交；未推送。`perf/acceptance/**` 等其他会话留下的未提交文件没有动。
