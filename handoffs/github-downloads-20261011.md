# GitHub 下载渠道迁移 · 2026-10-11

task_id：`lintel-github-release-downloads-20261011`。本轮仅 Folio 原站点、发行迁移入口、必要回归和本交接；沿 Chapter 的 claims 身份，未新建或释放声明。网站未部署，最终冻结发布由 Lintel 主会话处理。

## 输入核实

- 线上与 Air 原发行目录：Folio 1.2.1 (128)，`Folio-1.2.1-128-arm64.zip`，3,643,010 字节，SHA-256 `e2e3f477207a4b305f32abe2b3b1c98ade995f52d5ac51489bc6c9f7f6c2fa72`。原 ZIP、线上重新下载和 Mini 原站点镜像逐字节哈希一致。
- 原包实际为 ad-hoc、未公证，见原 `chapter-release-20261007.md`；Air 的公证包是另一构建 143，本轮不替换成它、不重编、不重签、不公证、不安装。
- 构建源码提交 `fe37ed16ca1feb94db777bcc327fa7293dd92b99` 已在公开仓 `zengtianli/tl-markdown`；源码指纹 `164b1e0fb7a8e6efd342ab6401f96c3a72d0c32741ff394ea989e3e78801169d`。
- Mini 原 `build/release/release.json` 是旧 1.0.1 (27)，未覆盖。经原双机 `macbook` 入口精确取回 Air 的 `build/release-1.2.1/` 原包、元数据与既有 `build/history-tests-1.2.1-128/` 证明和对应日志；未重跑 App 测试。
- `apps-portal show folio-mac --json` 当时 `download` 为空；真实 GitHub URL 是门户主会话后续登记的依赖，未改共享登记。

## GitHub Release（已实际公开，门户登记依赖）

- Release：<https://github.com/zengtianli/tl-markdown/releases/tag/v1.2.1-128>。
- **门户 `download` 应登记的直链**：<https://github.com/zengtianli/tl-markdown/releases/download/v1.2.1-128/Folio-1.2.1-128-arm64.zip>。
- 校验：<https://github.com/zengtianli/tl-markdown/releases/download/v1.2.1-128/SHA256SUMS.txt>；发行记录：<https://github.com/zengtianli/tl-markdown/releases/download/v1.2.1-128/release.json>。
- GitHub Release ID `409506586`，`draft:false`，实际公开时间 `2026-10-11T07:38:20Z`。tag 解引用仍是 `fe37ed16ca1feb94db777bcc327fa7293dd92b99`，没有推本轮源码。
- 原入口 `package-release.py --publish-existing` 验证官网元数据、重新下载 SHA、公开源码提交的完整源码指纹、ZIP 内 Info.plist / FolioBuild.json / CLI SHA 和真实签名；上传后从 GitHub 下载全部三个资产逐字节校验，再将草稿转为公开。
- GitHub API 的 ZIP `digest` 为 `sha256:e2e3f477207a4b305f32abe2b3b1c98ade995f52d5ac51489bc6c9f7f6c2fa72`，`size:3643010`。仅上传原 ZIP 和公开字段白名单内的发行记录、校验值，没有内部日志、私有源码或设备回执。
- 公开后以不带 GitHub 登录凭证的 HTTPS 直链重新下载至 `build/release-1.2.1/github-Folio-1.2.1-128-arm64.zip`，SHA 再次一致。该副本与官网回读副本均仅在本地发行目录，未进入站点白名单。
- 第一次草稿校验发现 GitHub 在草稿公开前不创建 tag，`commits/v1.2.1-128` 返回 `HTTP 422: No commit found for SHA: v1.2.1-128`；修正为草稿核 `target_commitish`、公开后核 tag。第二次 by-tag 读草稿返回 `HTTP 404: Not Found`，改从原 releases 列表取草稿；只续原草稿，不重复上传、不改资产字节。最终原入口退出 0。

## 原站点构建与回归

登记目录：`/Users/tianli/Apps/folio/build/site`。源生成器从原发行元数据派生 tag / GitHub 资产链接、版本、大小、SHA；不生成 `downloads/`，不复制安装包或站内校验副本。后续正式出包元数据也生成同一 GitHub 地址。原打包/安装的 Developer ID、公证和装订门禁未修改；迁移入口只接受当时官网已公开的同字节包。

