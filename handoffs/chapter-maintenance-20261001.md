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

## 2026-10-07 下午 · 命令入口第三轮：「配置与更新」四项与标签的关闭 / 恢复 / 重新载入，装机 1.2.1 (123)

需求与约定同前两节（`~/Apps/chapter/docs/PRD-agent-cli.md`、app 技能 `references/agent-cli.md`、`platforms.md`「配置迁移与版本更新」）。本人对这一轮的原话只有「好，继续做完，铺开」；下面每个具体做法是执行时自己定的，不是本人逐条同意过的。只动 Folio，不测性能、不发布、不推送。

- **边界（实际改动）**
  - 新增 `Sources/Shared/AppLifecycleCLI.swift`：总部 swift-shared 的逐字节副本，sha256 `c869edf8…5e`，没有在这里改。另三份共用副本（AppLifecycle / AppConfiguration / AppLifecycleUI）没动，`AppLifecycle.swift`、`AppLifecycleUI.swift` 仍落后总部，窗口没有换版。
  - 新增 `Sources/Lifecycle.swift`：产品一侧唯一的工厂（产品名、更新源、可迁移的键、偏好域、隔离规则、导入前的核对、命令入口）。
  - `CLI/main.swift`：帮助文字、命令表、`config` 子命令与 `update` 的分发、`tabs` 命令、失败短码三条。原有命令的实现没改。
  - `Sources/GraphEngine.swift`：只动文件末尾「Session edits」一节（`SessionEdit` / `SessionRequests` 加字段，新增 `SessionTabs`、`SessionLock.held`）。
  - `Sources/ViewModel.swift`：只动 `EditorStore` 的 `init` 参数、`persist` 开头一行、`apply` / `answerRequests`、`touchRecent`、`reload` / `close` / `restoreClosedDraft`、`reloadConfiguration`。
  - `Sources/TLMarkdownApp.swift`：`FolioLaunch` 两个开关、`AppDelegate` 的自检分支、`TLMarkdownApp.init` 里接「配置与更新」的那一段、新增 `FolioLifecycleSelfTest`。
  - `TLMarkdown.xcodeproj/project.pbxproj`（两个新文件的四处登记）、`scripts/build-cli.sh`（编译清单）、`scripts/accept/cli_cases.py`（加用例）、新增 `scripts/accept/lifecycle.sh`、`Tests/StoreTests.swift`（加用例）、`docs/cli.md`、两份 README 的命令行一节、`CLAUDE.md` 命令行一节、`project.yaml` 与 `ios/01-源程序/project.yaml` 的 `sop.agent_cli`。
  - 没碰：`Sources/Models.swift`、`IndexEngine.swift`（手机端的受监测输入）、`Editor/`、手机端源码、`site/`、`perf/lightweight.json` 与测量脚本、`build.sh`、`scripts/test.sh`、swift-shared 原版、Chapter、别的产品。`perf/build-receipt.json` 由装机入口重写；`perf/acceptance/agent_cli*`、两份 `delivery-evidence.json` 由 `chapter sop accept` 重写。
- **新增命令**
  - `folio config status | export -o <文件> [--force] | import <文件> --yes | sync on|off --yes [--dry-run]`、`folio update check`：走共用层，与窗口同一个 `AppConfiguration` 逻辑和更新检查。不带子命令的 `folio config` 还是原来的索引配置，输出没变。
  - `folio tabs close <文档|标签id> [--save|--keep-draft]`、`folio tabs restore`、`folio tabs reload <文档|标签id>`：标签栏的三个动作。规则在 `SessionTabs`，窗口的按钮改成也调它；关闭有未保存修改的标签时，窗口对话框的回答由命令自带，都不给等于取消。
  - 失败输出仍是 folio 自己的信封（`{ok, command, error(文字), code, usage}`）：共用层的 `error:{code,message}` 在 `present()` 里转成这个形状，一个命令只有一种失败形状。新增短码写在 `folio --help` 和 `folio config --help`。
