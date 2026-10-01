# Folio

**中文** | [English](README_EN.md)



[产品主页、直接下载与使用指南](https://app-mac-folio.tianli.cyou/)

本地 Markdown 阅读与编辑工具。SwiftUI 窗口内默认使用单栏即时渲染编辑区，Swift 管理文件、保存与恢复记录。完整渲染使用打包的 WebKit 组件，会创建辅助进程；不再沿用旧原生版的低内存测量值。

<!-- lightweight:start -->
## 资源占用

| 安装包 | 空闲内存 | 空闲 CPU | 启动到编辑窗口出现并读入 137 KB 样例文档 |
|---|---|---|---|
| **3.2 MB**（装好后 7.8 MB） | **125 MB** | **0%** | **300 ms** |

编辑区是包内 CodeMirror 网页组件，跑在系统 WebKit 里，多出网页、GPU、网络三个辅助进程；公式（KaTeX）、代码着色与 Mermaid 图表都在文档用到时才加载；外部修改由系统文件事件通知，空闲时不轮询；无服务器与后台任务。

<sub>v1.2.0 (68) · Mac16,12 / Apple M4 / 16 GB / macOS 27.2 · 合成 Markdown 样例 136,703 字节（200 节：标题、中文正文、表格、任务列表、代码块、10 个公式），由 scripts/measure-lightweight.py 生成；未打开用户文档 · 2026-10-01。数字来自所列设备实测，版本更新后重新测量。内存口径为 phys_footprint；CPU 为 60 秒采样窗内 CPU 时间 ÷ 墙钟；大小按十进制 MB。原始数据见 [perf/lightweight.json](perf/lightweight.json)。</sub>
<!-- lightweight:end -->

## 使用

- ⌘O 打开文件，⌘N 新建，⌘S 保存，⌘⇧S 另存为。
- 默认显示排版好的标题、表格、链接、图片、公式与图表。点击对应段落编辑 Markdown，移到其他段落后立即恢复排版；工具栏可切完整源码。
- ⌘F 搜索替换，⌘B 加粗，⌘I 斜体，⌘K 插入链接。
- 命名文件自动保存；未命名内容存为本地恢复草稿。
- 左侧最近文件可固定、重新定位或移除；标题大纲可跳转。
- ⌘⇧F 或侧栏「搜索」检索全部笔记：先在设置的「索引文件夹」添加目录并更新索引，再输入关键词，点命中行即打开并跳到对应行。索引由 Folio 在本机维护，不修改笔记；3 个字及以上走全文索引，更短的词自动逐字匹配。已有自定义索引位置继续保留。
- 应用包内附带 `folio` 命令，与界面共用同一 Swift 业务层，见下方「命令行」。菜单「文件 → 生成目录图谱…」与 `folio graph <目录> --launcher -n` 生成同一份目录图谱及再次生成的入口。
- 图片可拖入、粘贴或从菜单插入，默认保存至文档旁 `assets/`。
- 主编辑区直接显示网格表格和引用式链接；引用定义在渲染模式隐藏，在源码模式可编辑。
- ⌘⇧P / 工具栏「完整预览」可另开只读实时预览，适合对照阅读；日常编辑无需打开此窗口。

## 命令行（给程序和 agent 用）

界面给人用，`folio` 命令给程序和 agent 用：两者调用同一套 Swift 代码，界面里能看到、能做的索引、检索、状态与文件操作都有对应命令。下载版把 `/Applications/Folio.app/Contents/Resources/bin/folio` 链接到 `~/.local/bin/folio` 即可在终端使用；从源码安装时自动链接。完整说明、`--json` 结构与退出码见 [docs/cli.md](docs/cli.md)。

```sh
folio search 水库 --since 2026-01-01          # 与侧栏搜索同一实现：path:line + 命中行
folio files reservoir --repo notes --json      # 只列文件；--json 输出 {ok, mode, count, files:[…]}
folio stats --json                             # 篇数、最后更新、分布
folio config --json                            # 生效的配置、索引库位置及来源、索引文件夹
folio session --file ~/notes/a.md --json       # 该文件在 Folio 里是否打开、未保存或冲突
folio roots add ~/Documents/Notes && folio index
folio graph ~/Documents/Notes --launcher --json
folio asset add notes/a.md shot.png            # 复制图片到 assets/，输出要插入的 Markdown
```

| 命令 | 对应界面 |
|---|---|
| `search` / `files`（读） | 侧栏「搜索」（⌘⇧F） |
| `stats` / `config` / `roots`（读） | 设置「索引文件夹」、自定义索引位置 |
| `session`（读） | 标签页的未保存/冲突状态、侧栏「最近」、关闭的草稿、阅读设置 |
| `roots add/remove`、`index`（写） | 设置「添加文件夹」「移除」「更新索引」 |
| `graph`（写） | 菜单「文件 → 生成目录图谱…」 |
| `asset add`（写） | 插入图片（菜单、拖入、粘贴）的保存规则 |

每个命令都有 `--help` 和 `--json`；退出码 0 成功（含无命中）、1 失败、2 用法错误。检索默认最多 20 篇，`--limit 0` 不限；空白查询词（如空变量）和不是日期的 `--since` 都按用法错误处理，不会列出整个索引或静默返回空结果。设置里的「更新索引」每次按磁盘上的 index.json 重建，不会用窗口里的旧文件夹列表覆盖 `folio roots` 的修改。只读命令不写任何状态；`session.json` 只由 App 写入，所以标签、最近记录、固定与阅读设置的修改留在界面里。编辑、预览、撤销、打开窗口等纯界面手势没有命令；agent 直接改 Markdown 文件，Folio 会重新载入未改动的标签，对有未保存修改的标签标记冲突而不覆盖。

1.2.0 (57) 及更早版本的 `search`/`files --json` 输出带整篇正文的数组，且 `%`、`_` 当通配符、短词只查正文、命中行区分大小写；之后的构建输出对象，匹配规则与侧栏一致，文本输出格式不变。

## 构建

```sh
cd Editor            # 在仓库根目录执行
npm ci
cd ..
bash build.sh --install
```

运行时无需 Node、Python 或服务器。可选预览的 JS/CSS/字体全部打包。构建复用总部 Xcode 选择器、图标工厂和 CodingKey 检查；未从其他 App 导入代码。

`bash build.sh --build-only` 只构建，不启动 GUI、不安装；`bash scripts/test.sh --core-only` 验生产文件读写、自动保存与冲突恢复，不创建窗口。完整窗口与系统文件打开验收仍需在允许 UI 操作的隔离会话完成，不能用这两个命令代替。

本机装机可用 `python3 scripts/verify-install.py`：先核已装版来源，当前源码已有有效回执时直接跳过；否则沿 `build.sh --install` 构建，完成离屏编辑器和隔离 LaunchServices 文件打开测试，再备份旧程序并安装。装机后核验签名、版本、图标与 Chapter `perf/build-receipt.json`；保留用户状态，不关闭已有用户会话。文件打开测试使用独立 bundle ID 的后台副本，不修改默认文件关联。

Chapter 固定验收登记在 `project.yaml`，四项均使用合成数据和独立状态目录：

```sh
~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py accept --app folio-mac \
  --check functionality --check recovery --check privacy --check native_ui --json
```

`scripts/accept/` 调用生产文件、恢复和检索实现；`native_ui` 构建本仓应用后运行其 `--ui-self-test`，离屏创建真实 ContentView / EditorSurface，直接调用切换源码、重载和关闭等动作，保存截图并断言状态，不合成输入。Chapter 自动维护 `perf/delivery-evidence.json`；脚本不安装应用、不修改真实文档。人工关闭确认框、Dock/Finder 图标和安装版 LaunchServices 行为不在这四项的覆盖范围。

## 产品发行

`python3 scripts/package-release.py` 从已签名的构建包生成 `build/release/Folio-<版本>-<构建>-arm64.zip`、`release.json` 和 SHA-256。脚本核包内资源、系统依赖、源码指纹与解压后的签名；不启动、安装或上传应用。当前是 macOS 15+、Apple Silicon、本地签名且未公证的直接下载版。运行包包含第三方许可，不包含开发环境或用户会话。

主页源在 `site/`，实际版本、大小、下载名与哈希来自发行清单。`python3 scripts/build-site.py --out build/site` 生成可消费的静态包和 `site-manifest.json` 文件白名单；真实截图、视频与字幕缺失或版本不匹配时停止。`--preview` 仅出明确标记的内部预览，不可部署为完成站。源码按随仓许可公开；共享站群只消费白名单内的构建文件，不带入用户状态与录制原片。

合成录制资料与输入在 `docs/demo/`；`python3 scripts/prepare-demo.py` 创建独立状态及带环境变量的演示副本，打印其路径但不启动。仅该副本启用不能成为 key/main 的后台窗口，真实编辑器与文件读写不变；普通应用保持正常窗口行为。实录成片落 `docs/demo/media/`，原片保留 `build/demo/`。详情见 [录制说明](docs/demo/录制说明.md)。

验证：`bash scripts/test.sh`（本机 Xcode、Node 与 Chrome）。`build.sh` 还会从系统发起文件打开，核对隔离会话的实际文档内容；失败会阻止安装。安装包位于 `/Applications/Folio.app`，保留现有 Markdown 默认打开方式。

## 数据

原文是本地 UTF-8 `.md`。历史、设置与恢复草稿位于 `~/Library/Application Support/TLMarkdown/session.json`（仅当前用户可读写）。删除最近记录不会删除原文。外部修改冲突时停止自动保存，重新载入会保留当前修改为独立草稿。

## 可选预览依赖

CodeMirror / Lezer、markdown-it 与插件、DOMPurify、highlight.js、KaTeX、Mermaid。版本见 `Editor/package-lock.json`。许可随构建产物分发。

`Tests/NativeEditorTests.swift` 验证保留的原生编辑实现；`Editor/tests.mjs` 验证当前主编辑区使用的渲染和编辑组件。安装版还需通过真实窗口验证主编辑路径。

`Tests/MainEditorTests.swift` 挂载生产 `EditorSurface`，验证主区表格与引用渲染、编辑后重渲染和 Swift 保存；`scripts/test.sh` 与 `build.sh` 均执行，失败阻止安装。单独运行：`bash scripts/test.sh --main-editor /Applications/Folio.app/Contents/Resources`（隔离测试状态，不改用户会话）。错误原因和回退验证见 [实时渲染复盘](handoffs/live-rendering-retro.md)。

## 需求与验证

`handoffs/verification.md` 为最初 WebKit 版本历史验收；不代表当前原生功能范围。
