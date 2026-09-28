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

## 受阻（auto）

- 正式发版：`perf/lightweight.json` 测的是 (49) 包，站点构建要求与 (51) 包逐字节对应；(51) 重测时空闲门失败（负载 23→67，其他会话批量任务）。线上 `/release.json` 仍为 1.0.1 (27)。空闲后：

```sh
cd ~/Apps/folio
~/Dev/.venv/bin/python -c 'import os,sys; sys.path.insert(0,os.path.expanduser("~/Apps/chapter/engine")); import app_sop; ok,why=app_sop.steady(); print(why); sys.exit(0 if ok else 78)' && \
python3 scripts/measure-lightweight.py --zip build/release-1.2.0/Folio-1.2.0-51-arm64.zip --raw build/perf-1.2.0-51.json && \
python3 scripts/release/fold-lightweight.py --raw build/perf-1.2.0-51.json && \
python3 scripts/build-site.py --release build/release-1.2.0/release.json --out build/site && \
bash ~/Apps/apps-portal/site/deploy.sh --products-only folio-mac --dry-run
# 审读 dry-run 计划后：bash ~/Apps/apps-portal/site/deploy.sh --products-only folio-mac --deploy --plan <计划路径>
# 回读：curl -s https://app-mac-folio.tianli.cyou/release.json
```

若期间又有提交改动 `scripts/*.py` 等构建输入，需先 `python3 scripts/verify-install.py` 重装、重新打包，并把 `capture.json` 的 reused_for 键与哈希改到新构建号（reason/tests 可沿用，源码指纹不变时）。

## 需要本人

- installed_icon：装机 1.2.0 (51)，图标与之前相同，由 Chapter 出确认按钮。
