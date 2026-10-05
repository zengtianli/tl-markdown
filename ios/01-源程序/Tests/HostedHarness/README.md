# Folio 非 UI hosted XCTest 入口

## 原 persistent queue 的真实 functionality

`sop.accept.functionality` 调用本目录 `run.py --chapter-accept`，原 Core test 不再代判文件闭环。
固定模式先在真实 Chapter inherited canonical FD 内沿原 cached_build 选当前普通 Release SDK，
缺失才必要编；随后原 prepare 生成冻结overlay，真实XcodeGen/Debug build-for-testing完成后
保存实际命令、exit、当前源/测试不变、prepare/log SHA 的独立 observation，交给原 bind 核产物，
最后原 run 做一次真实 non-UI Hosted。ordinary Release与Hosted Debug分列，不当perf/Store。

```sh
cd /Users/tianli/Apps/folio/ios/01-源程序
chapter enqueue --app folio --action accept --check functionality --tmpdir /private/tmp --json
```

只入队一次，由既有worker串行消费；不要额外 SDK/boot/worker。父文件FD必须属于真实祖先
PID/start、canonical普通文件dev/inode，独立open必须已NB锁忙，再核继承同description排他锁；
子只close duplicate不LOCK_UN。没有继承字段的原手工run仍自己拿真实NB。固定队列模式
（2026-10-05起）接受两种：三个继承字段齐全，按上述核验；或三个都没有，由本进程自己NB取
canonical锁，内层run借同一description的duplicate。残缺或foreign字段仍拒，SOP_APP_ID/
SOP_CHECK/SOP_REPO与拒SIM_LANE覆盖不变。原因：Chapter a57bca9起验收期间放开全局锁、不再
下传FD。自取锁时没有“真实祖先持锁”这层身份证明，证据里记inherited:false；引擎提供不占
全局锁的队列身份凭证后恢复。原native SDK链/专有Folio Integration/Session的lock/load wait=0保留。
原bind按真实xctestrun解析Host与TestBundle（包括Host外的.xctest），逐文件绑定两个完整
产物目录的名字与SHA；缺/空/foreign目录、symlink逃逸或新增/删除/改变文件均拒绝。旧缺完整
test产物绑定的manual manifest仍保留历史，不能作为当前runtime复用来源。
阶段核真实AC、load、no-other-builder、lowpower，不用OWNER_NOW覆盖；全过程没有UI事件、
Simulator.app、焦点或Dock动作，检测GUI进程出现即失败。

沿原总600秒，操作截止400秒，200秒留原180秒shutdown/ownedPID-start进程组、锁链与证据。
必须真实3passed/0failed/0skipped、输入稳定及cleanup成功才由原消费者写通过。新断言要求生产
URL→WK编辑→生产保存→fresh store重开，以及reloadPreservingDraft/权限失败恢复，不称系统
picker/grant或OS Scene覆盖。各attempt receipt/log/prepare/bind/test/xcresult/cleanup在
`perf/acceptance/hosted-fileflow-20261004/`；真正编成且完整bound的外部overlay可保留作原严格复用
来源，没有active PID/native锁/Booted设备。75保原job等待，不重复入队或偷改证据。

当前66生产输入为 `26afdae298f46c1cafe35d34a91074b5f6e09b82da7aefde34de31762fb06177`，
新增WK规则真实缓存优化后旧750d SDK只属历史，不能冒当前。当前Hosted Swift测试SHA
`108b44b60dd355693fd180475786073d7e2ea3b3dc1978887a363c3b9917bd44`；普通 SDK不含Tests，
本次驱动接线不再改变66生产源码。接线/纯检查不代表该源码已编译、Hosted运行或启动预算通过。

这是已运行过的 prepare/run 流程的仓库入口。没有 Markdown/业务算法副本，没有 XCUIApplication、点击、按键或其他合成输入。只支持已验过的 iPhone hosted SDK 路线；iPad/Vision 运行尚未声明通过。

`prepare.py`、`bind.py` 和 `run.py` 默认只读校验。工作目录、普通 SDK receipt 必须显式传入；执行还必须显式指定专用 UDID。所有重操作由 Root 取得唯一串行槽后执行。不要在重队列外直接运行 XcodeGen/编译/模拟器。

1. 原普通 SDK receipt 由现有 sim_lane 构建提供。prepare 使用原 reuse_build 校验源、副本、SDK、Xcode 和二进制，并独立冻结当前测试源；测试变更不会逼普通 App 重编。