- **接法，以及和轻仪不一样的地方**
  - `folio` 是和 App 分开的 Swift 可执行文件，同一批源码编出：共用层四个文件加 `Lifecycle.swift` 直接编进 CLI（620 KB → 866 KB，上限 2 MB）。版本与 bundle id 取命令所在的 .app（`Product.bundle`）；开关的偏好域 App 用 `.standard`，命令用 `UserDefaults(suiteName: <所在 .app 的 bundle id>)`。
  - **App 里没有接 `AppLifecycleCLI.follow`。** 共用层自己写 `session.json`（可迁移的阅读设置就在这个文件里），而本产品的规则是这个文件同一时刻只有一个写入者。所以 `config import --yes` 和真正拨开关的 `config sync … --yes`：窗口开着时整条命令经 `requests/` 交给窗口，在窗口进程里用窗口自己的 `AppConfiguration` 执行（开关、状态句、编辑器当场跟着变），执行完窗口立刻重读五项阅读设置并存盘；窗口没开时命令拿会话锁自己执行。只读的（`config status`、`config export`、`update check`、`--dry-run`、没带 `--yes` 的调用）不拿锁、不写任何东西。`applied_by` 写明走的哪条路。
  - 窗口执行这条命令期间，窗口自己的每次保存先从文件取五项阅读设置再写（`persist` 里 `lifecycleRunning` 那一行）。原因见下面「对照」。
  - 隔离：`TL_MARKDOWN_STATE_DIR` 和 `APP_LIFECYCLE_SUPPORT_DIR` 必须同时设或同时不设，只设一半时 `config` 子命令拒绝（`isolation_incomplete`），窗口也不接「配置」一组。隔离运行的开关放在 `FOLIO_PREFERENCES_SUITE` 指的 `test.tianli.folio.` 开头的具名偏好域。
- **做的过程里发现并处理的两件事**
  - 共用层的导入是「整组替换」：文件里没写的可迁移键会被从 `session.json` 删掉。`EditorSettings` 的字号、宽度、启动时恢复、图片目录是必需字段，少一个整份会话记录就解不出来（下次启动会被另存为 `session-unreadable-*.json`，标签和草稿不再恢复）。手测时用只含两项的文件导入，记录真的变成了读不出的 92 字节。处理：命令在交给共用层之前先核对（类型、设置面板的范围、必需项齐全），不合就整份拒绝（`import_rejected`），什么都不写；无窗口时另有兜底，共用层写完后记录解不出就恢复原字节并报失败。**窗口里「导入配置…」按钮本身没有这层核对**（原有行为，没改；改它要动共用窗口或 `Models.swift`）：给它一份不完整的文件，按源码推断窗口会提示「配置恢复未完成」并在下一次保存时把原设置写回，这条没有在按钮上实测。
  - 第一版自检真实失败过一次：窗口执行 `config sync on` 时等了满 30 秒报 `sync_incomplete`，而同步其实已经完成。原因是请求目录的事件回调本身是主队列上的块，在里面转 run loop 等不到共用层经 `DispatchQueue.main.async` 送回的完成回调。改成从 run-loop 块里执行（`RunLoop.main.perform`），一次一条、按到达顺序；等了超过 5 秒才轮到的命令不执行并回报。
