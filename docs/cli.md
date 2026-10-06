# Folio 命令行

命令在应用包内：`/Applications/Folio.app/Contents/Resources/bin/folio`。界面给人用，命令给程序和 agent 用，两边调用同一套 Swift 业务代码：索引与检索（`Sources/IndexEngine.swift`）、目录图谱（`Sources/GraphEngine.swift`）、会话记录与插图规则（`Sources/Models.swift`）。仅依赖系统 SQLite，不需要 Python、Node 或常驻服务。

从官网下载 ZIP 安装后，需要手动把它加入终端路径（从源码 `./build.sh --install` 安装时会自动建立同一链接）：

```sh
mkdir -p ~/.local/bin && ln -s /Applications/Folio.app/Contents/Resources/bin/folio ~/.local/bin/folio
```

`folio --help` 列出全部命令，`folio <命令> --help` 显示单个命令的参数与 `--json` 结构。

## 命令与界面对应

| 命令 | 读/写 | 界面里的同一功能 |
|---|---|---|
| `folio status` | 读 | 读回当前状态：版本（「配置与更新」窗口）、配置与索引库、索引文件夹、窗口会话摘要、阅读设置 |
| `folio read <文档>` | 读 | 编辑器打开文件的规则（UTF-8、去 BOM、换行统一）；状态栏的字符数；窗口里有无未保存修改 |
| `folio outline <文档>` | 读 | 侧栏「大纲」：各级标题与所在行，跳过围栏代码块 |
| `folio search [词]` | 读 | 侧栏「搜索」（⌘⇧F）：按文件分组的命中行与行号 |
| `folio files [词]` | 读 | 同上，只列文件 |
| `folio stats` | 读 | 设置「索引文件夹」里的篇数与最后更新时间，另加 workspace/仓库/月份分布 |
| `folio config` | 读 | 设置里的索引文件夹列表、自定义索引位置；另列排除规则条数与实际使用的库 |
| `folio roots [list]` | 读 | 设置里的索引文件夹列表 |
| `folio session` | 读 | 标签页（未保存、冲突、提示）、侧栏「最近」、「恢复关闭的草稿」、阅读设置 |
| `folio settings` | 读 | 设置面板「阅读与编辑」的当前值与可取范围 |
| `folio recent [list]` | 读 | 侧栏「最近」：路径、是否固定、上次打开时间、文件是否还在 |
| `folio settings set <键> <值>…` | 写 session.json | 设置面板的正文字体、字号、宽度、启动恢复、图片目录、自定义索引文件；`font_size larger/smaller` 同 ⌘+ / ⌘- |
| `folio recent pin/unpin/remove <文件>…`、`folio recent clear` | 写 session.json | 最近文件右键菜单的固定到顶部 / 取消固定、从最近记录移除，以及「清空最近记录」；重新定位 = `recent remove` 旧路径 + `open` 新路径 |
| `folio write <文档>` | 写文档 | 「保存」「另存为」与新建文档：保留原换行符与 BOM，原子写入；窗口里有未保存修改时拒绝 |
| `folio open <文件>…` | 交给窗口 | 「打开…」、拖入、点最近文件或搜索命中：后台交给 Folio 打开，不抢焦点；`--example` 同欢迎页的「打开示例文档」 |
| `folio roots add/remove <目录>…` | 写 index.json | 设置「添加文件夹…」与移除 |
| `folio index [--full]` | 写索引库 | 设置「更新索引」（Ctrl-C 等同「取消」） |
| `folio graph <目录>` | 写 HTML | 菜单「文件 → 生成目录图谱…」 |
| `folio asset add <文档> <图片>` | 写图片文件 | 插入图片（菜单、拖入、粘贴）的保存规则 |

## 给 agent 的用法

