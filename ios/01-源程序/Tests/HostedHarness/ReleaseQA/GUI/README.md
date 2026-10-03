# Folio 真实 Files / Scene GUI 会话

此入口只准备 Root 通过 CUA 的真实操作。默认 dry；不 build、不自行打开 Simulator、不发送合成输入，不写安全作用域或 Session 元数据。原 Chapter file NB、原 sim_lane directory/load0、真实设备 owner 和 boot 前 admission journal 都保留；同一原 Session 持门至 `Root.done`，最终只清理自己的 worker/设备，未知或 foreign 门沿原 guard 留失败尾项。

本次唯一生产改动是 `project.yml` 两行 Scene flag，新62输入 `8309e99023c5314768151efa4498d8f0b249dc35d86d6e303eff794ca71275e0`。旧普通 Release 的真实 Info 没有 SceneManifest。入口严格要求新的真实普通 Release receipts、严格源码复用和实际 Info 中的 flag；旧4aa包拒用。2026-10-03 六包 Scene 批次已实际编译两个普通 Release SDK；当前只读 strict reuse 再次通过，尚未运行 GUI，不能宣称 Scene 已通过。

## 当前可执行的原 GUI 准备

**最终入口（2026-10-04）：** 原共享`eb4c61d`/SHA `e8ed9e00…`修正manual owner-active只选择合格fixed capture，29窄案例通过；本resource PIN采用这一最终版本。当前原prepare目录是`/private/tmp/folio-gui-scene-current-20261004-e8ed`，执行时用它替代下文旧b6/145c目录；source62、Scene普通Release两包与全部GUI断言/门未变。下文前两准备为历史，不直接execute。

2026-10-03 govern后共享app_sop仅修launch子进程Python与显式无界面media准入，冻结`8191f47`/SHA `145c1a26…`、27窄案例通过。原resource PIN跟到此真实版本，62源及两份Scene普通Release SDK不变，不重编、不重测旧host资源。旧b6准备保留；下一使用原prepare生成的新独立目录`/private/tmp/folio-gui-scene-current-20261003-145c`，默认dry和真实GUI门仍保持。此PIN更新不是Files/Scene PASS。

2026-10-03 后续仅更新原 `resource.py` 的两个已评阅工具 PIN：Chapter `b6d60b6d…`（固定平台 capture，原锁及验收保全不变），measurer `8b477d95…`（既有 SDK 原回执缓存复用，原采样/负载门不变）。其他工具、62 生产输入与普通 SDK 不变；旧准备和原件保留。新准备由本目录原 `prepare.py` 实际生成，绑定文件 SHA `3dcfe75ef8edca054496611963d6f198e145c5c893890399acad9f4f10a96d29`，[持久原件与范围](../../../../perf/acceptance/gui-scene-prepared-current-20261003/manifest.json)。一条 iPad 默认 dry 与旧 ABI 的纯拒绝反例通过，均未查询设备、boot、截图或操作 Files。

新 workdir `/private/tmp/folio-gui-scene-current-20261003-b6d` 使用仓内 `perf/acceptance/scene-sdk-20261003/{iphone,vision}-release-build.json` 原回执。iPad 复用普通 iPhone 包及原 owner `FF227F5B-7D8C-4C26-8831-9897C3ABA235`，iPhone owner 为 `61D5B9F4-6669-41F0-BC0F-EBE48AF0E02D`；这里只读原 owner，实际身份/Shutdown仍须执行时按原门核。

Root 分配唯一 GUI 槽后，沿原入口执行一次 iPad 会话（默认命令仍 dry，执行时追加 `--execute`）：

```sh
cd /Users/tianli/Apps/folio/ios/01-源程序 && /Users/tianli/Dev/.venv/bin/python -B Tests/HostedHarness/ReleaseQA/GUI/run.py --workdir /private/tmp/folio-gui-scene-current-20261003-b6d --platform ipad --slot-seconds 600
```

预算含取门、启动、真正系统 Files/Scene 操作与清理；建议450秒前写 bound `Root.done` 留清理余量。只有 Root CUA 实际打开/授权、两个 OS 窗口、保存与冲突字节证据才闭合对应范围。旧有效 host 资源不因工具 PIN 更新重采；WebKit 负责者合计仍缺可靠 XPC 归属证据，不把 host-only 改称完整资源。

以下保留原新轮准备格式（NEW 为参数占位）；上述当前准备已经存在，不重复生成或重编：

```sh
cd /Users/tianli && /Users/tianli/Dev/.venv/bin/python -B /Users/tianli/Apps/folio/ios/01-源程序/Tests/HostedHarness/ReleaseQA/GUI/prepare.py --workdir /tmp/folio-gui-scene-new --iphone-receipt /absolute/NEW/iphone-release-build.json --vision-receipt /absolute/NEW/vision-release-build.json --prior-owner iphone=/Users/tianli/Apps/folio/ios/01-源程序/perf/acceptance/store-iphone-runtime-20261003/owner.json --prior-owner ipad=/Users/tianli/Apps/folio/ios/01-源程序/perf/acceptance/store-ipad-runtime-20261003/owner.json
cd /Users/tianli && /Users/tianli/Dev/.venv/bin/python -B /Users/tianli/Apps/folio/ios/01-源程序/Tests/HostedHarness/ReleaseQA/GUI/run.py --workdir /tmp/folio-gui-scene-new --platform ipad --slot-seconds 600
```