- **验证**
  - `bash scripts/test.sh --core-only` 退出 0，PASS 由 176 条变 188 条。`Tests/StoreTests.swift` 用真 `EditorStore` 验窗口一侧（标签三个动作、交来的配置命令、没接「配置与更新」的窗口、没人接的命令、旧窗口的应答）；`scripts/accept/cli_cases.py` 用真二进制验文件一侧（`lifecycle_and_tabs`：帮助、只读命令不写任何文件连锁文件都不建、十种坏导入逐字节不变、导入后其余记录原样且权限 0600、同步开关与云端副本、背靠背、持锁不应答 5 秒内放弃、旧窗口应答判为 `window_outdated`、标签三个动作的各种分支、记录损坏时都不重写）。
  - `scripts/accept/recovery.sh`、`functionality.sh`、`privacy.sh` 通过（`SOP_OUT_DIR` 指到临时目录跑的，没有改 `perf/acceptance` 里 Chapter 的证据）。原有的 `--ui-self-test`（含重新载入、关闭标签）在试构建的隔离副本上 14 项通过。
  - **带窗口的自检** `bash scripts/accept/lifecycle.sh [某个 .app]`：`--lifecycle-self-test` 让构建产物的隔离副本（`sim_lane.uielement_copy`，另一个 bundle id，LSUIElement）充当运行中的窗口，激活策略 `.prohibited`，不上屏、不进 Dock；用的是 `TLMarkdownApp.init` 里同一段接线和真的 `EditorStore`，共用窗口离屏构造；子进程经名为 `folio` 的软链跑包里真的命令；每次判定都另起进程读回（`config status`、`settings`、`session`），外加云端那份文件。52 项，含三轮开关、四轮「两条命令背靠背」（on>off、off>on，从第二条返回起 1.5 秒内每次读回都必须是第二条的值）、窗口自己的开关与命令互读、导入、两次导入背靠背、五种坏导入、同步开着时导入、标签三个动作，以及本人真实的会话记录、偏好文件、同步目录前后只 stat 比对未变。导入那几段期间窗口每毫秒存一次盘，模拟正在打字。最终这版在试构建、装机包的副本、默认构建产物上各跑一次，3 次全过（加每毫秒存盘那段负载之前的一版另过 1 次）；结果在 `build/accept/lifecycle/`（`lifecycle.json`、`lifecycle-installed-123.json`、离屏渲染 `lifecycle-window.png`）。
  - **对照（分辨力）**：把「执行后重读设置」和「执行期间存盘先取文件里的设置」两处去掉另编一版，同一套自检 5 项失败（`window_takes_imported_settings`、`import_survives_the_windows_own_saves`、`back_to_back_imports_keep_the_last` 等），另起进程读到的字号退回导入前的 18；结果留在 `build/accept/lifecycle/lifecycle-counter-experiment.json`，那一版构建已删。没加每毫秒存盘之前，去掉第一处保护自检照过，所以这段负载是分辨力所在。背靠背开关这一段在本产品的接法下没有做对照：窗口是开关的唯一写入方，命令在窗口里串行执行。
- **装机**
  - 提交 `0bb5776` 后用产品既有入口 `python3 scripts/verify-install.py`（`build.sh --install`）装为 **1.2.1 (123)**，receipt 与当前构建输入匹配。签名装前装后都是 ad-hoc（`spctl -a -vv`：rejected；没有公证票据），等级没变。旧包在 `~/.Trash/folio-previous-1791354911/Folio.app`。装前装后 Folio 都没有在运行，没有启动它。
  - 装前装后 `defaults export cyou.tianli.TLMarkdown` 逐字节相同；`~/Library/Application Support/TLMarkdown` 六个文件的 SHA256、大小、修改时间、权限相同；`TianliApps/Configuration/cyou.tianli.TLMarkdown` 与 iCloud Drive 里的配置文件装前装后都不存在。与当天最早那次留底相比只有 `md_index.db-shm` 的修改时间变了（读索引的只读命令都会，内容哈希没变）。
  - 原有命令装前装后对照：`status / config / settings / recent / roots / stats / session` 的 `--json` 没有少字段，除构建号外取值相同，退出码相同；`folio settings --no-such --json` 仍退出 2。帮助里只有这轮有意改写的几行不同。