```sh
folio search 水库 --ws Work --since 2026-01-01          # path:line + 命中行
folio search 生态流量 --json | jq '.files[] | {path, lines}'
folio files reservoir --repo notes --limit 50 --json
folio stats --json                                      # count / updated_at / 分布
folio config --json                                     # 配置、库位置及来源、索引文件夹、规则条数
folio session --file ~/notes/a.md --json                # 改文件前先看 Folio 里有无未保存修改或冲突
folio session --text --json                             # 需要找回未保存草稿时附带正文
folio roots add ~/Documents/Notes && folio index        # 扩大索引范围后更新
folio graph ~/Documents/Notes --launcher --json         # 生成图谱，不打开浏览器
folio asset add notes/a.md ~/Desktop/shot.png           # 输出 ![图片](<assets/image-….png>)，文档本身不改
folio status --json                                     # 一次读回版本、配置、索引、会话摘要与阅读设置
folio read notes/a.md --json | jq '{characters, dirty}' # 正文 + 字符数 + 窗口里有无未保存修改
folio outline notes/a.md                                # 行号<Tab>按级别缩进的标题
printf '# 标题\n正文\n' | folio write notes/new.md        # 新建；已有文件则按原换行符与 BOM 保存
folio write notes/a.md --from /tmp/a-new.md --json      # 窗口里有未保存修改时退出 1，不覆盖
folio open notes/a.md && folio session --file notes/a.md --json   # 交给窗口，再读回标签状态
```

- **检索语义与侧栏一致**：查询词去掉首尾空白；3 个字及以上走全文索引（trigram），更短的逐字匹配；`%`、`_` 按字面；标题或正文命中都算；命中行不区分大小写，行号从 1 起。`--repo`、`--path` 按字面子串匹配，`--ws` 精确匹配，`--since` 比较最后修改时间（`YYYY-MM-DD` 或 `YYYY-MM-DDTHH:MM`，本地时间；其他写法是用法错误，退出 2）。不给查询词时只按条件列出文件；给了空白查询词（例如空变量）是用法错误，不会列出整个索引。`--limit` 默认 20，`0` 表示不限；`truncated: true` 表示达到上限、可能还有更多命中。
- **只读命令不改文档、配置、会话记录和索引内容**：`status/read/outline/search/files/stats/config/roots list/session/settings/recent list` 只读。读索引库时以只读方式打开，SQLite 会刷新库旁它自己的 `-shm` 共享内存文件（WAL 模式的读者都会），库内容不变。`session.json` 的快照最多比界面晚约 0.25 秒。
- **阅读设置与最近记录：窗口和命令写同一份**（`session.json` 的 `settings` 与 `recent`）。同一时刻只有一个写入者：Folio 窗口运行期间一直持有状态目录里的 `session.lock`，这时 `folio settings set` / `folio recent …` 把修改放进 `requests/` 交给窗口，窗口用设置面板和最近列表的同一段代码（`SessionEdits.apply`）应用、立即存盘并应答，编辑器与设置面板当场跟着变，`applied_by` 为 `window`；窗口没开时命令自己拿这把锁，经 `SessionDisk` 读出、修改、写回，标签、未保存正文和关闭的草稿原样保留，`applied_by` 为 `file`。窗口 5 秒内没有应答（`code: window_no_reply`）或开着的是装新版之前启动的旧窗口（`window_outdated`）时退出 1，什么都不写。值的范围与面板一致（字号 13–26、宽度 560–1300 且为 20 的倍数、字体 system/serif/mono、图片目录为相对目录），不在范围内是用法错误。窗口没开时 `recent clear` 不清程序坞菜单里的系统最近文档。
- **文档读写与编辑器同一实现**：`read`、`write` 走 `DocumentIO.open/save`，`outline` 与侧栏大纲共用 `MarkdownOutline`。`write` 的正文来自 `--content`、`--from` 或标准输入，只写 `.md`、`.markdown`、`.txt`；文件不存在时新建（所在文件夹须已存在）。目标在 Folio 窗口里有未保存修改或冲突时拒绝写入，`--force` 才写磁盘，此时窗口把该标签标记为冲突、不覆盖窗口里的修改。`open` 先按同一规则校验全部文件，再让系统在后台交给 Folio（`-n` 只校验不打开）。
- **写命令沿用界面的规则**：`roots add/remove` 先重读 index.json，展开 `~` 并规范化路径、去重，原子写入（0600），配置不可读时拒绝修改，add 只接受存在的文件夹，下次 `folio index` 生效；设置窗口的「更新索引」每次都按磁盘上的 index.json 重建，回到 Folio 时文件夹列表也会重读，所以窗口里的旧列表不会覆盖 `folio roots` 的修改；`index` 与设置「更新索引」共用同一写事务，另一方正在写时等 3 秒后失败，原索引保持不变；`graph` 遇到非本工具生成的同名文件拒绝覆盖；`asset add` 只接受小于 40 MB 的图片类型，目录必须是文档旁的相对目录。

