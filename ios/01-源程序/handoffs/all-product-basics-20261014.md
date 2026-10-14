# Folio 移动端 product_basics — 2026-10-15

本轮责任范围：Sources/MobileProductLifecycle.swift、FolioMobileApp.swift、ContentView.swift、MobileEditor.swift、MobileStore.swift 的设置/动作接线；新增产品设置与进程内自检；Shared 生命周期文件仅通过总部 vendor-lifecycle.py 原入口逐字节分发；project.yml、Resources/Folio.entitlements；scripts/accept/product_basics.py、project.yaml 的 product_basics/accept/相关功能清单、README 与本交接。保留其他会话改动、暂存及后台。最新接续轮精确 claims 身份为 PID 43047、chapter-task:48e5ac24f6165c13a625688b25626952，写前核对，不另开或释放（此前 PID 34499、95241 均为历史）。

共享资源：总部生命周期源只读；Chapter 标准/引擎只读；SDK 构建与模拟器使用原 sim_lane 全局串行锁，仓外冻结副本；不得触碰生产配置、真实 iCloud 或账户数据。无装机、上传、推送、发布、公证或更新源写入。

完成谓词：实际当前源码候选与原 sim_lane build receipt 绑定；必要静态/Core 回归；真实模拟器 App 的离屏原生控件动作、跨进程持久化、14 项必测原始布尔检查与 SHA；执行 chapter sop accept --app folio --check product_basics --json。隔离云传输与 Apple 跨设备传输分别报告，不冒充手机装机。阶段预算为本轮有限源码、构建、验收与一次针对实际错误的修复；共享环境忙则按 75 交回原队列。

已核：固定标准 schema 1 的四项合计 14 项；原移动入口配置为 nil、渠道 unreleased，不能当作通过。ASC 只读 apps 返回 cyou.tianli.TLMarkdown.mobile 对应真实记录 6819568883；此记录存在不表示已公开发行。

## 当前接续（PID 43047，以下历史过程以此为准）

- 本轮仅接续真实候选构建/验收与本交接，未追加源代码改动。开工回读原 job、原失败/暂缓事实、工作区及 claims；入场负载 11.74、无模拟器锁，与前轮负载等待相比条件已改变。
- 已实际执行规定的 `chapter sop accept --app folio --check product_basics --json`：原入口成功生成当前 c49c9eaef2bc3149c2f7025961de4ca4ffea67d99c86141690255679ea5151d5 输入的普通 Release iOS/Vision 候选，1.2.1 (2)、cyou.tianli.TLMarkdown.mobile；运行准入时负载升为 69.4，高于 18，最终退出 1、status:deferred。尚未安装到本轮专用模拟器或启动 Folio 业务，不把「Runtime iphone」准备日志当运行成功。
- 当前 iOS 候选 /private/var/folders/6_/r0ygnj7s41g013d21kpwlph80000gp/T/sim-lane-build.h6tprqqt/dd/Build/Products/Release-iphonesimulator/Folio.app；主程序 SHA256 53281d121022da835f8afe02cc7210a00657884fc4d582b7fe1fbae138d1f3be；build/product-basics/iphone-build.json SHA256 8928c8fc48af733b1708960632c81c3c34f0f54bd8b3a31ecba434633381c24d；36 个包文件与回执完整相符，真实构建 13.6 秒。
- 当前 Vision 候选 /private/var/folders/6_/r0ygnj7s41g013d21kpwlph80000gp/T/sim-lane-build.rfdh30nq/dd/Build/Products/Release-xrsimulator/Folio.app；主程序 SHA256 d048226c5ec4bb2d53a397e01141bcd262aa0d149f86fadd99c60cb15b6ff325；build/product-basics/vision-build.json SHA256 3e8e5e18b5b04ab591a0ebc92d2bf65dca72428b1d15ccf1d090b0820bade576；34 个包文件完整相符，真实构建 12.1 秒。
- 原 reuse_build 对 iphone、ipad、vision 三线均成功核验当前输入、仓外冻结源码与真实 SDK 包；iPad 合法复用同一 iOS 包。上述完整文件对照使用产品固定脚本原 artifact_files 实现，没有把回执改成通过证据。后续保持源码冻结，直接复用当前包，不为负载等待重编。
- 已交还原队列，enqueue 返回 deduplicated:true，仍为 e4c4a629451b48ac9dfbe291ead3b822、status:deferred；未新建并行作业、未降低阈值或重跑同因。队列消息保留其前次锁等待，最新直接验收输出已明确是负载等待；Chapter 的 deferred 处理会保留先前失败规范原件，不能据旧 yaml 日志认定当前构建失败。
- 剩余是资源准入后运行真实 App 的全部 14 项、三平台离屏设置图与独立新进程读回；本机隔离 iCloud 链路、Apple 跨设备传输均未实测。接续 `chapter work --once --app folio --json`，查询 `chapter jobs --app folio --active --json`；当前源码候选已具备，不重复前轮源码或构建阶段。未装机、发布、上传、公证、修改生产配置/iCloud/账户或既有后台；不手写 delivery-evidence，也不声称完整验收。