- **装机版上的实机证据**
  - 对本人真实状态只跑了只读的：`folio config status --json`（开关为关、五个可迁移项）、`folio config sync on --dry-run --json`（`would_change: true`，没改）、`folio config export -o <临时文件>`（导出的字号 19，与 `folio status` 读到的一致）、`folio update check --json`（联网读到产品主页的发行记录：当前 1.2.1 (123)，此渠道 1.2.0 (68)，`ahead_of_channel`）。这几条之后会话目录没有多出锁文件，`session.json` 与偏好未变。
  - 错误参数：`folio config status --no-such --json`、`folio update bogus --json`、`folio tabs close --json` 都退出 2、`usage: true`；`folio config import <文件> --json`（没带 `--yes`）退出 2、`confirmation_required`、没写任何东西。
  - 装机版的二进制在隔离状态里把 `lifecycle_and_tabs()` 整段和 `lifecycle.sh /Applications/Folio.app` 各跑了一遍，都过。
- **没有验证的**
  - **没有对本人真实的会话记录、偏好和 iCloud Drive 跑过任何一条写命令**（`config import --yes`、`config sync on|off --yes`、`tabs …`）。这几条在真实状态上没有实机证据。
  - 真实 iCloud Drive、真实偏好域（App 用 `.standard`、命令用 `suiteName` 读同一个域）这条路径没有实测；自检用的是具名测试域和临时「云」目录。
  - 上屏的真窗口加真命令没有实跑；自检的窗口从未显示，没有真人点开关。本人可以开着 Folio 跑一次 `folio config sync on --dry-run`，想真试再 `folio config sync on --yes` / `off --yes` 看窗口里的勾跟不跟（这会写 iCloud Drive）。
  - `update check` 只有上面那一次真实联网结果，没有离线用例；「有新版」分支没有实机证据（现在本机比渠道新）。
  - 没测性能（约定不测）；CLI 现在链接 AppKit，试编时粗看启动多约 1 毫秒，那是并行负载下的读数，不能当证据。
- **界面行为有三处跟着变了**
  - 提示条「重新载入」：文件读不出时，以前会先多出一个「重新载入前的修改副本」标签再报错，现在只报错、什么都不加（原标签里的修改仍在）。
  - 带 `TL_MARKDOWN_STATE_DIR` 但没设 `APP_LIFECYCLE_SUPPORT_DIR` 的普通启动（比如诊断启动），「配置与更新」窗口不再有「配置」一组：以前这种启动会把隔离目录里的设置接到本人的偏好和 iCloud 上。
  - 关闭标签、恢复草稿的收尾改成调 `SessionTabs` 里的同一段，行为按原样保留；`StoreTests`、`WatcherTests`、`RecoveryAcceptance`、`--ui-self-test` 都过。
- **已知边界与留给后面的**
  - 窗口没开时，`config sync on` 和同步开着时的 `config import` 在等 iCloud 那一次同步期间一直持有会话锁（通常不到一秒，最长 30 秒）。这期间启动的 Folio 只等 0.3 秒拿不到锁，之后的写命令会被 `window_outdated` 拒绝，直到重开 Folio；重叠的那一小段里窗口的保存和命令的写入仍可能互相覆盖。没有实测。
  - 不是命令触发的后台同步（另一台设备改了设置、本机下载时）正好碰上窗口存盘，旧设置可能被写回：这是原有的情况，这轮只保护了「命令在窗口里执行」的那一段。
  - `scripts/accept/lifecycle.sh` 没有登记进 `sop.accept`（这轮 `project.yaml` 只许动 `sop.agent_cli`），`build.sh` 的装机门也不跑它，回归不会被 Chapter 自动发现；要登记或接进装机门由本人定。
  - 窗口换成总部现版（另三份副本刷新）没做，按约定要本人先定。现在窗口标题仍是「Folio · 配置与更新」，开关是复选框；自检两种控件都认。
  - 暂缺 2 项按约定留着：「升级到新版 / 下载新版」（命令不做静默安装）、「iCloud 配置同步状态那句话」（由运行中的 App 持有）。手机端暂缺 2 项：读不到手机上装的版本、移动版尚无发行渠道。
  - Mac mini 上的装机没有动。
