# Folio 接管 Markdown 索引与目录图谱 · 第一期完成（2026-09-29 03:1x）

需求卡：`~/Apps/chapter/requests/folio-owns-md-index.md`。本轮授权：实现第一期、固定验收、本地提交、按既有回执路径装机；不推送、不发布、不部署。

## 结果

- 已装 **1.2.0 (49)**，`verify-install.py` 回读 receipt 匹配；`~/.local/bin/folio` → App 内命令。app_sop 五项固定验收（cli_entry、functionality、recovery、privacy、native_ui）在 (49) 上全部 passed；`scripts/test.sh --core-only` 通过。
- 私有对账（md-index indexer 的 `sop.accept.functionality`，app_sop 实跑 passed）：Python 固定基线与 Folio 各 4624 篇，路径集合一致，六词 FTS/转义 LIKE 计数一致，私密案卷目录 0 篇。
- 调用方回读均成功：`kb.py search 生态流量`、`md_index.py files RAG --repo hydro-assistant --limit 5`、`mdgraph --help`/探针生成、`folio graph ~/Apps --launcher`、`graph.py status`（8791 ready，未重启）。
- 迁移：md_index.py 转发（indexer `c3afe98`）、atlas/workspace 技能（cc-home `1ed714a`，codex_sync --check PASS）、mdgraph pipx 卸载并换成转发脚本、`~/Apps/知识图谱.command` 重生成、导航（Apps `64a6bdc`，configs `5bae431`）、旧库移到 `~/.Trash/folio-md-index-20260928/`。细节与回滚见 `~/Apps/md-index/indexer/handoffs/folio-migration.md`。

## 本轮 Folio 源码修正

- 图谱配置新增 `restricted_substrings`（对齐旧图谱按名称片段排除的规则，私有值只在本机 index.json）；同树对比 Folio 图谱相对旧 Python 图谱多 0 条路径。
- 增量索引：原实现每次写入都对 280 MB 库跑 `quick_check`，且任一改动就整表 FTS rebuild。现只有 `--full` 做 quick_check（增量遇页损坏自动退为全量并归档坏库）；改动按行维护外部内容 FTS5，仅 `--full`/首次接管旧库整表 rebuild。测试加 FTS5 `integrity-check`，反向验证能抓到漏删旧词。
- 遍历：排除规则展开结果缓存（只有 `~` 规则读环境变量），只对根目录核软链祖先。
- `build-cli.sh` 成功签名时不再把含本机路径的 codesign 提示写进验收日志。

## 性能（perf/lightweight.json 的 `index_cli`，空闲门前后均通过，测于 (48)，(49) 仅改签名输出）

CLI 313 KB（预算 2 MB）。全量：Folio 11.4 s 墙钟 / 10.6 s CPU / 165 MB，同时段 Python 19.4 s / 18.5 s / 71 MB（本轮机器噪声大，前一轮 Python 9.8 s）。无变化增量中位 3.9 s / 52 MB（修前 5.8 s / 156 MB；单独实测 2.6–3.1 s）。搜索「水库」30 ms vs Python 98 ms，「汛限水位」91 ms vs 113 ms。峰值 RSS 高于 Python 约 2.3 倍（全量），可作后续优化方向。

## 注意

- functionality/recovery/privacy/native_ui/cli_entry 证据与 build-receipt 已随本轮提交；Chapter 页面/图标/播放证据和 `perf/delivery-evidence.json` 仍未跟踪、未提交。
- 本轮未推送；公开仓 main 领先远端的提交需下次推送前再做一次隐私扫描（`git diff origin/main` 按 privacy 验收脚本里的禁用字符串清单检查）。
- 8791 常驻图谱进程下次重启才加载新版 md_index（范围函数未变）。

## 需要本人

- 打开 Folio 侧栏「搜索」，分别搜一个两字词和一个长词，确认点结果跳到对应行（本机索引已建好，无需再配置）。
- installed_icon 仍由 Chapter 出确认按钮。

## 接手

```sh
cd ~/Apps/folio
python3 scripts/verify-install.py                      # 已是当前构建会跳过
python3 scripts/measure-index.py                       # 空闲门通过才写 index_cli
~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py accept --app md-index --check functionality --json
```
