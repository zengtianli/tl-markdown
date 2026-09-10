# Folio 产品线与官网 · 2026-09-10

用户批准 Clip、Folio、DocKit、PhotoDesk 产品线与完整 product-homepage；Folio 私有源码不公开，二进制与经过核对的网站资产可分发。主线程统一实机截图录屏、GitHub 发行与站群部署。此仓没有操作共享 configs / stations。

## 已落实

- 生产文件读写和 store 共 27 个断言通过：原文保真、自动保存、外部修改冲突、另存为、草稿恢复、清空历史不删原文；未创建窗口、使用剪贴板或驱动浏览器。
- `build.sh --build-only` 不启动、安装或强退应用；保留既有完整 UI 验收入口，并在文档中明确它不能替代输入隔离要求。构建使用现有 Xcode 环境与 scrub_env；签名前去除可执行文件中的开发目录调试记录。
- 应用帮助菜单接产品主页。显式独立状态＋`FOLIO_BACKGROUND=1` 才抑制自动主窗口，后台 NSPanel 挂载相同的生产 ContentView；不能成为 key/main，普通启动保持原流程。已编译，子线程未启动该窗口，真实行为由主线程 CUA 核实。
- `scripts/package-release.py` 从签名 .app 生成 ZIP、release.json、SHA256SUMS；验证包内依赖资源、源码指纹、开发路径残留、ZIP 解压后的签名。无需 Node/Python/Homebrew 运行。
- `site/` 为独立新写的亮色页面：产品定位、下载、实机片段、逐步安装、首次打开、快捷键、冲突与保存状态、隐私和版本说明。仅参考 Unrevoke 的完成度和流程，没有复制 AGPL 页面源码。
- `scripts/build-site.py --out build/site` 仅消费实际发行清单与 `docs/demo/media/`；生成相对路径＋sha256＋bytes 的 `site-manifest.json` 白名单，禁止缺片占位发布。`--preview` 明确标记内部预览。版本、安装包文件名、大小和校验值都来自实际包。

## 录制与接线

1. 最后构建后运行 `python3 scripts/package-release.py`，正式媒体绑定该包内版本/构建号，而非后续纯网站文档提交数。
2. `python3 scripts/prepare-demo.py` 创建含合成 Markdown、独立状态、独立 bundle ID 和 LSEnvironment 的重签名演示副本，不启动它。副本去掉文件关联，保留实际可执行文件哈希供核对。主线程以 CUA background 入口使用返回路径。
3. 真实图片和三个片段按 `docs/demo/录制说明.md` 落 `docs/demo/media/`。原片留私有 `build/demo/`。确认真实保存结果可运行 `verify-demo.py <run>`。
4. 媒体齐后运行正式 build-site，主线程沿既有 `app-mac-folio.tianli.cyou` 发布白名单包。网页播放器最终需要真实播放、时间推进、Range/206、手机与桌面视觉回读。

## 仍需真实完成

最终包的 CUA 主编辑/保存重开验收、隔离后台面板实查、真实截图与视频、网页视觉与实际下载验收均由主线程处理，不能把子线程构建通过当作已完成。

本机仅查到 Apple Development 证书，没有 Developer ID Application；当前发行包是 adhoc、未公证。页面已按实际状态写明首次打开与错误处理，依据 Apple 官方支持文档 `https://support.apple.com/zh-cn/102445`，未加入 xattr / 关闭安全机制命令。新 Mac 上的下载首开仍须实测；本机解压签名检查不是 Gatekeeper 首开成功的证据。

## 实录阻断排查与修复

主线程在 build 12 隔离副本发现 Mermaid 长时间停在“正在绘制图表…”；录制副本随后正常退出。用户明确未主动关闭。只保留已确认有效的 open 原片；edit / replace 原片未完成保存，不得发布。

- Mermaid 资源确在签名包内，编辑器通过 file URL 加载；CSP 的 connect-src 为 none。旧实现只有 IntersectionObserver 相交时才启动绘制，加载和绘制都没有期限。修改为 CodeMirror 创建 widget 后的微任务立即渲染，本地组件加载 10 秒、绘制 15 秒超时会回到可点击修改的源码和明确错误；widget 销毁后不回写。构建检查 Mermaid 输出没有运行时外部 import。
- `cd Editor && npm run test:diagram` 的 6 项回归验证后台可见性回调缺席、绘制未完成、widget 销毁、组件失败后重试、组件超时及真实 Mermaid bundle 在没有网络 API 的 Node VM 中初始化。**VM 不具备 WebKit SVG 布局能力，这些不等于实际图表视觉验证**；新最终包仍需主线程用 CUA 查看四节点流程图。
- app 专属日志：PID 35454 在 16:48:22.213 被 AppKit 标记 `_kLSApplicationWouldBeTerminatedByTALKey=1`，16:48:56.882 调用 terminate，flush 后 reply YES，正常退出；其他两次也走正常终止路径。副本 LSEnvironment 无 `TL_MARKDOWN_BENCHMARK`，源码后台路径不调用 benchmark。证据支持自动终止资格与 NSPanel / 被抑制的 SwiftUI Window 生命周期有关，**没有直接记录退出发起方，不能把假设写成已证实根因**。
- 仅显式隔离后台模式，在 willFinishLaunching 禁自动及突然终止；录制副本 Info.plist 也写明不支持二者。普通启动无变化，主动 Quit 仍 flush 并退出；隔离副本若再收到退出，会记录当前 AppleEvent 类/ID 与调用栈以定位发起链。未在子线程启动 GUI 验证保活效果。
- 修改后无窗口的生产 I/O / store 27 项与 build-only 编译通过；正式包的实机保存、图表和持续存活验收仍待主线程完成。

### 17:30 实证与最终修复

主线程在 build 13 已肉眼确认四节点 SVG 完整显示，无需额外等待。自动/突然终止 opt-out 没有解决录屏收尾退出：40 秒录制自然结束后，诊断副本仍退出。统一日志把 NSLog 整条脱敏为 `<private>`，因此改为仅在显式隔离状态目录写 `termination.json`（0600，仅时间、进程、事件 class/ID、发送方 PID/bundle ID 和调用栈，不记事件载荷或文档）。诊断文件表明 eventClass、eventID、senderPID 都为空，调用栈第 11 帧确为 AppKit `_scheduleCheckForTerminateAfterLastWindowClosed`，随后 timer 调用 `terminate`。这是最后窗口关闭检查路径，不能再归因为未阻止系统资源回收，也无证据指向用户或外部自动化退出。

最终给 AppDelegate 实现 `applicationShouldTerminateAfterLastWindowClosed`：隔离 NSPanel 模式返回 false；普通单个 SwiftUI `Window` 继续返回 true，维持原先关闭窗口即退出的行为。主动 Quit 仍照常 flush；独立诊断合理保留。未换录屏工具。主线程需要用最终新包再次执行原来的定时窗口录制，确认收尾后进程持续存活，再完整录制最终版本的三个片段。