- **Chapter 自查**：`chapter sop accept --app folio-mac --check agent_cli` → 登记与帮助无问题，暂缺 2 项；`chapter agent-cli --json --app folio-mac` → `status: missing`，62 项 = 命令 43、human 17、missing 2，`problems` 为空（上一轮是 59 项、暂缺 8）。`--app folio`（手机端）→ 17 项 = 命令 9、human 6、missing 2，`problems` 为空（上一轮暂缺 3；「重新载入并保留当前草稿」现在对应 `folio tabs`）。
- **提交**：`0bb5776`（命令、窗口通道、自检、测试、登记、文档）与本节加装机回执的提交；未推送。`perf/acceptance/**` 等其他会话留下的未提交文件没有动。

## 2026-10-07 傍晚 · 命令入口第四轮：「升级到新版」与同步状态那句话有了命令，装机 1.2.1 (128)

共用层这天下午定稿了两条：`update install --yes [--dry-run]` 和 `config status` 的 `sync_status`（总部 `5d2ad1d`、`50a4919`）。本节把它们接进 Folio。本人对这一轮的原话只有「继续全部做完。按照你的意思」；下面的具体做法是执行时定的。只动 Folio 的 Mac 端，不测性能、不发布、不推送，`ios/` 不归本节。

这一轮由两个执行者接力：前一个 17:46 开工，18:05 随主会话重启被结束，没有留下提交和交接；后一个 18:10 接手。下面标「前任」的是前一个留在工作区、后一个逐处读过并自己跑过测试后沿用的。

- **结果**：`folio update install --yes [--dry-run]` 与 `folio config status` 的 `sync_status` 在装机版 1.2.1 (128) 里可用；`folio --help` 不再有「暂无命令」；登记里原来的 2 项暂缺改成命令。Chapter：`folio-mac` 由 `missing`（62 项 = 命令 43、human 17、暂缺 2）变为 `passed`（命令 45、human 17、暂缺 0）。
- **边界（实际改动）**
  - 前任写、后任沿用：`CLI/main.swift`（顶层帮助、`config --help` / `update --help` 的形状与短码表、`update` 的用法提示；命令实现没动）、`Sources/Lifecycle.swift`（隔离运行的更新渠道、`replacementProblem`、窗口执行命令时状态记录名的处理、隔离运行里「运行中的 App」怎么认）、`Sources/TLMarkdownApp.swift`（只动 `--lifecycle-self-test`：加同步状态那句话与 `update` 的检查）、`scripts/accept/cli_cases.py`（帮助核对、`sync_status` 各段、新增 `upgrade_cases`）。
  - 后任写：`project.yaml` 的 `sop.agent_cli` 两行、`docs/cli.md`、两份 README 的命令行一节、`CLAUDE.md` 命令行一节、本节。
  - 没碰：`Sources/Shared/` 四份副本、`Sources/ViewModel.swift`、`GraphEngine.swift`、`Models.swift`、`IndexEngine.swift`、`Tests/`、`scripts/accept/lifecycle.sh`、`build.sh`、`scripts/test.sh`、`Info.plist`、`ios/`、`site/`、`perf/lightweight.json`、别的产品与总部原版。`perf/build-receipt.json` 由装机入口重写；`perf/acceptance/agent_cli*` 与 `perf/delivery-evidence.json` 由 `chapter sop accept` 重写，没有提交。