## JSON 与退出码

每个命令都支持 `--json`，输出一个对象，成功时 `"ok": true`。失败时同样输出 `{"ok": false, "command", "error", "code", "usage"}`（`error` 是原因文字，`usage` 为 true 表示用法错误），并在 stderr 打印原因。`code` 是可供程序分支的稳定短码：`usage`、`invalid_value`、`not_found`、`window_unsaved`、`window_no_reply`、`window_outdated`、`session_unreadable`、`encoding`、`read_only`、`conflict`、`cancelled`，其余为 `failed`（1.2.1 (119) 及更早没有这个字段）。

| 退出码 | 含义 |
|---|---|
| 0 | 成功，包括检索无命中（`count: 0`） |
| 1 | 操作失败：索引不存在、配置不可读、目录不存在、写入被拒、窗口没有应答等 |
| 2 | 用法错误：不认识的命令或参数、缺少参数、该命令不接受的参数、设置的值不在可取范围 |

主要结构（字段名为 snake_case，时间为 ISO 8601 UTC）：

- `status`：`{ok, version, build, app?, state_directory, config: {path, exists, error?}, database: {path, source, exists}, index?: {count, updated_at, error?}, roots: [{path, exists}], session: {path, exists, modified, error?, documents, unsaved, conflicts, recent, closed_drafts}, settings?: {font_family, font_size, content_width, restore_session, image_folder, note_index_path?}}`。配置、索引或会话记录不可读时其余内容照常输出，`ok` 为 false、退出 1。
- `read`：`{ok, path, title, characters, lines, bytes, line_ending: "lf"|"crlf"|"cr", bom, open_in_folio, dirty, conflict, text}`。
- `outline`：`{ok, path, count, headings: [{line, level, title, offset}]}`（`offset` 为 UTF-16 位置）。
- `write`：`{ok, path, created, changed, characters, bytes, line_ending, bom, open_in_folio}`。
- `open`：`{ok, files, app, opened}`。
- `search` / `files`：`{ok, command, query, mode: "fts"|"like"|"filter", elapsed, truncated, limit, count, database, database_source, files: [{id, path, workspace, repository, title, mtime, lines: [{line, text}], body?}]}`。`files` 命令的 `lines` 为空数组；命中行按 `--width`（默认 120，0 不截断）截断；整篇正文只在 `--body` 时附带。
- `stats`：`{ok, count, updated_at, characters, repositories, workspaces, top_repositories, months, database, database_source}`。
- `index`：`stats` 的字段加本次运行的 `changed, unchanged, removed, skipped_binary, unreadable, symlinks, broken_links, elapsed, recovered_database?`。
- `config`：`{ok, state_directory, config: {path, exists, error?}, database: {path, source, exists}, index?: {count, updated_at}, roots: [{path, exists}], rules: {…条数}, rule_values?}`（`--show-rules` 才带规则内容）。
- `roots`：`{ok, action, config, roots, added, removed, unchanged, not_found, changed}`。
- `session`：`{ok, session_file, exists, modified, active_id, documents: [{id, path?, title, active, dirty, conflict, message, characters, text?}], recent: [{path, name, pinned, opened}], closed_drafts: [...], settings, unreadable_records}`。
- `settings`：`{ok, session_file, exists, settings: {font_family, font_size, content_width, restore_session, image_folder, note_index_path?}, limits: {font_family, font_size: [最小, 最大], content_width: [最小, 最大], content_width_step}}`；`settings set` 另有 `changed: [键]` 与 `applied_by: "window"|"file"`。
- `recent`：`{ok, session_file, exists, count, recent: [{path, name, pinned, opened, exists}]}`；写入另有 `action, changed: [路径], unchanged, not_found, cleared, applied_by`。已是所要状态记在 `unchanged`，不在列表里记在 `not_found`，都不算失败。
- `graph`：`{ok, path, launcher?, directories, files, nodes, edges, metadata_warnings}`。
- `asset`：`{ok, document, source, path, folder, markdown, bytes}`。

