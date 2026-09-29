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
