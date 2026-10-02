# Folio 非 UI hosted XCTest 入口

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