- **接法**
  - `update install` 不改 `session.json`，所以不走窗口通道、不拿会话锁，由命令进程直接交给共用层（`FolioLifecycle.run(… as: .reader)`）。失败仍转成 folio 自己的信封（`{ok, command, error, code, usage}`）。
  - 本机从源码装的 Folio 是临时签名，更新源是公开渠道（产品主页的 `release.json`）。共用层对这种组合不替换：有新版时窗口里是「下载新版…」，命令退出 1（`manual_install`）并给出安装包地址。所以 `update install --yes` 在这台机器的装机版上现在不会替换任何东西；带开发者签名的发行版才会走完整替换。
  - 隔离运行（设了 `APP_LIFECYCLE_SUPPORT_DIR`）的更新源换成隔离目录里的测试发行记录（`.privateCloud(channel: "isolated")`，读 `APP_LIFECYCLE_CLOUD_DIR/TianliApps/Updates/<bundle id>/isolated`），不联网。真实运行的更新源没变。
  - `FolioLifecycle.replacementProblem`：带 `--yes` 的 `update install` 在隔离运行里只替换隔离目录里的 App，只设了 `TL_MARKDOWN_STATE_DIR` 的运行一律不替换，都在查发行记录之前拒绝（`isolation_incomplete`）。
  - 共用层让每条命令把自己的同步结果记到命令自己的记录里（`status-command.json`），免得盖掉窗口那句。Folio 的 `config import` / `config sync` 在窗口开着时是窗口自己执行的，所以 `FolioLifecycle.run(… as: .window)` 在执行前后把记录名放回窗口那份（`status.json`），窗口执行完命令后 `config status` 读到的仍是窗口此刻显示的那句（`from: app`）。
- **验证**
  - `bash scripts/test.sh --core-only` 退出 0：Swift 测试 188 条 PASS（与上一轮同数，本轮没加 Swift 用例），真二进制用例 `scripts/accept/cli_cases.py functionality` 通过。这次测试编出的 `folio` 与装机版里的 `folio` 是同一个文件（sha256 都是 `592093bc1cfe413b…`）。
  - `cli_cases.py` 本轮新增的（都在 `build/cli-tests/work` 里的合成文件和隔离目录）：帮助逐项核对（顶层有 `update install --yes`、没有「暂无命令」、短码齐全，`update --help` 的形状）；`config status` 的 `sync_status` 在没同步过、同步后、关掉后、有人持锁四种情形的取值；`upgrade_cases` 在一个一次性的临时签名假 App 上（真 `folio` 放在它的 `Resources/bin`，经软链调用）验没有发行记录、版本相同、比渠道新、有新版时的 `update check` 与 `--dry-run`、缺 `--yes` 退出 2、发行包哈希不对（`upgrade_failed`，App 未动）、所在目录不可写（`manual_install`）、隔离目录之外的 App 与只隔离状态目录的运行（`isolation_incomplete`），以及真的替换一次：装上新版、旧包进隔离目录里的「废纸篓」、`backup` 为 null、`old_app_cleanup` 为 `trashed`、没有重开任何东西。
  - 带窗口的自检 `bash scripts/accept/lifecycle.sh`：64 项（上一轮 52 项）全过，跑了两次——提交前的试构建一次，装机后对 `/Applications/Folio.app` 的隔离副本一次（`build/accept/lifecycle/lifecycle.json`、`lifecycle-installed-128.json`）。新增的 12 项：窗口还没发布过句子时命令读到开关的初值；三轮开关里窗口执行完命令后，命令读到的是窗口此刻显示的那句（`from: app`、`live: true`，与窗口的状态行、`configuration.status` 三者相同）；窗口自己拨开关后同样；隔离运行的 `update check` 只读隔离渠道；有新版时 `update check` 给出 `folio update install --yes`；`--dry-run` 认出这个窗口是要先退出的 App 而没有让它退出；缺 `--yes` 退出 2；这几条之后 App、会话锁都还在。自检里从不带 `--yes` 跑 `update install`。
  - 跑测试和自检时机器负载均值在 200 以上（十几个单元同时编译），没有出现计时类失败。
