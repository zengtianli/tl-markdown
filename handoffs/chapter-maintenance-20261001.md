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
- **md-index 常驻服务**：`com.tianli.md-index-graph` 在 launchd 里是 disabled 且未加载，没有进程，8791 不监听，错误日志最后写于 10-04 18:00。`scripts/runtime_readback.py:18` 在服务未加载时直接抛 `CalledProcessError`。没有 enable，没有重启，等本人决定这个服务是否继续常驻。
- **待测性能（本轮未测）**：Mac 线装机已是 1.2.1 (89) 且 build-receipt 匹配，`perf/lightweight.json` 仍是 1.2.0 (68)；iPhone/iPad/Vision 三条线实测输入旧于当前 `2f206556…`。10-04 20:38 的自动测量日志以 `KeyboardInterrupt` 结束（`app_registry.py:182` 目录枚举中被中断），不是产品断言失败。
- **Mac 测量前置修了一处**：`scripts/release/measure-sop.py` 原来只找 `build/release-1.2.1/Folio-1.2.1-89-arm64.zip`，而 (89) 的包在 `build/release-1.2.1-89/`（sha256 与 `release.json`、`SHA256SUMS.txt` 一致），空闲门一开就会以「没有发行包」退出 1。现在两个目录都找。只做了编译和路径解析核对，没有运行测量。