```bash
/Users/tianli/Dev/.venv/bin/python Tests/HostedHarness/prepare.py \
  --workdir /ABS/FRESH-WORKDIR --receipt /ABS/SDK-RECEIPT.json --platform iphone
```

加 `--write` 才写仓外 `iphone/project.hosted.yml`、`test_src` 和 prepared.json。不会改原项目或普通 SDK 冻结树；输出目录有旧证据时拒绝覆盖。

2. 在已分配的串行槽中，用实际 overlay 做 XcodeGen 和一次 build-for-testing。保存真实完整日志与 hosted-build-observation.json（exit_code、input_stable、preparation_sha256、log、log_sha256）。此入口不替自己编造该观察记录，也不会运行编译。

3. bind 将真实 xctestrun、host/test binary、全部 App 资源、项目、测试、准备脚本和编译日志绑定为 run-expected.json。当前历史实际编包绑定为 51 件；未来按实际文件数登记。

```bash
/Users/tianli/Dev/.venv/bin/python Tests/HostedHarness/bind.py \
  --workdir /ABS/WORKDIR --receipt /ABS/SDK-RECEIPT.json
```

加 `--write` 才写新绑定；旧绑定不覆盖。源码、测试、prepare/build 观察与产物任一变化都会拒绝。

4. 已绑定包的只读校验与真正单轮运行：

```bash
/Users/tianli/Dev/.venv/bin/python Tests/HostedHarness/run.py \
  --workdir /ABS/WORKDIR --receipt /ABS/SDK-RECEIPT.json
/Users/tianli/Dev/.venv/bin/python Tests/HostedHarness/run.py \
  --workdir /ABS/WORKDIR --receipt /ABS/SDK-RECEIPT.json \
  --udid OWNER-ALLOCATED-UDID --execute
```

run 只使用 test-without-building。NB 取得 Chapter 原全局锁，sim_lane.Session 的 lock/load wait 为 0；只接受 Folio Integration、iPhone-17-Pro/iOS27.0、Shutdown 的专用设备。记录 PID/start/进程组，Simulator/AppSimulator GUI 出现即不通过；finally 只回收自己的进程、设备和 held locks，shutdown 失败也释放锁。每次独立日志/xcresult，真实 3 passed、0 failed/skipped、前后输入稳定、清理成功才通过；失败保留，不自动重试。

仓库 harness 另由 binding.json 绑定；不在 62 个生产源输入中，不借历史运行宣称新入口已实跑。改 harness 后更新它自己的绑定并真实复验。

2026-10-03 原实际运行证据在 `perf/acceptance/hosted-sdk-20261003.json`：生产 4aa、测试 42dd、日志 240477a4，3/0/0。该历史证据不因迁移入口而重写。它只覆盖 SDK/WebKit 内的生产 URL、渲染/编辑/安全保存、两个编辑器、附件与恢复；不证明系统 Files 授权/选择器、OS Scenes、整 App 重启、资源预算或新 harness 已运行。

2026-10-04 按固定五平台标准补齐第一项的文件闭环断言：在真实 hosted App 进程中，以生产 `MobileStore.open` 打开合成 BOM/CRLF 文稿，经原 WK Editor API 编辑、生产保存后，用新的 `DocumentWorkspace`/`MobileStore` 重开并核正文与非 dirty 状态；外部冲突后走生产 `reloadPreservingDraft`，核外部文件不变、未保存草稿保留且新 store 能恢复两份内容。这是新增测试准备，须重新冻结当前测试、真实 build-for-testing 和 run 后才有运行结果；不复写历史3/0/0，不称系统 picker 授权、Scene URL 派发或整进程重启已验。

当前生产66输入 `750d36751372b4662a2fe3f75b5bda2503c0c8c957002f8215a6291d449b78e7` 的已有普通 iPhone/iPad Release receipt 位于 `/Users/tianli/Library/Caches/sim-lane/platform-measure/sim-lane-build.e6982c0791732bfce73b18268bda234214598f596023b7e4fb5e4d72f08f88e6/sim-lane-build.5zz7oo95/build.json`。2026-10-04 原 prepare 默认只读严格复用已成功，未 build/boot；新增断言仍未实跑。下一沿上文原入口使用该 receipt 和新工作目录，不采用旧62源 GUI 准备或旧 hosted 产物。测试变更不改变这66个生产输入，也不要求重新普通 SDK 构建。
