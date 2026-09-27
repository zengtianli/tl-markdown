# Chapter 固定验收与本地页面修复（2026-09-28）

本轮只改 Folio 仓库。主 agent 集成与提交，子 agents 分别负责功能、恢复、隐私、App 内离屏自检和页面数字。未推送、发版、装机、部署；未修改共享模块。开工时已有的 `perf/acceptance/` 四项页面/图标证据与 `perf/delivery-evidence.json` 由 Chapter 生成，保留其内容，不随本轮提交。证据总表仅通过 app_sop 更新。

## 实现与验证入口

最终验收：app_sop `accept` 四项全部 `passed`，证据及日志 SHA256 已独立核对，当前产品输入绑定仍有效。真实构建为 **1.1.0 (38)**，未安装；四张截图已逐图核对，源码与重载后文字正确。`bash scripts/test.sh --core-only` 退出 0（原有文件、检索、Store、Watcher 和两项结构回归）。固定验收输出见 `perf/acceptance/{functionality,recovery,privacy,native_ui}.json`，完整核心日志在 `build/accept-core-tests.log`。

- `scripts/accept/_common.sh`：每次建立独立合成状态，复用 Xcode 选择器和真实生产 Swift 文件。
- functionality：真实打开 Unicode/空格路径、BOM/CRLF、自动保存、后台标签隔离、合成 FTS5/短词检索与命中打开、会话恢复。
- recovery：外部冲突不覆盖、重载保留本地草稿、会话和关闭草稿恢复、只读保存失败、损坏会话保留及恢复记录写失败提示。未操作 dirty-close 的人工确认框。
- privacy：实际验证 session 0700/0600、隔离状态目录、只读索引、图片目录拒绝、WebKit 临时数据存储、程序导航限制及 mdasset 文件类型/文档身份边界。无外网请求，不是全进程抓包审计。
- native_ui：本仓 App 的 `--ui-self-test`，真实 ContentView / EditorSurface 永不显示或激活，直接调用源码切换、新建/选择、重载、关闭，检查生产 WebKit 状态、DOM、CSS 和截图。原生外壳与独立 WebKit 截图分列，避免把异步合成器旧画面当成动作结果。未覆盖系统文件选择框、Dock/Finder 和安装版 LaunchServices。
- `project.yaml` 已登记四项；双语 README 记录入口与覆盖边界。
- `scripts/build-site.py` 改正 MiB/MB 换算和 CPU 精度；本地 `build/site` 保留已发布 **1.0.1 (27)**，显示 **112.1 MB / 0.02%**，主进程 **47.2 MB**。测量日期仍为 2026-09-26，没有补造新测量。Chapter `numbers_on_page` 返回空缺项，21 个白名单文件的路径、大小和 SHA256 已核验。

```sh
# cd 进本仓库后复验；Chapter 写证据，不手写通过状态。
~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py accept --app folio-mac \
  --check functionality --check recovery --check privacy --check native_ui --json
# 与 accept 顺序运行，app_sop 有全局互斥锁。
~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py run --app folio-mac --test-only --now --json
~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py run --app folio-mac --check-only --json
```

## 需要本人决定及现成材料

- 是否发布含全部笔记检索的 1.1.0：改动摘要见 `handoffs/note-search-merge.md`；本轮新增自检，未改普通启动流程。构建入口 `bash build.sh --build-only`；本地打包入口 `python3 scripts/package-release.py`，不会上传。新版本的性能与演示证据尚未完成，不能把 1.0.1 数据改标成 1.1.0。
- installed_icon 仍由本人在 Chapter 确认。现有图标源 `icon/AppIcon.png` / `icon/AppIcon.icns` 保留；本轮 UI 截图不证明实际 Dock/Finder 图标。

## 受阻与接手

以下命令仅供本人决定后执行，本轮未执行其中的外部写入。

1. **线上页面**：本地包已修，禁止部署使线上旧数字仍待更新。先 `python3 scripts/build-site.py --out build/site`，再 `bash ~/Apps/apps-portal/site/deploy.sh --products-only folio-mac --dry-run`；阅读输出计划后执行 `bash ~/Apps/apps-portal/site/deploy.sh --products-only folio-mac --deploy --plan <上一步输出的计划路径>`。最后运行上面的 `--check-only` 线上回读命令。
2. **README 推送**：开工时领先远端的四项依次为 `6893662` 发行/源码政策、`37d4857` 双语名称、`5c8251b` 全部笔记检索、`3e5853a` 检索交接；本轮还增加一项本地提交。没有仓内 `.github` 工作流。禁止 push，故只核对未推送。接手先 `git log --oneline '@{upstream}..HEAD'` 与 `git diff '@{upstream}..HEAD' --stat`，确认后 `git push origin main`。
3. **装机与发布版不一致**：现场核对 `/Applications/Folio.app` 为 **1.1.0 (37)**，发布包为 **1.0.1 (27)**，禁止装机所以未回退。现有 `build/release/Folio-1.0.1-27-arm64.zip` 的 SHA256 已核为 `4c1bc14cca3a2f5b8c1d74a597c879f394d8a6ac22694c6c9b77eebe1c61aa4e`。若确定回到公开版本，退出正在用的 Folio 后，先运行下方命令核包和暂存；旧安装备份后再复制。回退会暂时失去 1.1.0 新增的笔记检索。

```sh
shasum -a 256 build/release/Folio-1.0.1-27-arm64.zip
ditto -x -k build/release/Folio-1.0.1-27-arm64.zip build/install-release-1.0.1
codesign --verify --deep --strict build/install-release-1.0.1/Folio.app
# 本人确认安装时执行；仅备份程序，不删除用户文稿或状态。
FOLIO_PREVIOUS="$HOME/.Trash/folio-before-release-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$FOLIO_PREVIOUS"
mv /Applications/Folio.app "$FOLIO_PREVIOUS/"
ditto build/install-release-1.0.1/Folio.app /Applications/Folio.app
```

4. **1.1.0 的性能/演示输入已变**：保留旧版真实数据，本轮按“快、小改”要求不做长空闲采样或重录。接手先 `~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py run --app folio-mac --stage perf --stage media --check-only --json` 看当前差项；新版本发布前按 `scripts/measure-lightweight.py --help` 与 `docs/demo/录制说明.md`，在满足空闲门后采样并更新真实素材。不要用 `--now` 绕过性能空闲门。
5. **Chapter 核心测试登记被占用**：直接核心回归已通过，但 `run --test-only` 返回 75 / `busy`。现场锁由另一产品的 app_sop 测试持有，未停止它或绕过锁。待该任务完成，在本仓运行 `~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py run --app folio-mac --test-only --now --json` 登记，再 `run --app folio-mac --check-only --json` 汇总。最终只读校验四项新验收绑定均有效；余下 delivery 项是 `installed_icon` 与随 UI 输入变化待重检的 `media_playback`，后者沿用户已安排的 Chapter 只读重检，不在本轮重复执行。