- **装机**
  - 提交 `fe37ed1` 后用产品既有入口 `python3 scripts/verify-install.py`（`build.sh --install`）装为 **1.2.1 (128)**（装前 1.2.1 (123)；构建号取提交数），receipt 与当前构建输入匹配。签名装前装后都是 ad-hoc（`spctl -a -vv`：rejected；没有公证票据），等级没变。可执行文件 sha256 前 16 位：`6a05539fe96febf0` → `a0fec3e6be1082bc`；`folio`：`e557225e71395974` → `592093bc1cfe413b`。
  - 旧包由 `build.sh` 移到 `~/.Trash/folio-previous-1791369787/Folio.app`（构建号 123，可执行文件哈希与装前留底相同）。`/Applications` 里只有一个 Folio。
  - 装前装后 Folio 都没有在运行，没有启动或重启它。
  - 装前装后 `defaults export cyou.tianli.TLMarkdown` 逐字节相同；`~/Library/Application Support/TLMarkdown` 六个文件的 SHA256、大小、修改时间、权限相同（与 18:15 的第一次留底相比只有 `md_index.db-shm` 的修改时间变了，是装前读索引的只读命令造成的，内容哈希没变）；`TianliApps/Configuration/cyou.tianli.TLMarkdown` 与 iCloud Drive 里的配置文件装前装后都不存在。
  - 原有命令装前装后对照：`status / config / settings / recent / roots / stats / session / config status` 的 `--json` 没有少字段，除构建号外取值相同，退出码都是 0；`config status` 多了 `sync_status` 一组；`folio settings --no-such --json`、`folio config status --no-such --json` 仍退出 2、`code: usage`。
- **装机版上的实机证据**（只跑了只读的）
  - `folio --version` = `folio 1.2.1 (128)`；`folio --help` 退出 0，写入一段有 `update install --yes`，`config status` 那行提到同步状态，全文没有「暂无命令」。
  - `folio config status --json`：`sync_status` 为 `{text: "iCloud 配置同步已关闭", at: null, from: "derived", live: false}`（开关为关、Folio 没在运行、从没同步过）；文字输出多一行「同步状态：iCloud 配置同步已关闭」。
  - `folio update install --no-such --json` 退出 2、`code: usage`；多给一个词同样退出 2。
  - `folio update check --json`（联网读产品主页的发行记录，不读 iCloud）：当前 1.2.1 (128)，此渠道 1.2.0 (68)，`ahead_of_channel`，`upgrade.command` 为 null。`folio update install --dry-run --json` 与不带参数的 `folio update install --json`：都退出 0、`installed: false`、`state: ahead_of_channel`，什么都没动。这几条之后状态目录没有多出文件，装机版仍是 128。
- **Chapter 自查**：`chapter sop accept --app folio-mac --check agent_cli` → `passed`，界面功能对照 62 项 = 命令 45、human 17、暂缺 0，读回 `folio status`；`chapter agent-cli --json --app folio-mac` → `status: passed`，`problems` 为空（上一轮是 `missing`、暂缺 2；改登记后、装机前读到的是 `unchecked`）。手机端组件（`folio`）这一轮由别的单元处理，不在本节。
- **没有验证的**
  - **没有对真实装机版跑过 `update install --yes`**（约定不跑）。真的替换只在一次性的假 App 上验过，走的是隔离渠道的本地发行包。
  - 公开渠道那条完整的路（https 下载、开发者签名比对、`spctl` 评估、替换、重开）在 Folio 上没有任何实跑：本机构建是临时签名，按共用层源码这种组合在有新版时是 `manual_install`。`manual_install` 这个分支只用「所在目录不可写」触发验过，「公开渠道加临时签名」触发的没有实测（现在渠道没有比本机新的版本）。
  - 装机版上「有新版」的各分支没有实机证据（本机比渠道新）。
  - 运行中的真窗口加 `sync_status` 的 `from: app`：只在离屏自检里验过，自检的窗口从未显示；Folio 的真窗口这一轮没有开过。
  - 运行中的 Folio 被 `update install --yes` 要求退出、换好再重开这一段没有实跑。按源码，Folio 退出前会存盘、未保存的正文留在会话记录里并在下次启动恢复；没存成时退出会被取消，命令 20 秒后报 `app_busy`、不替换。
  - 新增的「窗口那句话」检查没有做对照（去掉 `FolioLifecycle.run` 里放回记录名的那两处之后自检会不会失败，没有试）。
  - 没有对本人真实的会话记录、偏好和 iCloud Drive 跑过任何一条写命令（同上一轮）。没测性能（约定不测）。Mac mini 上的装机没有动。
