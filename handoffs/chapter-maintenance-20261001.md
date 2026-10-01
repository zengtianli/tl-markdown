# Chapter 维护：装机 1.2.0 (68)、主页数字重部署、自动部署修复（2026-10-01 上午）

## 已完成

- **自动部署失败的根因（已修）**：`sop.site_build` 是 `python3 scripts/build-site.py --out build/site`，不带 `--release` 时默认读 `build/release/release.json`，那是 1.0.1 (27) 的旧包，于是 Chapter 的 deploy_page 报「measures 1.2.0 (57), release is 1.0.1 (27)」。`build-site.py` 不带 `--release` 时改为选 `perf/lightweight.json` 实测过的那个已打包发行（`build/release*/release.json` 的版本、构建号、下载字节数一致），没有实测过的就取最新包并照旧拒绝构建。提交 `85f3d1d`。
- **回执输入收窄（已修）**：`scripts/verify-install.py` 的回执输入从 `scripts/*.py`、`scripts/*.sh` 改为 build.sh 实际调用的 `build-cli.sh`、`test.sh`、`package-release.py`、`test_file_open.py`、`install-cli.py`。改站点、演示、测量或验收脚本不再让装机回执失效、白涨构建号。同一提交 `85f3d1d`。
- **主页重部署 (57)**：`chapter sop run --app folio-mac --stage promo --retry` 用修好的默认值重建并部署，线上 `facts.json` 卡片为「安装包 3.1 MB（安装后 7.6 MB）· 空闲内存 125 MB · 空闲 CPU 0% · 速度 297 ms」，与 `perf/lightweight.json`（09-30 23:10 对 (57) 的重测）一致；page、card、page_icon、readme 全部 ok。
- **推送**：领先的 3 个提交（CLI 扩展、重测、README 数字）推到 GitHub；推送前按 `scripts/accept/cli_cases.py` 的禁用字符串清单扫描新增行，干净；仓库无 workflows/webhook。
- **装机 1.2.0 (68)**：`python3 scripts/verify-install.py`（build.sh --install 内主编辑区与 LaunchServices 文件打开测试通过），receipt 回读匹配；`folio --version` = `folio 1.2.0 (68)`。装前 Folio 没有运行。
- **验收**：native_ui、cli_entry、functionality、recovery、privacy、installed_icon（离屏读取系统显示图标，与源图标一致）、icon_review 在 (68) 上全部 passed，均由 Chapter 验收器自动判定。
- **发行包 (68)**：`package-release.py --app /Applications/Folio.app --out build/release-1.2.0`，`Folio-1.2.0-68-arm64.zip` 3,200,409 字节，SHA256 `18263b66…`，源码指纹 `caae8759…`；(57) 包移到 `build/release-1.2.0-57/`（线上仍是它）。`capture.json` 登记 `reused_for["1.2.0 (68)"]`，`check_media` 对 68 与 57 都通过。

## 待测量阶段

- 发布 (68) 需要先在空闲门下实测这个包：Chapter 登记的 `sop.measure`（`scripts/release/measure-sop.py`）会测 `build/release-1.2.0/Folio-1.2.0-68-arm64.zip` 并写入 `perf/lightweight.json`；之后 deploy_page 不带参数就会选中 (68) 构建并部署主页，release 项随之对齐。在此之前 Chapter 的 release 项为「发布版 57 落后于装机的当前构建 68」，这是如实的待办，不是故障。
- 注意 (68) 包比 (57) 大约 99 KB（CLI 新命令），实测后主页「安装包」数字会变。

## 未提交

- `perf/acceptance/homepage_*`、`media_playback*` 含本机绝对路径（Playwright 浏览器位置），公开仓不提交，留本地。