## 前轮接续（06:46）

- 本轮先回读原始 failed 记录与完整日志：规范原件仍是上轮 Python 缺 yaml 的失败；后续 deferred 由 Chapter 恢复此前原件，不能把它误认为 Python 修复失效，也不能把 deferred 当 passed。回读原 job e4c4a629451b48ac9dfbe291ead3b822 仍 queued，未另建执行者。
- 入场负载 14.42 且无锁，沿 `chapter work --once --app folio --json` 接续原 job；实际准入时被 fitcoach-ios:product-basics、PID 35992 先取锁，原队列返回 deferred，next_attempt_at 06:45:24。没有碰对方设备或进程。
- 对本产品代码检查发现快捷键辅助动作仅由自检调用，实际 SwiftUI 菜单直接调用 store.reload。已将启用快捷键时的菜单动作接到同一 MobileReloadShortcut.perform，并抽出 binding(enabled:) 供真实菜单和自检共同使用；触屏菜单在禁用硬件绑定时仍可安全重新载入。自检新增对真实绑定关闭为 nil、恢复后 key/modifiers 的断言，没有合成按键或放宽检查。
- 修改后已实际执行规定的 `chapter sop accept --app folio --check product_basics --json`，退出 1、status:deferred，最新原因「1 分钟负载 64.8 在 0s 内没降到 18.0 以下」，在构建准入前停止。没有重跑同因，未降低阈值。Tests/static_check.py 和 git diff --check 通过；新快捷键接线尚未编译及运行，旧候选不再视为当前输入。
- `chapter enqueue --app folio --action accept --check product_basics --tmpdir /private/tmp --json` 返回 deduplicated:true，保留原 job e4c4a629451b48ac9dfbe291ead3b822、status:deferred，不新造队列。资源允许后由固定脚本重建输入变化的候选，再跑真实 iPhone/iPad/Vision App、14 项行为、离屏原图及新进程读回。接续 `chapter work --once --app folio --json`；查询 `chapter jobs --app folio --active --json`。
- 本轮新输入 c49c9eaef2bc3149c2f7025961de4ca4ffea67d99c86141690255679ea5151d5，72 个绑定文件；它与历史候选 996230d2… 不同。收尾只读负载回读 25.9，仍超过 18，锁已不存在；未以无锁代替负载准入，也未重复执行同因失败。
- 当前仍未有四项运行验收通过；本机隔离 iCloud 链路与 Apple 跨设备传输都未测，不能称完整交付。未安装手机或 Mac、未外发发布、未修改生产数据或既有后台，既有未暂存的产品展示块和其他会话产物保留。

## 前轮结果（06:43）