1.2.0 (57) 及更早版本的 `search/files --json` 输出的是带整篇正文的数组，`%`、`_` 当作通配符，短词只查正文，命中行区分大小写；现在与侧栏为同一实现，文本输出格式不变，但计数可能略有不同（例如短词也匹配标题）。

## 索引库位置

所有命令与界面按同一顺序决定使用哪个索引库：`--db` 参数 → 环境变量 `MDINDEX_DB` → Folio 设置里的「自定义索引位置」 → 默认 `~/Library/Application Support/TLMarkdown/md_index.db`。配置默认是同目录的 `index.json`，可用 `--config` 指定；`TL_MARKDOWN_STATE_DIR` 把整个状态目录（配置、默认库、会话记录）换到别处，适合测试和隔离运行。`folio config` 显示当前实际使用的位置及其来源。

首次使用请在 Folio 设置中添加「索引文件夹」，或运行 `folio roots add <目录>`，再更新索引。没有配置不会扫描任何目录。

配置示例（按自己的目录修改，配置和数据库均不应加入源码仓）：

```json
{
  "roots": ["~/Documents/Notes"],
  "skip_directories": [".git", "node_modules", ".venv", "build", "dist", "DerivedData"],
  "skip_paths": [],
  "full_text_excluded_paths": [],
  "skip_directory_suffixes": [],
  "skip_hidden": true,
  "restricted_names": [],
  "restricted_prefixes": [],
  "restricted_substrings": []
}
```

`skip_paths` 排除整棵子树，支持 `目录/**/名称` 排除该目录下任意层的指定名称；`full_text_excluded_paths` 仅排除全文索引。图谱的受限名称、前缀及名称片段（`restricted_substrings`）由本机配置指定，公开默认没有私有规则。

更新仅读取普通 Markdown 文件，不跟随软链，跳过含 NUL 的文件及 FIFO。取消会保留原索引；坏库保留为 `.corrupt` 后重建。索引读取连接保持只读，写入在一个事务中完成。

图谱读取 Markdown 链接、frontmatter 的 tags/relations，以及 catalog/project.yaml 中的 knowledge_graph 和 table_rows 子集；它不是完整 YAML 处理器。输出保留生成物标记，遇到非本工具生成的同名文件会拒绝覆盖。`-n` 或 `--json` 只生成，不打开浏览器；否则用默认浏览器打开。此命令生成静态快照，不替代独立的实时图谱服务。

## 只在界面里做的事

逐项对照登记在 `project.yaml` 的 `sop.agent_cli`（手机端在 `ios/01-源程序/project.yaml`），`folio --help` 末尾有同一份摘要。

- **只在窗口里有意义**：未命名草稿标签（保存前只在窗口里）、打开设置面板、帮助网页；撤销/重做、搜索与替换、查找下一个、加粗/斜体/链接（都作用于窗口里的光标与选区）；源码与渲染切换、完整预览（KaTeX、Mermaid、表格，只渲染不产出文件）、侧栏显示与切换、切换标签、点大纲跳转、打开搜索命中后光标跳到该行、渲染模式下勾选任务列表、代码块复制按钮、点正文里的链接；关闭提示横幅、在 Finder 中显示；手机端的「授权图片目录…」。
- **暂缺命令**：关闭标签（含关闭时的保存 / 保留草稿）、恢复关闭的草稿到标签页、提示条上的「重新载入」——它们改的是窗口会话里的标签，还没接到 `folio settings` / `folio recent` 用的那条窗口通道，状态用 `folio session` 读；「配置与更新」窗口里的「使用 iCloud 记住配置」、导出配置、导入配置、检查更新、升级到新版由共享生命周期模块提供，该模块暂无命令入口。

agent 修改 Markdown 用 `folio write` 或直接写文件：Folio 的外部修改监视会重新载入未改动的标签，对有未保存修改的标签标记冲突而不覆盖。
