# Chapter 维护：接手 md-index 并入、装机 1.2.0 (44) 与命令行验收（2026-09-29 凌晨）

## 起点

- 工作树里有 `folio-owns-md-index` 需求卡（`~/Apps/chapter/requests/folio-owns-md-index.md`）的未提交实现：Swift `IndexEngine`/`GraphEngine`、`CLI/main.swift`、设置页索引与「生成目录图谱…」、`scripts/accept/cli.sh` 等。来源是 Codex 线程 `01a0e3f9-1584`（09-28 01:45 起），09-29 01:15 停在“GUI 首版已接入……先完成不冲突的实现和对账”，之后无进程、无 claims。本轮验证后接手提交。
- 当时 `scripts/test.sh --core-only` 失败：GraphEngine 测试首次生成就报「目录或文件无法安全读取；不跟随软链」。

## 已完成

- **根因 1（已修）**：引擎用 `standardizedFileURL` 规范路径，Foundation 会把 `/private/var` 改写成 `/var` 软链，O_NOFOLLOW 逐级打开被拒、`skip_paths` 与扫描路径失配。改为 `URL.lexicalPath`（只处理 `.`/`..`，放在 `IndexEngine.swift` 供两个引擎共用）。核心测试全过：Index engine、Graph engine 27 项。提交 `a3abc24`（含接手的整张卡实现）。
- **根因 2（已修）**：装机后经 PATH 调用 `folio`，`argv[0]` 只是 `folio`，`--version` 回退成 `folio development`，`folio graph` 报「没有找到随 Folio 安装的图谱模板」（真实装机版复现）。改为 `_NSGetExecutablePath` 取真实位置（`FolioExecutable.url`）。`scripts/accept/cli.sh` 的 functionality 模式新增“装机布局 + PATH 调用 + 不带模板覆盖”的用例；旧代码实测输出 `folio development`，能被这条用例抓到。提交 `bdd7c12`。
- **装机**：`python3 scripts/verify-install.py` → ok，已装 **1.2.0 (44)**，`~/.local/bin/folio` → `/Applications/Folio.app/Contents/Resources/bin/folio`；receipt 回读“装机可执行文件、图标与当前构建输入均匹配”。装前没有运行中的 Folio；没有启动装机版。真实装机版 `folio --version` = `folio 1.2.0 (44)`，`folio graph <真实目录> -n` 生成成功（探针目录已删除）。
- **验收**：`app_sop accept --check cli_entry functionality recovery privacy native_ui` 五项全部 passed（证据由 app_sop 写入）。
- **候选包**：`build/release-1.2.0/Folio-1.2.0-44-arm64.zip`，3,098,738 字节，SHA256 `75395b76296d5169335c7c3805ecc9b94b42e52eb40ac2d95068b242eac8c180`；签名、随包资源、系统依赖检查通过，仍是 ad-hoc 未公证。发行说明 `docs/releases/1.2.0.md`。

## 注意

- `functionality/recovery/privacy` 的 `.log` 含本机路径（`build-cli.sh` 里 `codesign --force` 的 “replacing existing signature” 带绝对路径），公开仓远端原有版本没有，故这三项的 json/log 留本地不提交。下次源码本来就要改时，把 `build-cli.sh` 的这行 stderr 过滤掉（改它会改变构建输入、需要重装，所以本轮没动）。
- 需求卡第 4、8 步（私有对账、md_index.py 转发、技能/launcher/mdgraph 改接、旧库移走）在其他仓库，不属于本组件仓，本轮未做。

## 受阻

- **正式发行**：线上仍是 1.0.1 (27)。性能实测仍属 1.0.1，空闲/负载门本轮返回 `负载 11.2 ≥ 10`；演示原片录于 1.0 (14)，站点构建要求录制与发行版本一致。接手：

```sh
~/Dev/.venv/bin/python -c 'import os, sys; sys.path.insert(0, os.path.expanduser("~/Apps/chapter/engine")); import app_sop; ok,why=app_sop.steady(); print(why); sys.exit(0 if ok else 78)' && \
python3 scripts/measure-lightweight.py --zip build/release-1.2.0/Folio-1.2.0-44-arm64.zip --raw build/perf-1.2.0-44.json
python3 scripts/prepare-demo.py --app /Applications/Folio.app   # 然后按 docs/demo/录制说明.md 录制
python3 scripts/build-site.py --release build/release-1.2.0/release.json --out build/site
bash ~/Apps/apps-portal/site/deploy.sh --products-only folio-mac --dry-run
```

- **SOP 核心测试登记 / 只读重检**：`app_sop run --check-only` 返回 busy（另一轮 app_sop 持锁），未绕过。锁释放后：`~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py run --app folio-mac --test-only --now --json`。

## 需要本人

- installed_icon：当前装机版 1.2.0 (44)，图标 SHA256 仍为 `a51366356ae2bacab1d7e3cdc82132b3b70d90daede6da0f16d3c038dea77693`，在 Chapter 确认。
- 需求卡要求的一键确认：在 Folio 侧栏「搜索」分别搜两字词和长词，确认点结果跳到对应行（需先在设置里添加索引文件夹并更新索引）。