- 本轮主体源码已提交 51a9cf2；后续原队列接续发现 Chapter 登录 shell 的 python3 缺 yaml，已在固定验收器 build_environment 中选择同一个真实 Chapter Python 的 PATH，不改共享引擎或原 build.sh。原失败任务 bb57bf86128f445e97b3fe7b7927dd82 已结束，失败原件 perf/acceptance/run-5o8lqyub/product_basics.json 与 product-basics-mobile-a6cc95da49244330af1605cb521f63a5/raw.json 保留，不冒充产品行为已执行。
- 最终源码已沿原入口实际重建两线成功，均为普通 Release、1.2.1 (2)、cyou.tianli.TLMarkdown.mobile；input_sha256 996230d2e926adbb9bc60872bd42e0b926b50e4fbba7b56e2a6311a79ee82f69。原 reuse_build 对 iphone、ipad、vision 三条线全部验证成功，iPad 合法复用同一 iOS 包，不改写平台事实。
- 当前 iOS 候选 /private/var/folders/6_/r0ygnj7s41g013d21kpwlph80000gp/T/sim-lane-build.7kfszkbc/dd/Build/Products/Release-iphonesimulator/Folio.app；主程序 SHA256 abfd8d3724b097e9eeb8410ef453d91d01a5f920382086f024b464475dc41235；build/product-basics/iphone-build.json SHA256 924746b9d3bf1c73875a17b7261bc3afdf04cb1c8851c95e1396bb96d5f521ad，绑定全部 36 个包文件，真实构建 13.2 秒。
- 当前 Vision 候选 /private/var/folders/6_/r0ygnj7s41g013d21kpwlph80000gp/T/sim-lane-build.5wvex3mp/dd/Build/Products/Release-xrsimulator/Folio.app；主程序 SHA256 d2b6b2db87c150b38d95c8f2cc390b2e628d965bfebfffd1cb6da3d105b6e1e7；build/product-basics/vision-build.json SHA256 b3bf25abdc803468edb84bd0ea769fe11571739150e121da8a1296bbe9c348ec，绑定全部 34 个包文件，真实构建 11.8 秒。
- 原占用锁后来释放，已接续原队列一次并修实际 Python 入口错误，再以改变后的输入执行必需的 chapter sop accept --app folio --check product_basics --json。最终真实返回退出 1、status:deferred，原因「1 分钟负载 96.5 在 0s 内没降到 18.0 以下」。没有降低门槛、强行占用设备或同因循环；Folio 未进入模拟器业务运行，不能记 14 项通过，也没有可供目视的设置截图。
- 剩余验收已交回原队列 job e4c4a629451b48ac9dfbe291ead3b822（2026-10-15 06:42:46 创建，accept/product_basics，tmpdir /private/tmp，status:queued）。环境允许后复用现有当前候选，仅续真实运行与完整 14 项检查；固定脚本仍先核回执与完整包，输入变化才构建。接续 `chapter work --once --app folio --json`，状态 `chapter jobs --app folio --active --json`。
- 当前完成：四项源码、共享能力接线、登记、固定隔离自检、当前候选与包输入回执、必要静态/Core 回归。当前未完成：三平台真实 App 运行、14 项行为、离屏图与独立新进程读回；本机隔离 iCloud 链路及 Apple 跨设备传输都尚未实测。没有安装、上传、推送、公证、发布或修改用户真实数据；本任务尚未完整验收，等待原队列准入自动补齐，无须用户决定。

## 本轮源码与入口

- 实现真实阅读设置文件 reading.json，字号/宽度直接传给唯一 WebKit Editor；原生 UIKit 设置控件、可关闭的外接键盘 ⌘⇧R 及安全重新载入共用原文稿业务。原共享 AppConfiguration 白名单仅 reading 字段，新增 KVS entitlement，默认关闭；文稿、恢复草稿、书签、权限不迁移。
- App Store 记录 6819568883 配到原共享更新检查器，支持原生检查、系统商店获取及启动自动检查选项；未声称该记录已公开发行。导入导出仍由共享 AppLifecycleMobilePanel 执行。
- 固定脚本 scripts/accept/product_basics.py 已登记到 sop.accept.product_basics，四项登记齐全；普通 Release App 内 --product-basics-self-test 有 exercise/readback/cleanup 阶段，真实 UIKit 控件 target/action、WebKit CSS、重新载入保留草稿、隔离云文件往返与损坏/不可用恢复、真实 App Store HTTPS 检查和共享检查器隔离测试源、新进程持久化及清理逐项产生布尔检查。没有网络 mock、替代业务引擎或顶层 ok 冒充通过。
- 脚本默认只在缺失/过期时经原 scripts/build.sh 与 sim_lane 锁准备当前候选；显式 --app/--receipt/--vision-receipt 必须严格匹配，不偷偷重建指定包。回执绑定跨根真实输入与全部候选文件，iPad 只在原 reuse_build 校验允许时复用 iPhone 包。--inspect 只读原始证据并验 SHA，不能当作当前手机状态查询。

## 历史构建与验证（中间输入）