只有新 Root 独占 GUI 槽授权后，在后者追加 `--execute`。一次一个平台，不自动重试。iPad 实际已有自有设备 `FF227F5B-7D8C-4C26-8831-9897C3ABA235`，以真实 owner receipt 复用；17Max 同理。Vision 没有有效 owner 时只能由原 ensure 在真实未来槽创建并记录，dry 不造 UID。

控制器立即输出实际 run directory；等其 `ready.json`。Root 此后才用官方 Simulator 入口选定 `ready.udid` 并通过 CUA 操作。脚本不打开或杀掉 GUI。总600秒从初始输入读取前起算，包含 admission/boot/install/UI 等待/最终 cleanup；到界不入新阶段，已有操作自然结束，超预算最终失败。建议450秒前结束 GUI，留清理余量。Root 应在 `Root.done` 前用 CUA 关闭自己打开的 Simulator 窗口。

Files 夹具没有预种 App/Documents：真实包 `UIFileSharingEnabled=false`，那个目录不能冒称 Files 可见。worker 仅在自己持门期间提供绑定127.0.0.1随机端口的只读虚构 ZIP；`ready.fixture_url` 是实际端口。Root 在 Simulator Safari 实际打开该 URL、下载并在 Files 的“我的 iPad/iPhone”→“下载项”解压，形成 `FolioGUIFixture/folio-gui.md` 和 `assets/pixel.png`。若实际 Safari/本地 provider 不可用，该步骤记阻断；不伪造已导入。主机上的真实 provider/container UUID 路径只有原 App 经 Files 打开后才从生产 `session.json.documents[].path` 读取；不会静态编造。`checkpoint-*.json` 会记录这个真实路径，仍不能代替系统选择器授权证据。

最小真实操作顺序：

1. 原生产 `-folio-demo` 已进入真实 Editor；该参数仅隔离恢复目录，并不禁用 Files。通过“文稿操作”→“打开 Markdown”，在系统选择器选上述 `folio-gui.md`，截图记录文件提供方与打开结果。
2. 未授目录时观察相对图缺权限提示，正文仍能编辑。选择“授权图片目录…”并在真实目录选择器选 `FolioGUIFixture`，观察红蓝合成图。文件与目录两次授权分别记录。
3. 选择“编辑文稿”，加入唯一 `GUI-A` 字样，选择“保存原文件”。通过下述 checkpoint 记录实际屏幕、App 创建的恢复 Session 和文稿路径；Root 读取那个实际文件验证 BOM/CRLF 与 `GUI-A`，不把提示文字当写盘证明。
4. iPad/Vision 用系统窗口菜单创建第二 Folio Scene，观察两窗口同文稿；A 编辑 `GUI-A2` 后 B 操作旧内容，确认旧回写被拒或同步、A 草稿保留。系统无法创建第二 Scene 则明确失败，不把两个 WK 实例当真 Scene。
5. 冲突可由 Root 明确请求仅这个虚构原文件的外部改写：先取得真实当前文件 SHA 和生产文稿 id，再发 `external-conflict` 请求。UI 再编辑并保存应拒覆盖外部 `EXTERNAL-CONFLICT`，当前草稿仍保留；随后“重新载入并保留当前草稿”检查两个版本。仅合成文件可写，不涉及用户材料。
6. 时间允许时 Root 通过真实系统 App 切换/强制关闭后重新打开，观察本地未保存草稿恢复；不篡改恢复 JSON。余量不足即只记录已验范围。

`Root.request.json` 和 `Root.done` 是 Root 写给自己持门 worker 的控制文件。用同目录临时文件后原子 rename，避免半写；每个请求都绑定实际 `ready.json` SHA。checkpoint 名称唯一：

```json
{"ready_sha256":"ACTUAL_READY_SHA","action":"checkpoint","name":"saved-a"}
```

外部冲突请求（当前 SHA 必须与磁盘原件相等，否则拒写；限当前自有 device 内普通合成文件）：

```json
{"ready_sha256":"ACTUAL_READY_SHA","action":"external-conflict","document_id":"ACTUAL_PRODUCTION_DOCUMENT_ID","expected_sha256":"ACTUAL_CURRENT_FILE_SHA"}
```

完成时 `Root.done` 内容：

```json
{"ready_sha256":"ACTUAL_READY_SHA","root_cua_only":true,"observed_steps":["填写实际已做步骤和截图路径"],"blocked_steps":["填写实际未验或失败步骤"]}
```

worker 只返回会话完成/清理范围，不自动宣布 Files/Scene PASS。Root 须按真实 CUA 截图、系统选择器、两窗口和源文件字节逐项判定。所有成果在独立 `gui-runs`，不修改旧 Store/Core/hosted/SDK 证据，不把 GUI 会话当资源或商店全套验收。
