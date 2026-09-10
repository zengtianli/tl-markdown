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