```sh
cd /Users/tianli/Apps/folio
/Users/tianli/Dev/.venv/bin/python -B Tests/ReleaseSiteTests.py
/Users/tianli/Dev/.venv/bin/python -B scripts/build-site.py --release build/release-1.2.1/release.json --keep-history --history-tests build/history-tests-1.2.1-128/proof.json --out build/site
/Users/tianli/Dev/.venv/bin/python -B site/build-iphone.py --base build/site --out build/site
lintel site check --site apps --product folio-mac --bundle /Users/tianli/Apps/folio/build/site --json
```

- 回归 2 项通过：公开元数据保留发行事实、剔除内部记录；站点拒绝安装包，即使在白名单内，仍允许教程示例 ZIP。
- iPhone 原增量入口不再查站内镜像，改核本地原发行目录的同一 ZIP SHA / 字节数，以及 GitHub URL，保留原 Mac 白名单校验和原子替换。
- 完整站点白名单 29 个文件，`preview:false`，1.2.1 (128)，无 Folio 安装包；本地 `build/release-1.2.1/Folio-1.2.1-128-arm64.zip` 保留，原 `build/release/` 未动。原站点备份位于 `build/.site-previous-wd_ach2_`（含旧镜像，仅本地恢复用，不在登记站点白名单）；第二步 Mac 中间构建备份在 `build/.site-previous-7b8yty4v`。
- 白名单 29 个文件 SHA / 字节数逐项通过；所有原视频、完整教程、截图和字幕的 SHA 不变，iPhone 小节完整保留。`media/capture.json` 的复用核对日期从前次生成的 `2026-10-08T07:13:06.221612+00:00` 改为取回原证明的 `2026-10-07`，与本轮复用的原测试证明一致，未声称新测试。
- 本轮没有 App 构建、安装、版本变化、素材重录或网站部署；所有其他会话的 project.yaml、perf、iOS 等差异保留，未提交。

## 本地源码提交

`8fbbb5d20042d8d20947df463ba21ecf23bcb708`：`site: migrate Folio downloads to verified GitHub Release assets`。仅 7 个本轮文件：`scripts/package-release.py`、`scripts/build-site.py`、`site/index.html`、`site/build-iphone.py`、`site/README.md`、`README.md`、`Tests/ReleaseSiteTests.py`；本交接另作为说明提交。未执行源码 push。提交前核逐文件差异、`git diff --check`，提交后回读 7 文件统计与本轮改动一致。

## 静态门禁阻挡（没有绕过）

只读 `lintel site check --site apps --product folio-mac --bundle /Users/tianli/Apps/folio/build/site --json` 返回 `ok:true` 但 **`ready:false / errors:1`**，规范版本 37。完整 JSON 留在 `build/github-downloads-check-20261011.json`。

唯一 error 为 `package.integrity`，完整原文：

> 公开产品站点目录里的每个安装包（无论页面是否链接）都必须与发行清单的版本/文件名/字节数/SHA256 及 site-manifest 逐项吻合。未通过：https://github.com/zengtianli/tl-markdown/releases/download/v1.2.1-128/Folio-1.2.1-128-arm64.zip（链接不能映射到同源站点产物）、https://github.com/zengtianli/tl-markdown/releases/download/v1.2.1-128/Folio-1.2.1-128-arm64.zip（链接不能映射到同源站点产物）

主会话需让原 Lintel 门禁支持真实 GitHub Release 外部资产，再按上述原 check 入口重验；不能恢复站内镜像或隐藏 ZIP 扩展名来通关。Folio 没有独立 Lintel site ID，其自有域名也是 apps 登记的 `folio-mac` 产品入口，所以沿 `--site apps --product folio-mac --bundle` 检查，无另一个产品部署入口。

另有原有三条 `video.1/2/3.captions_default` warning（中文字幕未声明默认启用，需实际播放确认），没有扩本轮范围处理。门户 `download` 在本轮只读时仍空，真实 URL 如上，应由主会话登记。

**网站未发布。** 官网仍是旧站内下载版，本地新站点等待主会话统一冻结、门禁检查和发布。
