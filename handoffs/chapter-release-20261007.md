# 发布 1.2.1 (128)（2026-10-07 晚，Chapter 授权的一次性发版）

## 结果

- 发布前：线上 `https://app-mac-folio.tianli.cyou/release.json` 为 1.2.0 (68)；本机装机 1.2.1 (128)，`verify-install.py` 回读 receipt 匹配（跳过重装，未重启 Folio，发版期间 Folio 没有在运行）。
- 发布后：线上 1.2.1 (128)。下载包 `Folio-1.2.1-128-arm64.zip` 3,643,010 字节，SHA256 `e2e3f477207a4b305f32abe2b3b1c98ade995f52d5ac51489bc6c9f7f6c2fa72`，源码指纹 `164b1e0f…`（源码提交 fe37ed1）。从线上重新下载后哈希一致，解压后 `codesign --verify --deep --strict` 通过，可执行文件与本机装机版逐字节相同。
- 签名等级不变：ad-hoc，未公证（`spctl` 评估为 rejected、无 stapled ticket，与以往各版相同；主页安装指南照旧说明首次打开方法）。没有新开 GitHub Release / App Store 渠道。
- `folio update check --json`：`state: up_to_date`，「当前已是此渠道最新版：1.2.1 (128)」。
- 线上 `facts.json`：1.2.1 (128)，`historical_reference: true`，卡片为「当前下载 3.6 MB · 历史实测 1.2.0 (68)（2026-10-03）：…」。
- 部署：`deploy.sh --products-only folio-mac` 先 dry-run 审读（只写 `/var/www/apps-products/mac/folio`，23 个文件，脚本自带服务器端备份与 rollback.sh），再 `--deploy --plan …/20261007T140139Z-97e77919/plan.json`，服务器逐文件哈希 OK。
- 换下的 (68) 本地发行包移到 `~/.Trash/folio-release-1.2.0-68-20261007-220322/`。

## 这次怎么发的（与以往不同之处）

- 以往要求先在空闲门下实测本次发行包，站点才肯构建。发版时本人在用电脑（空闲 0 秒、负载约 12），按「时间优先」改走脚本里已有的 `--keep-history --history-tests`：主页顶部与资源占用区明确标注「历史参考、不代表新版新测」，截图/录像标 1.0 (14)，性能标 1.2.0 (68)。
- `--history-tests` 的证明这次是对**从发行 ZIP 解压出的 App** 现跑的：`bash scripts/test.sh --main-editor <解压>/Folio.app/Contents/Resources` 与 `python3 scripts/test_file_open.py <解压>/Folio.app`（隐藏、隔离副本），均退出 0；日志与 `proof.json` 在 `build/history-tests-1.2.1-128/`（含本机路径，不入库）。
- **防回退（已修）**：Chapter 的 `sop.site_build`（不带 `--release`）原来会选 `perf/lightweight.json` 实测过的旧包，等于把刚发的新版换回旧版（10-05 20:32 的站点重建就是 68）。`measured_release()` 现在只在不低于 `build/site/release.json` 的包里选：没实测过新版时拒绝构建，而不是降级。实跑默认入口确认选中 128 并拒绝。
- 主页新增 1.2.1 两张卡（配置导出/导入与可选 iCloud、检查更新），命令行卡片更新；版本记录页加 1.2.1；隐私页与常见问题写明检查更新、升级下载与 iCloud 配置同步的联网范围。发行说明 `docs/releases/1.2.1.md`。

## 待自动补（不需要本人）

- 实测 1.2.1 (128) 发行包后，主页的历史标注自动消失：`sop.measure`（`scripts/release/measure-sop.py`，会找 `build/release-1.2.1/Folio-1.2.1-128-arm64.zip`）写入 `perf/lightweight.json` 后，默认 `site_build` 就能构建 128 的正式页并部署。这一步要等空闲门（测量会启动隐藏副本，在 Dock 冒图标）。
- media_playback：部署后跑一次失败（readyState 0，当时负载 12.9）；三段视频线上 206 / video/mp4 可取，文件与上一版逐字节相同。属验收器高负载超时，已知同类两次。

## 没验证的

- 没有在另一台 Mac 或干净账户上实际走一遍「检查更新 → 下载/升级」；只在本机用 `folio update check` 读回线上记录。
- 没有重录演示、没有重测性能。
