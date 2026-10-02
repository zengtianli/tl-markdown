# Folio · 文页 — 移动文稿入口

同一 Folio 产品的 iPhone、iPad、Apple Vision Pro 原生入口：从 Files 打开 UTF-8 Markdown，使用原 Folio Editor 阅读、编辑与源码模式；显式保存原文、另存为，以及本地恢复草稿。Mac 沿用族根应用；Watch 无适合正文编辑的独立流程。

Files 导入与系统打开入口使用安全作用域书签，访问成对释放；读文件经 NSFileCoordinator，原文保存复用原 `DocumentIO.save` 的冲突检测和原子写入。BOM 与换行符仍由同一业务层保留。编辑只写私有恢复记录，重新载入先保留当前草稿，WebKit 重启从已收到的草稿恢复。另存为冻结导出快照；导出期间的新修改保持未保存状态。权限书签损坏时独立降级，有效 session 草稿照常恢复、编辑与另存；原文件保存需重新从 Files 打开同一文件取得授权，显式替换权限记录前保留坏记录原字节。正文恢复记录本身损坏时保留原件并显示独立救援入口。

多个窗口共享一个文稿所有者和恢复仓，操作绑定发起窗口自己的编辑器 flush，不使用“最后载入的编辑器”。每次文本修改递增 revision，编辑器加载代次随消息传入；过期窗口与延迟旧代次回写不得覆盖新文稿，并发新增内容保留为独立恢复草稿，不自动合并。编辑器拆除前先检查自己的未送文本，旧实例不能注销替换后的新实例。实际多窗口 WebKit 交互仍待原生验收。

默认阅读，菜单进入编辑；左上角可切文稿及恢复草稿。未命名文稿用“另存为”。单文件授权只用于正文，未授权父目录时正文仍能编辑保存；相对图片会提示在菜单选择“授权图片目录…”，必须明确选择当前文稿所在目录，独立持久书签用于目录安全作用域。图片读写均在授权目录句柄内逐层 O_NOFOLLOW/openat，拒绝父级/叶子符号链接、越界与非普通文件；读取每块最多64 KiB，累计严格小于40 MB，每块及结束核对 fstat，文件增长或内容变更则拒绝预览。原授权基线不重新解析为换链后的目录；另存到其他目录后须重新授权图片目录。外部网络图片阻断，不发送正文。链接仅由用户点击打开。文稿上限 5 MB，图片沿原 Folio 40 MB 上限；不支持整库索引与 Mac 目录图谱，这些仍由 Mac 入口承担。

## 源码与构建

引用族根 `Sources/Models.swift`、`Sources/IndexEngine.swift`、`Resources/Editor` 和许可；本组件仅有权限与平台 adapter。唯一 XcodeGen target FolioMobile 使用 `supportedDestinations: [iOS, visionOS]`，由 XcodeGen 推导实际 iPhone/iPad/Vision 设备族 1,2,7。移动 bundle ID 为 `cyou.tianli.TLMarkdown.mobile`，三条移动线共享；原 Mac ID 保持。版本沿原 Folio 1.2.0，build 1 是开发初值，未准备上传。

```sh
bash -c 'source scripts/env.sh && xcodegen generate'
bash scripts/build.sh iphone   # 同样支持 ipad / vision；共享 sim_lane 仓外构建
bash scripts/test-core.sh      # 低负载窗口内运行，编译原 Foundation + adapter 测试与 CLI
```

原 Mac 已交付 `folio` CLI；开发 CLI `CLI/main.swift` 用同一 DocumentWorkspace，可对明确指定的隔离状态执行 import、inspect、new、write、save、export、reload，JSON 输出，禁止指向正在运行 App 的状态。测试编译后验证 `--help`；不安装第二套全局命令。

`-folio-demo` 打开 `Fixtures/demo.md`，内容虚构，恢复状态单独位于 `FolioMobile-Demo`；生产 `FolioMobile` 保持独立。正式品牌图标复用原 Folio icns 最大图，Vision 分层沿总部转换能力，无新占位设计。

## 当前验证边界

代码已落地；静态接线、实际生成设备族和注入 JS 加载代次标记测试通过。2026-10-03 03:15:37—03:15:50，在 Chapter 全局锁内真实重编并运行 `scripts/test-core.sh`，exit0：并发编辑器、恢复与权限、图片读取竞态及系统别名的新 CoreTests 全部通过，开发 CLI 编译及 `--help` 也通过。测试前后 `monitor_inputs.bindings.code` 均为 `03f7ed6bdb4466a5e3eb82d944d2a446cbde6d2a0ca8ea6a0d3d9e0c4aed5fae`。三条移动线仍未有实际资源、Files 文件提供方/目录授权、多窗口 WebKit、系统冷启动打开、保存/另存为交互、键盘/窄屏/横屏或 Vision 画面证据；不表示已安装、上架或完整交付。

跨根唯一源以 `sop.source_root: ../..` 和族根相对 glob 写入 `project.yaml` 的 source，组件沿用族根 Git 仓。共享 owner 已补 sim_lane 家族布局冻结与仓外输入映射；`FOLIO_FAMILY_ROOT` 由既有接口重定向冻结家族根，静态副本输入证明由 native owner 核验。修复后 input 摘要会变化，真实构建 receipt 与资源验收须重新绑定最新输入，不复用旧哈希。launch 薄入口由 Chapter 提供原生验收上下文后调用同一 builtin，measure 薄入口调用总部 platform_measure；本 agent 未运行这些实际平台动作。

资源预算为 App 进程内存 150 MB、空闲 CPU 0.5%、模拟器包 12 MB、iPhone/iPad 冷启动 1.5 秒、Vision 2 秒；均为目标，未测量。WebKit 辅助进程在资源报告单列并计入合计。

图片读取竞态的新增 CoreTests 在同一个 production reader 的默认空 checkpoint 中执行真实文件系统操作：打开父目录后 rename+symlink 指向授权范围外、叶子/授权根换链、FIFO、首块后 ftruncate 增长到上限内或超过上限、初始大小恰好达到上限。真实重跑还验证合法 `/tmp`、`/var` 系统别名与用户链接拒绝：只规范经 lstat 核实 root 所有、且目标正确的 `/var`、`/tmp`、`/etc`，不会任意解析用户链接。该次本机日志 `/tmp/folio-core-sweep-20261003-alias-fix1.log`，SHA256 `ba6fb8b66ea8a8874477d43eb376bf3a86eca68b0a750dbdf2dc77a00775323e`；原 ENOTDIR 失败日志保留，使用本次新证据，未改断言来掩盖失败。
