# Chapter 授权推送、装机与发行准备（2026-09-28 上午）

本轮用户明确授予本产品装机、发版、推送和部署权限；早间 `chapter-acceptance-20260928.md` 的“禁止”仅描述上一轮，不能用来阻止本轮已授权动作。公开范围不变，未修改共享模块。已有未跟踪的 Chapter 页面/图标/播放证据和 `perf/delivery-evidence.json` 不提交；总表只由 app_sop 写入。

## 已完成

- 回读远端后确认本地原先领先 5 项提交，全部是本组件；主 agent 已推送并回读 GitHub main。新增装机脚本与双语说明在 `df33fe3` 提交并推送，后续本轮收尾提交只补证据与交接。
- 推送触发检查：GitHub Actions workflows、webhook、main check-runs、deployments 和 GitHub Releases 均为空；本仓无 ci_scripts / Xcode Cloud 配置。ASC 官方 API 按 `cyou.tianli.TLMarkdown` 过滤返回空、无后续页。pre-push 只有 Git LFS。未发现推送触发构建/部署；现有官网仍沿显式 products-only 白名单部署。共享 app-sop 每小时及 /Applications 变化触发观察，未改它的配置。
- 安装入口 `python3 scripts/verify-install.py` 复用既有 `build.sh --install`，由 Chapter build-receipt 包裹真实构建。重复调用已验证会按有效源码回执直接跳过，不重复装机。
- 隔离文件打开测试现在使用与生产可执行文件一致的 UUID 副本，独立 bundle ID / 状态目录，移除文档类型注册，FOLIO_BACKGROUND + LSUIElement + open -g -j；冷、热、多文件、Unicode/空格、两种扩展名和重复打开均实跑通过。原来的生产 MainEditorTests 也通过，未删安装门。
- 已装 **1.1.0 (40)**，bundle ID 仍为 `cyou.tianli.TLMarkdown`。可执行文件 SHA256 `0dba8977ba666307dd1f62dfd713192dbaf15ddc1860907a891753b605f9eecc`，图标 SHA256 `a51366356ae2bacab1d7e3cdc82132b3b70d90daede6da0f16d3c038dea77693`。独立回读确认可执行文件、版本、图标和当前源码与 `perf/build-receipt.json` 一致；旧 .app 已按原入口移到废纸篓备份，用户数据未迁移。开始装机时没有运行中的安装版 Folio；未启动装机版、未抢输入。
- 装机导致输入绑定变化后，主 agent 统一运行 app_sop 的 functionality / recovery / privacy / native_ui 四项，全部 passed；再只读核验绑定仍有效。media_playback 沿 Chapter 本轮已通过证据复用，没有重跑；余下实际交付确认仅 installed_icon。
- 从真实安装版打包 `build/release-1.1.0/Folio-1.1.0-40-arm64.zip`：**2,811,244 字节**，SHA256 `ffcf9a6bda4eecdd0ad772bff2a9f205b1e44f2865a3ccf00b6b80e901e87146`。包与解压签名、系统运行依赖和随包资源验证通过；仍是原有 ad-hoc、未公证分发方式，未新建 App Store 或 GitHub Release 通路。
- 已准备实际 1.1.0 (40) 的隔离录制副本，位置由 `build/demo-1.1.0.json` 记录，尚未启动或录制；发行说明在 `docs/releases/1.1.0.md`。
- `app_sop audit --app folio-mac --json` 回读官网页面、图标、README、公共源码和 build-receipt 均通过；官网发布清单仍为 **1.0.1 (27)**。本轮没有部署旧包或伪造新版本上线。

## 受阻：正式发行与部署

现有发行是官网 ZIP（`project.yaml` 的 `sop.release=build/site/release.json`），GitHub 尚无 Release。不能通过另开分发通路、改版本数字或 `--preview` 绕过已有发行门。

- `perf/lightweight.json` 的实测仍属于 1.0.1 (27)，脚本要求性能版本与 ZIP 大小和发行包准确对应。门检查时用户空闲 411 秒，1 分钟负载 40.3 / 10 核，未满足 600 秒/低负载条件；按本轮快节奏不长时间等待采样。
- 视频录于 1.0 (14)，只登记复用到 1.0.1；1.1.0 已增加搜索侧栏。对新包执行正式站构建得到 `Site not built: Recording and release versions differ`，未生成站点候选，也未覆盖旧站。需要新版实际素材或有实际验证支持的有限复用；不能仅凭源码描述补通过。
- 所以 Chapter 的装机/发行版本差异仍会显示；本机已是当前源码，不应为了消除提示降回 1.0.1。

进入本仓后，待空闲门满足再做性能候选（不直接改已有实测事实）：

```sh
~/Dev/.venv/bin/python -c 'import sys; sys.path.insert(0,"/Users/tianli/Apps/chapter/engine"); import app_sop; ok,why=app_sop.steady(); print(why); sys.exit(0 if ok else 78)' && \
python3 scripts/measure-lightweight.py --zip build/release-1.1.0/Folio-1.1.0-40-arm64.zip --raw build/perf-1.1.0-40.json
```

录制入口可重新幂等准备（只准备，不抢输入）：

```sh
python3 scripts/prepare-demo.py --app /Applications/Folio.app
```

按 `docs/demo/录制说明.md` 使用隔离副本完成真实镜头，并将新实测和媒体绑定本次包后，继续：

```sh
python3 scripts/build-site.py --release build/release-1.1.0/release.json --out build/site
bash ~/Apps/apps-portal/site/deploy.sh --products-only folio-mac --dry-run
# 审读上一步实际计划，再填它输出的计划路径；只部署本组件。
bash ~/Apps/apps-portal/site/deploy.sh --products-only folio-mac --deploy --plan <实际计划路径>
~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py run --app folio-mac --check-only --json
```

## 受阻：SOP 核心测试登记

装机闸门和四项固定验收实际已通过；`app_sop run --test-only` 返回 75 / busy，其他任务正在使用全局锁，未停止其他进程或绕过锁。待锁释放后直接执行：

```sh
~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py run --app folio-mac --test-only --now --json
```

## 需要本人

只有 installed_icon 仍由本人在 Chapter 确认。已备好当前安装版、图标哈希、离屏 UI 截图和来源回执，不替本人填写 Dock/Finder 图标通过。

## 本地证据

- `build/install-verification.log`：真实构建、MainEditor、LaunchServices 和装机签名/版本输出。
- `build/install-readback.json` / `perf/build-receipt.json`：装机与当前源绑定。
- `build/accept-installed-1.1.0.json` / `perf/acceptance/`：四项 app_sop 结果及原件。
- `build/package-1.1.0.log` / `build/release-1.1.0/release.json`：候选包及校验值。
- `build/site-candidate-check.log` / `build/measurement-gate.json`：发行前置阻塞的实际结果。
- `build/sop-install-audit.json`：最后只读全维度核验，不能把其旧版性能/媒体通过误称为新版实测。
