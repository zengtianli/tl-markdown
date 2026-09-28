# Folio 命令行

安装后的 `~/.local/bin/folio` 指向 App 内的命令，GUI 与 CLI 共用 Swift 索引和目录图谱引擎；仅依赖系统 SQLite，不需要 Python、Node 或常驻服务。

```sh
folio --help
folio --version
folio index                 # 按设置中的文件夹增量更新
folio index --full          # 全量更新
folio search 水库
folio search reservoir --repo notes --since 2026-01-01
folio files 生态流量 --title --limit 20
folio stats --json
folio graph ~/Documents/Notes --launcher -n
```

首次使用请在 Folio 设置中添加「索引文件夹」，再点「更新索引」。没有配置不会扫描任何目录；索引默认在 `~/Library/Application Support/TLMarkdown/md_index.db`，配置为同目录 `index.json`。支持 `--db`、`--config`；已有 `MDINDEX_DB` 或 GUI 自定义索引位置继续生效。

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
  "restricted_prefixes": []
}
```

`skip_paths` 排除整棵子树，支持 `目录/**/名称` 排除该目录下任意层的指定名称；`full_text_excluded_paths` 仅排除全文索引。图谱的受限名称及前缀由本机配置指定，公开默认没有私有规则。

更新仅读取普通 Markdown 文件，不跟随软链，跳过含 NUL 的文件及 FIFO。取消会保留原索引；坏库保留为 `.corrupt` 后重建。索引读取连接保持只读，写入在一个事务中完成。

图谱读取 Markdown 链接、frontmatter 的 tags/relations，以及 catalog/project.yaml 中的 knowledge_graph 和 table_rows 子集；它不是完整 YAML 处理器。输出保留生成物标记，遇到非本工具生成的同名文件会拒绝覆盖。`-n` 只生成，不打开浏览器；未指定时用默认浏览器打开。此命令生成静态快照，不替代独立的实时图谱服务。
