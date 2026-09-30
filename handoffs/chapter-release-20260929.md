# Chapter 维护：1.2.0 (51) 装机、发行准备与推送（2026-09-29 03:1x–03:4x）

## 已完成

- media_playback：03:08 失败为高负载下无界面浏览器 20 秒内未推进播放（readyState 4、currentTime 0）；负载降到约 4 后同一线上页面重跑 passed（3 段实际播放）。页面未改。Chapter 自身验收器在高负载下易超时，归 Chapter。
- cli_entry 重跑 passed。装机 1.2.0 (51)（`verify-install.py` 回读 receipt 匹配）；五项固定验收（cli_entry、functionality、recovery、privacy、native_ui）在 (51) 上全部 passed。
- 发行准备（未上线）：
  - 候选包 `build/release-1.2.0/Folio-1.2.0-51-arm64.zip`：3,101,287 字节，SHA256 `2e0f1650311a27a137743abc0f40a4c9f146a2eeebce23e695d323aab3974b12`，源码指纹 `5f28a536…`（与 49 相同）。
  - 空闲门通过时实测了 (49) 发行包：下载 3.10 MB、解压 7.56 MB（较 1.0.1 +0.84 MB，预算 3 MB）、空闲 108 MiB / CPU 0.03%、启动 7 次中位 329 ms；已写入 `perf/lightweight.json`（1.0.1 转入 compare_previous_release）。
  - 演示录制：子 agent 抽帧对照 1.2.0 离屏界面，三段操作在 1.2.0 原样成立，差异仅侧栏标签（旧「侧栏 最近文件｜大纲」→「最近｜大纲｜搜索」）及新功能未出镜；`capture.json` 登记 `reused_for["1.2.0 (51)"]`（reason、tests、hero_note）。
  - 主页新增 1.2 功能节（全部笔记搜索、索引文件夹、目录图谱、folio 命令）与 ⌘⇧F；头图说明在复用时标注录制版本；版本记录页补 1.1.0/1.2.0。
  - 发现并修正：下载版不会自动建立 `~/.local/bin/folio`（只有源码 `build.sh --install` 会建），主页、docs/cli.md、README、发行说明改为说明手动链接。
  - 新增 `scripts/release/fold-lightweight.py`（放子目录，不是装机回执的构建输入）。
- 推送：8 个提交推到 GitHub main，回读远端 = 本地 `847db74`；推送前按禁用字符串清单扫描干净；仓库无 workflows / ci_scripts / webhook，Actions runs 0，pre-push 只有 Git LFS，未触发构建或部署。

## 05:0x 发版完成（接续上面的受阻项）

- 空闲门通过（空闲约 3.3 小时、负载 4.2→4.9，前后各一次）后实测 (51) 发行包：下载 3,101,287 字节、解压 7,561,216 字节、空闲 118 MiB（页面按十进制 123.7 MB）/ CPU 约 0%、启动 7 次中位 310 ms；`scripts/release/fold-lightweight.py` 并入 `perf/lightweight.json`（(49) 转入 measurement_history，上一发行版对比仍为 1.0.1 (27)）。
- README / README_EN 资源块由共享 `~/Apps/apps-portal/site/perf_block.py` 重写；发行说明数字同步。
- 正式站构建 `build-site.py --release build/release-1.2.0/release.json` 通过（非 preview）；`deploy.sh --products-only folio-mac` 先 dry-run 审读计划（只写 `/var/www/apps-products/mac/folio`，含备份与 rollback.sh），再 `--deploy --plan …/20260928T210556Z-24bad34d/plan.json`，服务器逐文件哈希校验 OK。
- 线上回读：`/release.json` = 1.2.0 (51)，下载包 SHA256 `2e0f1650…` 与本地一致；本机装机 (51) 源码指纹 `5f28a536…` 与发行一致。app_sop homepage_desktop、homepage_mobile、media_playback、icon_review 在线上页面 passed。
- 仍为 ad-hoc 签名、未公证的官网 ZIP，未新开 GitHub Release / App Store 通路。

## 需要本人

- installed_icon：装机 1.2.0 (51)，图标与之前相同，由 Chapter 出确认按钮。