- bash scripts/test-core.sh 退出 0：静态接线、生产编码/保存/恢复/冲突、双编辑器代次、权限边界、图片 FD 竞态与大小约束，以及真实开发 CLI 编译和 --help 均通过。它不覆盖新设置 UI 或手机运行。最终补充清理与候选完整文件绑定后，Tests/static_check.py、固定脚本 Python AST 和 git diff --check 仍通过；没有把它们当 14 项运行证据。
- 主实现的普通 Release iPhone 与 Vision 实际 SDK 构建均成功。最初自检布尔表达式含 throwing RHS 的 Swift 编译错误已修正后重建；原编译失败日志保留于 sim-lane-build.rmipzgzi/build-iphone-Release.log。此后一次改为真实 App Store 网络查询及共享测试源 I/O，再次构建两线成功。
- iPhone 中间候选：/private/var/folders/6_/r0ygnj7s41g013d21kpwlph80000gp/T/sim-lane-build.6kl2gpzj/dd/Build/Products/Release-iphonesimulator/Folio.app；1.2.1 (2)，cyou.tianli.TLMarkdown.mobile；二进制 SHA256 458d43d5aa6c9f8f514f9309c596e41a94ca900dea28caacdc391dff52e9444a；build/product-basics/iphone-build.json SHA256 63811028e9dcfaf6f3f2a0815277f4ebd6ae42acb11a52692f9faf2acb0b3d59；真实构建 11.7 秒。
- Vision 中间候选：/private/var/folders/6_/r0ygnj7s41g013d21kpwlph80000gp/T/sim-lane-build.3sf4g084/dd/Build/Products/Release-xrsimulator/Folio.app；同 bundle/版本；二进制 SHA256 41771cee037eb0ac4cf735c5acf47de75c57cac94b50cdabfaf0c88409374cc7；build/product-basics/vision-build.json SHA256 300ceb63ff1831b85a98de1902ebd91f40d40f89632c6bef27c5160fe2e294f8；真实构建 11.5 秒。两份回执 source_layout.input_sha256 均 db6577b8fe94d72c84874a0f2eb1021aed753247e759838a8f0ee7aa40ed19a3，Xcode 27.0 (27A266a)。
- **上述是中间候选**：随后增加测试域清理、无效自检参数拒绝、自动准备过期候选及完整包文件绑定，输入已变化，最终源码仍须重建，固定脚本会拒绝把旧回执当当前候选。未改写旧回执、未称当前版本已安装。

## 早期固定验收与锁等待（历史）

- 已按要求实际执行 chapter sop accept --app folio --check product_basics --json，CLI 退出 1，product_basics.status:deferred，原文「模拟器锁 /Users/tianli/Library/Caches/sim-lane/lock 被 sim_lane:iphone:14252 (pid 14252) 占着，0s 内没轮到」。Folio 没有进入任何模拟器运行阶段，14 项均未实际通过，不生成手写通过证据。Chapter 对 deferred 沿原逻辑处理验收原件；本轮没有手写 perf/delivery-evidence.json。
- 只读核实 PID 14252 属于 fitcoach-ios 的 product_basics，父 PID 14161；该任务随后失败退出，原锁仍 keep_booted:true，UDID 12EB09F6-4195-4458-84FF-2BDA92BED17B。未接管、释放或关闭其保留模拟器，未触碰对方源码或后台。需要原 owner/Chapter 协调收回失败任务留下的资源，不能把锁忙算产品失败。
- 已交回原 Chapter 队列：job bb57bf86128f445e97b3fe7b7927dd82，action accept、check product_basics、tmpdir /private/tmp，2026-10-15 06:38:46 创建，回读 status:queued、message:等待执行。它会在原车道可用后准备最终候选，再运行全部三条移动线；没有创建平行 runner 或宣称正在运行。
- 接续（进入本组件目录）：`chapter work --once --app folio --json`；只读状态 `chapter jobs --app folio --active --json`。若原队列完成后出现实际代码失败，先读固定 product_basics 日志/原始检查和真实失败输入，再定向修复，不对同因循环。单独重新验收的固定入口仍是 `chapter sop accept --app folio --check product_basics --json`。
- **剩余事实**：最终输入的候选/完整包回执尚未生成；真实 App 的 14 项行为、三端离屏设置截图和新进程持久化尚未执行；本机隔离 iCloud 链路也尚未实测，Apple KVS 跨设备传输另未验证。四项源码和登记已补，完整 product_basics 交付未完成。
- 本轮没有安装任何 Mac 或手机包，没有上传、签约、推送、公开发布、部署、公证或写更新源，没有改变真实配置、iCloud/账户数据及已有后台。仅提交本轮源与交接；既有 project.yaml 产品展示追加块、原 perf/验收差异和其他会话文件保留。
