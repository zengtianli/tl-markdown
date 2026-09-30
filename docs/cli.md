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
| `folio search [词]` | 读 | 侧栏「搜索」（⌘⇧F）：按文件分组的命中行与行号 |
| `folio files [词]` | 读 | 同上，只列文件 |
| `folio stats` | 读 | 设置「索引文件夹」里的篇数与最后更新时间，另加 workspace/仓库/月份分布 |
| `folio config` | 读 | 设置里的索引文件夹列表、自定义索引位置；另列排除规则条数与实际使用的库 |
| `folio roots [list]` | 读 | 设置里的索引文件夹列表 |
| `folio session` | 读 | 标签页（未保存、冲突、提示）、侧栏「最近」、「恢复关闭的草稿」、阅读设置 |
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
```

- **检索语义与侧栏一致**：查询词去掉首尾空白；3 个字及以上走全文索引（trigram），更短的逐字匹配；`%`、`_` 按字面；标题或正文命中都算；命中行不区分大小写，行号从 1 起。`--repo`、`--path` 按字面子串匹配，`--ws` 精确匹配，`--since` 比较最后修改时间（`YYYY-MM-DD` 或 `YYYY-MM-DDTHH:MM`，本地时间；其他写法是用法错误，退出 2）。不给查询词时只按条件列出文件；给了空白查询词（例如空变量）是用法错误，不会列出整个索引。`--limit` 默认 20，`0` 表示不限；`truncated: true` 表示达到上限、可能还有更多命中。
- **只读命令从不写状态**：`search/files/stats/config/roots list/session` 只读索引库和配置；`session` 只读 `session.json`，该文件只由运行中的 App 写入，所以标签、最近记录、固定和阅读设置的修改仍在界面里做。快照最多比界面晚约 0.25 秒。
- **写命令沿用界面的规则**：`roots add/remove` 先重读 index.json，展开 `~` 并规范化路径、去重，原子写入（0600），配置不可读时拒绝修改，add 只接受存在的文件夹，下次 `folio index` 生效；设置窗口的「更新索引」每次都按磁盘上的 index.json 重建，回到 Folio 时文件夹列表也会重读，所以窗口里的旧列表不会覆盖 `folio roots` 的修改；`index` 与设置「更新索引」共用同一写事务，另一方正在写时等 3 秒后失败，原索引保持不变；`graph` 遇到非本工具生成的同名文件拒绝覆盖；`asset add` 只接受小于 40 MB 的图片类型，目录必须是文档旁的相对目录。

## JSON 与退出码

每个命令都支持 `--json`，输出一个对象，成功时 `"ok": true`。失败时同样输出 `{"ok": false, "command", "error", "usage"}`，并在 stderr 打印原因。

| 退出码 | 含义 |
|---|---|
| 0 | 成功，包括检索无命中（`count: 0`） |
| 1 | 操作失败：索引不存在、配置不可读、目录不存在、写入被拒等 |
| 2 | 用法错误：不认识的命令或参数、缺少参数、该命令不接受的参数 |

主要结构（字段名为 snake_case，时间为 ISO 8601 UTC）：

- `search` / `files`：`{ok, command, query, mode: "fts"|"like"|"filter", elapsed, truncated, limit, count, database, database_source, files: [{id, path, workspace, repository, title, mtime, lines: [{line, text}], body?}]}`。`files` 命令的 `lines` 为空数组；命中行按 `--width`（默认 120，0 不截断）截断；整篇正文只在 `--body` 时附带。
- `stats`：`{ok, count, updated_at, characters, repositories, workspaces, top_repositories, months, database, database_source}`。
- `index`：`stats` 的字段加本次运行的 `changed, unchanged, removed, skipped_binary, unreadable, symlinks, broken_links, elapsed, recovered_database?`。
- `config`：`{ok, state_directory, config: {path, exists, error?}, database: {path, source, exists}, index?: {count, updated_at}, roots: [{path, exists}], rules: {…条数}, rule_values?}`（`--show-rules` 才带规则内容）。
- `roots`：`{ok, action, config, roots, added, removed, unchanged, not_found, changed}`。
- `session`：`{ok, session_file, exists, modified, active_id, documents: [{id, path?, title, active, dirty, conflict, message, characters, text?}], recent: [{path, name, pinned, opened}], closed_drafts: [...], settings, unreadable_records}`。
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

以下是界面手势或只属于窗口的状态，没有对应命令：打开文件到窗口（交给人时用 `open -a Folio 文件.md`）、编辑与撤销、搜索替换、加粗/斜体/链接、源码与渲染切换、字号与版宽、完整预览（KaTeX、Mermaid、表格）、大纲点击跳转、渲染模式下勾选任务列表、代码块复制按钮；标签页的关闭/保留草稿/重新载入/恢复关闭的草稿，最近记录的固定、移除、重新定位与清空，以及阅读设置的修改——这些都写入只由 App 维护的 `session.json`，命令行只读它。agent 修改 Markdown 时直接写文件：Folio 的外部修改监视会重新载入未改动的标签，对有未保存修改的标签标记冲突而不覆盖。