## 09:5x 主页包补 facts.json 并重新部署

- 他人会话提交 `9cb0ea1`：build-site 用 `~/Apps/apps-portal/site/product_facts.py` 从 perf/lightweight.json 与本次发行记录生成 `facts.json`，供门户卡片与 Chapter 读取。线上包原先没有该文件，apps-site 因此受阻。
- 按发行 1.2.0 (51) 重建正式站（非 preview），`facts.json` 绑定 build 51、下载 3,101,287 字节、空闲 124 MB（十进制）/ 0% / 310 ms；dry-run 计划只写 `/var/www/apps-products/mac/folio`（23 个文件），部署后服务器哈希逐项 OK；线上 `facts.json` 与本地逐字节一致，`/release.json` 仍为 1.2.0 (51)。
- 注意：`9cb0ea1` 改了 `scripts/build-site.py`（装机回执的构建输入），本轮 `verify-install.py` 因回执失效按既有入口重装为 1.2.0 (57)；源码指纹 `5f28a536…` 与发行 (51) 相同，应用代码无差别，只是构建号不同。重装后 cli_entry、functionality、recovery、privacy、native_ui、homepage_desktop 均 passed；homepage_mobile 首次在负载约 26 时探针未回报，重跑 passed。
- 若 Chapter 要求装机与发行构建号一致，需在空闲门通过时按上文发版链路对 (57) 重新打包、实测、改 capture.json 的 reused_for 键并部署。

## 23:2x–23:4x 装机 (57) 与发行 (51) 对齐：已备好，等空闲门

- 回读：本机已是当前构建 1.2.0 (57)（receipt 匹配，跳过重装）；线上 `/release.json` 1.2.0 (51)。两者源码指纹同为 `5f28a536…`，差别只有构建号。
- 已按既有入口从装机版打包 `build/release-1.2.0/Folio-1.2.0-57-arm64.zip`：3,101,286 字节，SHA256 `fac92aea33131021e1197f8e4fd44de95a1c19d3d5fadace76f0acfffe178990`，包签名/资源/系统依赖检查通过；(51) 包移到 `build/release-1.2.0-51/`（线上仍是它）。
- `docs/demo/media/capture.json` 已登记 `reused_for["1.2.0 (57)"]`（理由同 51，tests 写明 (57) 上通过的五项验收）。
- 站点构建要求 `perf/lightweight.json` 测的正是本次发行包（版本与字节数），不能把 (51) 的数字改标成 (57)；空闲门在 15 分钟内一直不通过（用户持续操作、负载 11.4），未测量、未部署。空闲后一条链接手：

```sh
cd ~/Apps/folio
~/Dev/.venv/bin/python -c 'import os,sys; sys.path.insert(0,os.path.expanduser("~/Apps/chapter/engine")); import app_sop; ok,why=app_sop.steady(); print(why); sys.exit(0 if ok else 78)' && \
python3 scripts/measure-lightweight.py --zip build/release-1.2.0/Folio-1.2.0-57-arm64.zip --raw build/perf-1.2.0-57.json && \
python3 scripts/release/fold-lightweight.py --raw build/perf-1.2.0-57.json && \
~/Dev/.venv/bin/python ~/Apps/apps-portal/site/perf_block.py "$PWD" && \
python3 scripts/build-site.py --release build/release-1.2.0/release.json --out build/site && \
bash ~/Apps/apps-portal/site/deploy.sh --products-only folio-mac --dry-run
# 审读计划后：bash ~/Apps/apps-portal/site/deploy.sh --products-only folio-mac --deploy --plan <计划路径>
# 回读：curl -s https://app-mac-folio.tianli.cyou/release.json ；curl -s https://app-mac-folio.tianli.cyou/facts.json
```

若之后又有提交改动构建输入（`scripts/*.py`、Sources 等），先 `python3 scripts/verify-install.py` 重装并重新打包，再把 capture.json 的 reused_for 键改到新构建号。

## 09-30 09:1x 只读复核（本人在用机器，未构建、未测量、未装机、未发布）