- **留给后面的**
  - 隔离运行的窗口现在读隔离渠道而不是公开渠道（`FolioLifecycle.updateSource` 改成了按是否隔离取值）。真实运行不受影响；以后写隔离测试时不要指望它联网。
  - `scripts/accept/lifecycle.sh` 仍没有登记进 `sop.accept`（这轮 `project.yaml` 只许动 `sop.agent_cli`），回归不会被 Chapter 自动发现。
  - 冲突副本 4 个留在原处（见下），要不要清由本人或管两机同步的会话定。
- **提交**：`fe37ed1`（命令、工厂、自检、用例、登记、文档）与本节加装机回执的提交；未推送。`perf/acceptance/**`、`perf/delivery-evidence.json`、`ios/` 下别的会话的未提交文件没有动。

- **经过（按时间）**
  - 18:12 声明边界被两机准入挡住：mini 侧账本上还挂着前任同名会话的租约（进程已不在，本机记录也没了）。没有绕，等它在 18:23 自己到期后才声明（`agentcli2-folio-mac`，13 个文件）。等的时候只做了不写产品目录的事。
  - 四份共用副本（`Sources/Shared/`）与总部现版逐字节相同，已由别的会话在 `129ea99` 提交，没有再动。
  - 冲突副本 4 个（`perf/delivery-evidence.sync-conflict-…json`、`handoffs/chapter-maintenance-20261001.sync-conflict-…md`、`ios/01-源程序/project.sync-conflict-…yaml`、`ios/01-源程序/perf/delivery-evidence.sync-conflict-…json`），都不在编译或打包路径，当前文件都比冲突副本新且更长；没有移，也没有提交它们。
  - 留底（18:15，在执行者自己的临时目录）：装机版 1.2.1 (123)，ad-hoc 签名，`spctl` rejected，无公证票据；`defaults export`、数据目录六个文件的清单与 SHA256；Folio 没在运行。
  - 18:32 `bash scripts/test.sh --core-only` 在当前工作区（含前任的改动）退出 0：Swift 测试 188 条 PASS（与上一轮同数，本轮没加 Swift 用例），真二进制用例 `cli_cases.py functionality` 通过，含本轮新加的 `upgrade_cases` 与 `sync_status` 各段。跑的时候机器负载均值 210 上下，没有出现计时类失败。
  - 18:32 起重命令按主线的排队规则跑（先 1 号槽，18:34 改 3 号槽）：试构建 → `scripts/accept/lifecycle.sh` → 提交 → 装机。
  - 18:37 试构建（`bash build.sh --build-only`，当时还没提交）编过；18:38 `bash scripts/accept/lifecycle.sh` 在这份构建上通过：64 项（上一轮 52 项），`failed` 为空，背靠背回退 0，偏好域与工作目录都已清掉。结果在 `build/accept/lifecycle/lifecycle.json`。
  - 18:39 提交 `fe37ed1`（九个文件：命令、工厂、自检、用例、登记、文档）。构建号取提交数，现在是 128。
  - 18:40–18:43 `python3 scripts/verify-install.py` 装机（装前再核一次 Folio 没在运行、偏好与数据和 18:15 的留底一致）。18:43 装后比对与装机版只读验证；18:44 Chapter 验收 `passed`；18:45 装机包隔离副本上的自检通过。声明在收尾提交后释放。
