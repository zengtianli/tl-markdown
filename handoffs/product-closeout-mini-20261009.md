# Folio Mac 欠项收口 · Mini · 2026-10-09

交接：`20261009-1842-产品欠项收口-folio-mac`，本轮限时 35 分钟，只管 macOS 组件，禁止推送、发版、部署、送审、改变公开范围或合成输入。

初读 Chapter status（缓存及 fresh）与 brief：13 项缺项，2 项登记重检、11 项验收缓存缺失；watcher 信息提示不计缺项。仓库已有 project.yaml、perf 与 iOS 他人未提交改动，保留且不提交。

有限步骤：先固定脚本重检政策和双语命名，再补命令行及图标等短验收，最后按环境和剩余预算补无窗口功能/恢复/隐私及现有离屏 UI；每项回读自己的检查。独立测试可并行，设备和共享证据落盘按原互斥处理。构建如需 xcodebuild 必须经过 sim_lane 排队，不走发版或公证。

分类：13 项先列为会话可执行候选；无已知本人动作。实际接口、安装包缺失、网络与队列阻挡现场核验后记为外部条件。已有素材优先复用，不降标准、不手写通过。

最终产物：`/Users/tianli/mac-pair/tasks/sop-folio-mac-20261009/output/report.md`、同任务根 `result.md` 和原队列 `.reply.md`。完成结果如下。

## 结果

本轮 Chapter 初读 13 项缺项，最终完整 fresh 回读为 4 项；初读 13 项均已收口，重检暴露的剩余项是旧版性能样本、性能输入绑定、卡片部署、README 推送。后两项本交接明确禁止；性能入口未保证不进 Dock，本轮保守未启动，不改检查标准、不写新实测数字。无人需要点击或授权。

新增真实无账号登记；sop.test 改为 python3 scripts/test-core-parallel.py。适配器读取原 scripts/test.sh 的 core 段，拆成 document_io / note_search / store / watcher / structure / IndexEngine / GraphEngine / cli 八块并行，不复制测试实现。首次因 Mini 缺 markdown-it 失败；按锁文件 npm ci（180 包，8 秒）修复依赖后，Chapter 原任务 dbd3295d58b34db1854d6fdde047f08e 接续成功：8 workers、39.8 秒，input_stable=true。已保留首次失败原件，不将失败豁免为通过。代码提交 0916580d15426cb86a2bb75f47e319d589a01bbf。

11 项固定验收均通过、与当前 scope SHA 及证据文件 SHA 一致。新跑 8 项，复用 3 项当前输入未变的证据（icon_review、installed_icon、agent_cli）。更换测试入口使 code/ui/media 绑定变化，最终只补受影响的 5 项，其余不重复跑。最终原件：

- functionality：perf/acceptance/run-l3ti34o0/functionality.json
- recovery：perf/acceptance/run-ahh55qq3/recovery.json
- privacy：perf/acceptance/run-qeotwbqf/privacy.json
- native_ui：perf/acceptance/run-fed5nm7y/native_ui.json，14 个断言为 true，6 张离屏截图已冻结；编辑器、索引空态和设置截图已看过。透明设置截图的白底诊断副本留任务 output，不替换原证据。
- homepage_desktop：perf/acceptance/run-pri_s8a3/homepage_desktop.json，1440px、HTTP 200、无横向溢出、4 张图加载。
- homepage_mobile：perf/acceptance/run-j_o0mru3/homepage_mobile.json，390px、HTTP 200、无横向溢出、4 张图加载。
- media_playback：perf/acceptance/run-12a8aob0/media_playback.json，4 个本地 H264 视频完整解码，网页 3 段播放到 1.1–1.3 秒。
- cli_entry：perf/acceptance/run-vth5x4jf/cli_entry.json，真实装机内 CLI 通过。

App/CLI 仍为 1.2.1 (128)，装机 receipt 验证通过；无需重构建、安装或重启。未运行 xcodebuild、模拟器、性能采样、GUI 合成输入、推送或发布。

只将自己的 project.yaml 两处增量和新适配器提交；原 sop.product 的 12 行他人变更仍留工作树，iOS 和既有 perf 脏文件不提交。全局 post-commit 会运行 git_follow 向另一台 Mac 推送，所以本机提交用临时 hooks 路径保留原 pre-commit 凭证扫描及 commit-msg 门，省略该自动推送；共享 hooks 和同步开关均未修改。

完整报告、当前状态 JSON、失败及通过日志保存在原任务 output；最终回执写原队列路径。产品尚余上述 4 个标记，本轮授权范围内工作已完成。