- 线上 `/release.json`、`facts.json`、`site-manifest.json` 均为 1.2.0 (51)，preview=false；本地 `build/site/release.json`（Chapter 的 `sop.release`）也是 51。
- 备好的 `build/release-1.2.0/Folio-1.2.0-57-arm64.zip` SHA256 `fac92aea…` 与 SHA256SUMS 一致；解包后与 `/Applications/Folio.app` 做 `diff -rq`，整棵树无差异——本机装的就是这个包。
- 51 包与 57 包逐文件比：只差 `Info.plist` 的 CFBundleVersion、`Resources/FolioBuild.json`（build、source_commit、built_at）、`_CodeSignature` 和主可执行文件；主可执行文件去掉签名后 SHA256 相同（`b2741b8d…`），`bin/folio` 相同（`584198f9…`）。即应用内容一样，差别只是构建号与随之变化的签名。
- `perf/lightweight.json` 仍是 1.2.0 (51) 的实测；`scripts/build-site.py` 第 77–79 行要求版本和下载字节数都等于本次发行包（57 为 3,101,286 字节），所以发布 57 必须先在空闲门下实测 57，属于重任务。
- 装机图标：`AppIcon-a51366356ae2baca.icns` 与 `icon/AppIcon.icns` 逐字节相同（`a5136635…`）；iconutil 解出的 10 个尺寸与源 icns 逐像素相同，1024 图与 `icon/AppIcon.png` 逐像素相同；app_sop 回读 installed_icon_matches=True。`perf/delivery-evidence.json` 里从来没有 installed_icon 记录，只能本人看 Dock/Finder 后在 Chapter 点「图标没问题」。该证据绑定源图标与装机图标文件（文件名含内容哈希），发 57 或同图标重建都不会让它失效。
- Chapter 板上装机项的「装发布版」方向是反的：会把 57 降成 51，51 的可执行文件与回执不符，build-receipt 随即变 stale，再触发重建出更大的构建号。正确方向是把 57 发布出去。
- 反复出现的原因：装机回执的输入（`scripts/verify-install.py` 第 37–39 行）包含 `scripts/*.py`、`scripts/*.sh`。09-29 的 `9cb0ea1` 只改了不进 App 的 `scripts/build-site.py`，回执就失效了，于是重装，git-count 构建号从 51 变成 57，装机与发行不再一致，只能重新实测、重新发版。建议下次 Sources 等真正要改、本来就得重装时，在同一提交里把这两条收窄为 build.sh 实际调用的 `scripts/build-cli.sh`、`scripts/test.sh`、`scripts/package-release.py`、`scripts/test_file_open.py`、`scripts/install-cli.py`。这个文件本身也在回执输入里，单独改会立刻让回执失效，所以本轮没改。

空闲后发布 57（与上一节相同，只给 fold 补上 57 的测试说明）：

```sh
cd ~/Apps/folio
~/Dev/.venv/bin/python -c 'import os,sys; sys.path.insert(0,os.path.expanduser("~/Apps/chapter/engine")); import app_sop; ok,why=app_sop.steady(); print(why); sys.exit(0 if ok else 78)' && \
python3 scripts/measure-lightweight.py --zip build/release-1.2.0/Folio-1.2.0-57-arm64.zip --raw build/perf-1.2.0-57.json && \
python3 scripts/release/fold-lightweight.py --raw build/perf-1.2.0-57.json --tests "1.2.0 (57) 装机构建：build.sh --install 内 MainEditor WKWebView 与 LaunchServices 文件打开测试通过；app_sop 固定验收 functionality、recovery、privacy、native_ui（离屏 --ui-self-test）、cli_entry 均 passed，2026-09-29" && \
~/Dev/.venv/bin/python ~/Apps/apps-portal/site/perf_block.py "$PWD" && \
python3 scripts/build-site.py --release build/release-1.2.0/release.json --out build/site && \
bash ~/Apps/apps-portal/site/deploy.sh --products-only folio-mac --dry-run
# 审读计划后：bash ~/Apps/apps-portal/site/deploy.sh --products-only folio-mac --deploy --plan <计划路径>
# 回读：curl -s https://app-mac-folio.tianli.cyou/release.json ；curl -s https://app-mac-folio.tianli.cyou/facts.json
# 然后：~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py run --app folio-mac --check-only --retry --json
```
