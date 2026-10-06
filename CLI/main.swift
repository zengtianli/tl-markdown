import Foundation
import Darwin

private var interrupted: Int32 = 0
private func stderr(_ message: String) { FileHandle.standardError.write(Data((message + "\n").utf8)) }

/// How the command was called is wrong (exit 2), as opposed to an operation that failed (exit 1).
private struct UsageError: Error, LocalizedError { let message: String; var code = "usage"; var errorDescription: String? { message } }
/// An operation that failed for a reason callers may want to branch on (the `code` of the --json reply).
private struct CodedFailure: Error, LocalizedError { let code: String, message: String; var errorDescription: String? { message } }
private func errorCode(_ error: Error) -> String {
    switch error {
    case let failure as CodedFailure: return failure.code
    case let usage as UsageError: return usage.code
    case DocumentError.encoding: return "encoding"
    case DocumentError.readOnly: return "read_only"
    case DocumentError.conflict: return "conflict"
    case DocumentError.missing: return "not_found"
    case DocumentError.state: return "session_unreadable"
    case SessionEditError.noReply: return "window_no_reply"
    case SessionEditError.invalid: return "invalid_value"
    case FolioIndexError.cancelled: return "cancelled"
    default: return "failed"
    }
}
/// The command already printed its result, which reports the failure; only the exit status remains.
private struct ReportedFailure: Error {}

private let overview = """
Folio — Markdown 文档读写、索引、检索与目录图谱。与 Folio 界面共用同一 Swift 引擎：界面给人用，命令给程序和 agent 用。

用法：folio <命令> [参数]        folio <命令> --help 查看单个命令

读取（不改文档、配置、会话记录或索引内容）：
  status                       读回当前状态：版本、配置与索引库、索引文件夹、窗口会话摘要与阅读设置
  read <文档>                  按编辑器的规则读一篇文档：正文、字符数、换行与 BOM、窗口里有无未保存修改
  outline <文档>               文档大纲：各级标题、所在行（与侧栏「大纲」同一解析，跳过代码块）
  search [词]                  全文检索，显示 path:line 与命中行
  files [词]                   只列命中文件
  stats                        索引概况：篇数、最后更新、按 workspace/仓库/月份
  config                       生效的配置、索引库位置、索引文件夹与规则数
  roots                        列出索引文件夹
  session                      Folio 窗口状态：打开的文档（未保存/冲突）、最近文件、关闭的草稿
  settings                     阅读设置的当前值与可取范围（字体、字号、宽度、启动恢复、图片目录、自定义索引）
  recent                       最近文件列表：路径、是否固定、上次打开时间、文件是否还在

写入：
  write <文档>                 按编辑器「保存 / 另存为」的规则写文档（正文来自 --content、--from 或标准输入）
  open <文件>…                 交给 Folio 窗口打开（后台，不抢焦点；-n 只校验不打开；--example 打开示例文档）
  index [--full]               按配置增量更新索引（build 是兼容别名）
  roots add|remove <目录>…     增删索引文件夹，规则同设置界面；下次 index 生效
  settings set <键> <值>…      改阅读设置，同设置面板与 ⌘+ / ⌘-；窗口开着时由窗口应用并立即生效
  recent pin|unpin|remove <文件>…   固定、取消固定、从最近记录移除（文件本身不动）
  recent clear                 清空最近记录
  graph <目录>                 生成静态目录图谱 HTML（-n 或 --json 时不打开浏览器）
  asset add <文档> <图片>      把图片复制到文档旁的图片目录，输出 Markdown 引用（不改文档）

通用参数：--db 文件  --config 文件  --json  --help  --version
没有配置不会扫描任何目录：先 folio roots add <目录>（或在 Folio 设置中添加文件夹），再 folio index。
读索引库的命令以只读方式打开它；SQLite 会刷新库旁它自己的 -shm 共享内存文件，库内容不变。

--json：每个命令输出一个对象（字段 snake_case，时间 ISO 8601 UTC）。
  成功 {"ok": true, …该命令的字段}，字段见 folio <命令> --help
  失败 {"ok": false, "command": 命令, "error": 原因, "code": 短码, "usage": 是否用法错误}，原因同时写到 stderr
  短码：usage、not_found、window_unsaved、window_no_reply、window_outdated、session_unreadable、invalid_value、
        encoding、read_only、conflict、cancelled，其余为 failed

退出码：
  0  成功（检索无命中也算）
  1  操作失败：文件或索引不存在、配置不可读、写入被拒、文档在窗口里有未保存修改、窗口没有应答等
  2  用法错误：不认识的命令或参数、缺少参数、该命令不接受的参数、设置的值不在可取范围

仅在窗口中（没有对应命令）：
  草稿与设置入口：未命名草稿标签（保存前只在窗口里）、打开设置面板、帮助菜单的使用指南与产品主页
  编辑手势：撤销/重做、搜索与替换、查找下一个、加粗/斜体/插入链接、勾选任务列表、代码块复制、点正文里的链接
  视图：侧栏显示与切换（最近/大纲/搜索）、切换标签（手机端为在列表里切换文稿）、源码/即时渲染切换
        （手机端为阅读/编辑与显示 Markdown 源码）、完整预览、点大纲跳转、打开搜索命中后光标跳到该行
  提示与系统面板：关闭提示横幅（手机端为提示条与关闭提示）、在 Finder 中显示、手机端的「授权图片目录…」
  暂缺命令（见 folio status / session 读到的状态）：关闭标签、恢复关闭的草稿到标签页、提示条上的「重新载入」；
  配置与更新窗口里的「使用 iCloud 记住配置」、导出配置、导入配置、检查更新、升级到新版
agent 改 Markdown 用 folio write 或直接写文件：窗口会重新载入未改动的标签，对有未保存修改的标签标记冲突而不覆盖。
"""

private let searchUsage = """
与侧栏搜索（⌘⇧F）同一实现：查询词去掉首尾空白；3 个字及以上走全文索引，更短的逐字匹配（% 与 _ 按字面）；
标题或正文命中即算，命中行不区分大小写，行号从 1 起。按最后修改时间倒序。不写索引。
  --title        只查标题          --ws W       workspace 名（精确）
  --repo R       仓库路径子串      --path P     文件路径子串（均按字面）
  --since D      最后修改时间 ≥ D（YYYY-MM-DD 或 YYYY-MM-DDTHH:MM，本地时间；格式不对是用法错误）
  --limit 20     最多文件数（0 不限）  --per-file 3 每个文件的命中行数（0 不取命中行）
  --width 120    命中行截断宽度（0 不截断，--json 同样适用）
  --body         --json 时附带整篇正文（默认不带）
不给查询词时只按上述条件列出文件；查询词是空白（如空变量）是用法错误。无命中退出 0。
truncated 为 true 表示达到 --limit，可能还有更多命中。
--json：{ok, command, query, mode: fts|like|filter, elapsed, truncated, limit, count, database, database_source,
         files: [{id, path, workspace, repository, title, mtime, lines: [{line, text}], body?}]}
"""

private let commandUsage: [String: String] = [
    "status": """
    用法：folio status [--config 文件] [--db 文件] [--json]
    只读，读回当前状态：命令与 App 版本、状态目录、index.json 与索引库（位置、来源、篇数、最后更新）、
    索引文件夹及是否存在、窗口会话摘要（打开/未保存/冲突的文档数、最近文件数、关闭的草稿数）和阅读设置。
    Folio 不需要系统权限。配置、索引或会话记录不可读时照常输出其余内容，ok 为 false 并退出 1。
    --json：{ok, version, build, app?, state_directory, config: {path, exists, error?}, database: {path, source, exists},
             index?: {count, updated_at, error?}, roots: [{path, exists}],
             session: {path, exists, modified, error?, documents, unsaved, conflicts, recent, closed_drafts},
             settings?: {font_family, font_size, content_width, restore_session, image_folder, note_index_path?}}
    """,
    "read": """
    用法：folio read <文档> [--json]
    只读。与编辑器打开文件同一规则（DocumentIO.open）：只接受 UTF-8 文本，去掉 BOM，换行统一为 LF；
    输出正文。同时报告状态栏上的字符数，以及此文档在 Folio 窗口里是否打开、有无未保存修改或冲突
    （有未保存修改时磁盘上的不是窗口里的最新正文，用 folio session --file <文档> --text 看窗口里的）。
    --json：{ok, path, title, characters, lines, bytes, line_ending: lf|crlf|cr, bom, open_in_folio, dirty, conflict, text}
    """,
    "outline": """
    用法：folio outline <文档> [--json]
    只读。与侧栏「大纲」同一解析：# 到 ###### 开头的标题，跳过围栏代码块里的行。读的是磁盘上的文件
    （规则同 folio read）。文本输出每行「行号<Tab>按级别缩进的标题」。
    --json：{ok, path, count, headings: [{line, level, title, offset}]}（offset 为标题在正文中的 UTF-16 位置）
    """,
    "write": """
    用法：folio write <文档> (--content 文本 | --from 文件 | 标准输入) [--force] [--json]
    与编辑器「保存 / 另存为」同一实现（DocumentIO.save）：已有文件保留原来的换行符与 BOM，原子写入，
    只读文件拒绝；内容相同则不写。文件不存在时新建（等同新建文档后另存为，所在目录须已存在）。
    只写 .md、.markdown、.txt。此文档在 Folio 窗口里有未保存修改或冲突时拒绝（退出 1），避免与本人正在
    写的内容相撞；--force 仍写磁盘，窗口会把该标签标记为冲突而不覆盖窗口里的修改。
    --json：{ok, path, created, changed, characters, bytes, line_ending, bom, open_in_folio}
    """,
    "open": """
    用法：folio open <文件>… [-n] [--json]
          folio open --example [-n] [--json]
    把文件交给 Folio 窗口打开，等同「打开…」、拖入或点最近文件：先按编辑器的规则校验（存在、
    .md/.markdown/.txt、UTF-8），全部通过才交给系统在后台打开（不抢焦点；Folio 未运行时会启动它）。
    --example 等同欢迎页的「打开示例文档」：把随 App 的《欢迎使用.md》复制到状态目录（已有则不覆盖）再打开。
    -n（--no-open）只校验（--example 时仍会复制）不打开。打开后可用 folio session --file <文件> 读回标签状态。
    --json：{ok, files: [路径], app, opened}（app 为所在的 Folio.app；开发版二进制为 bundle id）
    """,
    "index": """
    用法：folio index [--full] [--config 文件] [--db 文件] [--json]
    按 index.json 中的索引文件夹增量更新全文索引（build 是兼容别名）；--full 全部重读并重建。
    与设置里的「更新索引」同一引擎、同一写事务；Ctrl-C 取消时原索引保持不变；另一方正在写入时等待 3 秒后失败。
    --json：{ok, count, changed, unchanged, removed, skipped_binary, unreadable, symlinks, broken_links, elapsed,
             updated_at, recovered_database?, database, database_source, …}
    """,
    "search": "用法：folio search [词] [参数] [--db 文件] [--json]\n" + searchUsage,
    "files": "用法：folio files [词] [参数] [--db 文件] [--json]\n只列命中文件（路径、仓库、修改时间、标题），参数与 search 相同；--json 结构同 search，lines 为空。\n" + searchUsage,
    "stats": """
    用法：folio stats [--db 文件] [--json]
    设置界面显示的篇数与最后更新时间，以及按 workspace、仓库、月份的分布。只读。
    --json：{ok, count, updated_at, characters, repositories, workspaces, top_repositories, months, database, database_source}
    """,
    "config": """
    用法：folio config [--show-rules] [--config 文件] [--db 文件] [--json]
    只读显示所有命令实际使用的设置：index.json 位置、索引库位置及来源（--db > MDINDEX_DB > Folio 设置里的
    自定义索引位置 > 默认）、篇数与最后更新、索引文件夹及是否存在、各类排除规则的条数。
    --show-rules 同时列出规则内容（可能含本机私有目录名）。配置文件不可读时退出 1。
    --json：{ok, state_directory, config: {path, exists, error?}, database: {path, source, exists}, index?,
             roots: [{path, exists}], rules: {…条数}, rule_values?}
    """,
    "roots": """
    用法：folio roots [list] [--config 文件] [--json]
          folio roots add <目录>… [--config 文件] [--json]
          folio roots remove <目录>… [--config 文件] [--json]
    与设置界面「添加文件夹 / 移除」同一规则：先重读 index.json，路径展开 ~ 并规范化，去重后原子写入（0600）；
    配置不可读时拒绝修改；add 只接受存在的文件夹。修改在下次 folio index（或设置里「更新索引」）后生效。
    已存在的 add 和不在列表中的 remove 不算失败，见 unchanged / not_found。
    --json：{ok, action, config, roots, added, removed, unchanged, not_found, changed}
    """,
    "settings": """
    用法：folio settings [--json]
          folio settings set <键> <值> [<键> <值>…] [--json]
    设置面板「阅读与编辑」里的各项，存在 session.json 的 settings 里，窗口与命令读写同一份。不带 set 只读。
      font_family       system | serif | mono（系统字体 / 宋体 / 等宽字体）
      font_size         13 到 26 的整数；larger / smaller 同菜单的放大字号（⌘+）/ 缩小字号（⌘-），到头不再变
      content_width     560 到 1300、20 的倍数
      restore_session   true | false（启动时恢复上次打开的文件）
      image_folder      文档旁的相对目录，不能是绝对路径或含 ..
      note_index_path   自定义索引文件；default 或空字符串回到默认索引
    值不在范围内是用法错误（退出 2），什么都不改。Folio 窗口开着时由窗口应用：编辑器与设置面板立即跟着变，
    并马上存盘；窗口没开时直接改 session.json（其余内容原样保留）。applied_by 说明走的哪条路。窗口 5 秒内
    没有应答，或开着的是装新版之前启动的旧窗口（不接收命令的修改）时退出 1，不写入。
    --json：{ok, session_file, exists, settings: {font_family, font_size, content_width, restore_session, image_folder,
             note_index_path?}, limits: {font_family: [..], font_size: [最小, 最大], content_width: [最小, 最大],
             content_width_step}}；set 另有 changed: [键]、applied_by: window|file
    """,
    "recent": """
    用法：folio recent [list] [--json]
          folio recent pin|unpin|remove <文件>… [--json]
          folio recent clear [--json]
    侧栏「最近」的列表与它的右键菜单：固定到顶部 / 取消固定、从最近记录移除、清空最近记录。只改记录，
    不动文件本身。顺序同侧栏：固定的在前，其余按上次打开时间倒序。exists 为 false 的是已移动或删除的文件；
    「重新定位文件…」等于 folio recent remove <旧路径> 再 folio open <新路径>。
    已是所要状态的记在 unchanged，不在列表里的记在 not_found，都不算失败。窗口开着时由窗口应用并立即
    显示，没开时直接改 session.json（此时程序坞菜单里的系统最近文档不会被清，下次在窗口里清空时一并清）。
    窗口没有应答或是旧窗口时退出 1，不写入。
    --json：{ok, session_file, exists, count, recent: [{path, name, pinned, opened, exists}]}；
             写入另有 action、changed: [路径]、unchanged、not_found、cleared（清掉的条数）、applied_by: window|file
    """,
    "session": """
    用法：folio session [--file 路径] [--text] [--json]
    只读显示 Folio 最近保存的窗口状态（session.json，最多比界面晚约 0.25 秒）：打开的文档（当前、未保存、冲突、
    提示、字符数）、最近文件（是否固定）、关闭后保留的草稿、阅读设置，以及记录损坏时另存的 session-unreadable-*.json。
    --file 只看某个文件；--text 附带未保存文档和草稿的正文。修改某个 Markdown 前可先确认它在 Folio 中没有未保存修改。
    本命令从不写 session.json。阅读设置用 folio settings set 改，最近记录用 folio recent 改；标签的关闭、
    恢复与重新载入目前只能在窗口里做。
    --json：{ok, session_file, exists, modified, active_id, documents, recent, closed_drafts, settings, unreadable_records}
    """,
    "graph": """
    用法：folio graph <目录> [--launcher] [-o 文件] [-n] [--config 文件] [--json]
    生成静态目录图谱（默认 <目录>/知识图谱.html），与菜单「文件 → 生成目录图谱…」同一引擎和本机受限规则。
    --launcher 另写可双击重新生成的 知识图谱.command；遇到非本工具生成的同名文件拒绝覆盖。
    默认生成后用浏览器打开；-n 或 --json 时只生成不打开。
    --json：{ok, path, launcher?, directories, files, nodes, edges, metadata_warnings}
    """,
    "asset": """
    用法：folio asset add <文档> <图片> [--folder 相对目录] [--json]
    与编辑器插入图片（菜单、拖入、粘贴）同一规则：文件须为图片类型且小于 40 MB，复制到文档旁的图片目录
    （默认取设置里的「图片目录」，通常 assets），命名 image-<随机>.<扩展名>；目录不能是绝对路径或含 ..。
    只新建图片文件，不修改文档；输出应插入的 Markdown 引用，如 ![图片](<assets/image-1a2b3c4d5e6f.png>)。
    --json：{ok, document, source, path, folder, markdown, bytes}
    """,
]
private let commands = ["status", "read", "outline", "write", "open", "index", "build", "search", "files", "stats", "config", "roots", "session", "settings", "recent", "graph", "asset"]
private let valueOptions: Set<String> = ["--db", "--config", "--ws", "--repo", "--path", "--since", "--limit", "--per-file", "--width", "-o", "--output", "--folder", "--file", "--content", "--from"]
private let searchOptions: Set<String> = ["--ws", "--repo", "--path", "--since", "--title", "--limit", "--per-file", "--width", "--body"]
private let allowedOptions: [String: Set<String>] = [
    "index": ["--full"], "search": searchOptions, "files": searchOptions, "stats": [], "config": ["--show-rules"],
    "roots": [], "session": ["--text", "--file"], "graph": ["--launcher", "-o", "--output", "-n", "--no-open"], "asset": ["--folder"],
    "status": [], "read": [], "outline": [], "write": ["--content", "--from", "--force"], "open": ["-n", "--no-open", "--example"],
    "settings": [], "recent": [],
]

/// The app bundle this binary ships in (Resources/bin/folio shares the app's version; no second counter).
private func bundled() -> (app: URL?, release: String, build: String)? {
    let contents = FolioExecutable.url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    guard let data = try? Data(contentsOf: contents.appendingPathComponent("Info.plist")),
          let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let release = info["CFBundleShortVersionString"] as? String else { return nil }
    // Only a real bundle (…/Folio.app/Contents) is an app to hand files to. A development binary in
    // the repository still reads its version from the source Info.plist, but names no app.
    let app = contents.deletingLastPathComponent()
    return (contents.lastPathComponent == "Contents" && app.pathExtension == "app" ? app : nil, release, info["CFBundleVersion"] as? String ?? "0")
}
private func version() -> String {
    // A development binary outside the .app still has a meaningful explicit identity.
    bundled().map { "folio \($0.release) (\($0.build))" } ?? "folio development"
}

private struct Options {
    var command = "", invoked = "", action = ""
    var explicitDatabase: String?
    var config = FolioIndexConfig.defaultURL
    var query = FolioIndexQuery()
    var json = false, full = false, launcher = false, noOpen = false, showRules = false, text = false, force = false, example = false
    var edit: SessionEdit?
    var output: URL?, root: URL?, folder: String?, file: String?, content: String?, from: String?
    var operands: [String] = []
    init(_ args: [String]) throws {
        var positional: [String] = [], seen: [String] = [], i = 0
        while i < args.count {
            let option = args[i]
            func value() throws -> String {
                i += 1
                guard i < args.count else { throw UsageError(message: "参数 \(option) 需要一个值") }
                return args[i]
            }
            func count() throws -> Int {
                let raw = try value()
                guard let n = Int(raw), n >= 0 else { throw UsageError(message: "参数 \(option) 需要非负整数：\(raw)") }
                return n
            }
            // Index dates are "YYYY-MM-DDTHH:MM" text; a malformed bound would compare as text and
            // silently match nothing, so only a real date (optionally with a time) is accepted.
            func since() throws -> String {
                let raw = try value()
                guard Self.validDate(raw) else { throw UsageError(message: "参数 --since 需要日期 YYYY-MM-DD 或 YYYY-MM-DDTHH:MM：\(raw)") }
                return raw
            }
            if option.hasPrefix("-"), option != "--", option != "-" { seen.append(option) }
            switch option {
            case "--db": explicitDatabase = try value()
            case "--config": config = URL(fileURLWithPath: FolioIndexConfig.expanded(try value()))
            case "--json": json = true
            case "--full": full = true
            case "--launcher": launcher = true
            case "-n", "--no-open": noOpen = true
            case "-o", "--output": output = URL(fileURLWithPath: FolioIndexConfig.expanded(try value()))
            case "--ws": query.workspace = try value()
            case "--repo": query.repository = try value()
            case "--path": query.path = try value()
            case "--since": query.since = try since()
            case "--title": query.titleOnly = true
            case "--limit": query.limit = try count()  // 0 = no limit, like --width 0
            case "--per-file": query.perFile = try count()
            case "--width": query.width = try count()
            case "--body": query.includeBody = true
            case "--show-rules": showRules = true
            case "--text": text = true
            case "--folder": folder = try value()
            case "--file": file = try value()
            case "--content": content = try value()
            case "--from": from = try value()
            case "--force": force = true
            case "--example": example = true
            case "--": positional.append(contentsOf: args.dropFirst(i + 1)); i = args.count
            default:
                guard !option.hasPrefix("-") || option == "-" else { throw UsageError(message: "不认识的参数：\(option)") }
                positional.append(option)
            }
            i += 1
        }
        guard let name = positional.first else { throw UsageError(message: "请指定命令（status、read、outline、write、open、search、files、stats、config、roots、session、settings、recent、index、graph、asset）；运行 folio --help 查看用法。") }
        guard commands.contains(name) else { throw UsageError(message: "不认识的命令：\(name)；运行 folio --help 查看用法。") }
        invoked = name; command = name == "build" ? "index" : name
        let allowed = allowedOptions[command, default: []].union(["--db", "--config", "--json"])
        if let bad = seen.first(where: { !allowed.contains($0) }) { throw UsageError(message: "\(name) 不接受参数 \(bad)；运行 folio \(name) --help 查看用法。") }
        let rest = Array(positional.dropFirst())
        switch command {
        case "search", "files":
            guard rest.count <= 1 else { throw UsageError(message: "查询词包含空格时请用引号包起来") }
            // An empty variable must not turn into "list the whole index": no query word lists by
            // the filters, a blank one is refused (the sidebar shows nothing for it either).
            if let word = rest.first, word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw UsageError(message: "查询词是空白；要按条件列出文件请不给查询词")
            }
            query.query = rest.first ?? ""
        case "graph":
            guard rest.count == 1 else { throw UsageError(message: "用法：folio graph <目录> [--launcher] [-o 文件] [-n]") }
            root = URL(fileURLWithPath: FolioIndexConfig.expanded(rest[0]), isDirectory: true)
        case "roots":
            action = rest.first ?? "list"
            switch action {
            case "list": guard rest.count <= 1 else { throw UsageError(message: "roots list 不接受其他参数") }
            case "add", "remove": guard rest.count >= 2 else { throw UsageError(message: "用法：folio roots \(action) <目录>…") }
            default: throw UsageError(message: "roots 只支持 list、add、remove")
            }
            operands = Array(rest.dropFirst())
        case "read", "write", "outline":
            guard rest.count == 1 else { throw UsageError(message: "用法：folio \(command) <文档>；运行 folio \(command) --help 查看参数") }
            if command == "write", content != nil, from != nil { throw UsageError(message: "--content 与 --from 只能给一个") }
            operands = rest
        case "open":
            guard example ? rest.isEmpty : !rest.isEmpty else { throw UsageError(message: "用法：folio open <文件>… [-n]，或 folio open --example [-n]") }
            operands = rest
        case "settings":
            action = rest.first ?? "list"
            guard action == "list" || action == "set" else { throw UsageError(message: "settings 只支持 set；不带参数时读取当前值") }
            if action == "list" { guard rest.count <= 1 else { throw UsageError(message: "settings 读取时不接受其他参数") } }
            else { edit = try Self.settingsEdit(Array(rest.dropFirst())) }
        case "recent":
            action = rest.first ?? "list"
            operands = Array(rest.dropFirst())
            switch action {
            case "list", "clear": guard operands.isEmpty else { throw UsageError(message: "recent \(action) 不接受其他参数") }
            case "pin", "unpin", "remove": guard !operands.isEmpty else { throw UsageError(message: "用法：folio recent \(action) <文件>…") }
            default: throw UsageError(message: "recent 只支持 list、pin、unpin、remove、clear")
            }
        case "asset":
            guard rest.first == "add", rest.count == 3 else { throw UsageError(message: "用法：folio asset add <文档> <图片> [--folder 相对目录]") }
            action = "add"; operands = Array(rest.dropFirst())
        default:
            guard rest.isEmpty else { throw UsageError(message: "\(name) 不接受位置参数") }
        }
    }
    /// `<键> <值>` pairs for `settings set`; the limits are the settings panel's (SessionEdits.validate).
    static func settingsEdit(_ pairs: [String]) throws -> SessionEdit {
        guard !pairs.isEmpty, pairs.count % 2 == 0 else { throw UsageError(message: "用法：folio settings set <键> <值> [<键> <值>…]；运行 folio settings --help 查看键") }
        var edit = SessionEdit(), seen: Set<String> = []
        for i in stride(from: 0, to: pairs.count, by: 2) {
            let key = pairs[i], value = pairs[i + 1]
            guard seen.insert(key).inserted else { throw UsageError(message: "\(key) 给了两次") }
            func number() throws -> Double {
                guard let n = Double(value), n.isFinite else { throw UsageError(message: "\(key) 需要数字：\(value)") }
                return n
            }
            switch key {
            case "font_family": edit.fontFamily = value
            case "font_size":
                if value == "larger" { edit.fontSizeStep = 1 } else if value == "smaller" { edit.fontSizeStep = -1 } else { edit.fontSize = try number() }
            case "content_width": edit.contentWidth = try number()
            case "restore_session":
                switch value.lowercased() {
                case "true", "on", "yes", "1": edit.restoreSession = true
                case "false", "off", "no", "0": edit.restoreSession = false
                default: throw UsageError(message: "restore_session 需要 true 或 false：\(value)")
                }
            case "image_folder": edit.imageFolder = value
            case "note_index_path": edit.noteIndexPath = value == "default" ? "" : value.trimmingCharacters(in: .whitespaces)
            default: throw UsageError(message: "不认识的设置：\(key)；可用 font_family、font_size、content_width、restore_session、image_folder、note_index_path")
            }
        }
        do { try SessionEdits.validate(edit) } catch { throw UsageError(message: error.localizedDescription, code: "invalid_value") }
        return edit
    }
    static func validDate(_ raw: String) -> Bool {
        let parts = raw.split(separator: "T", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return false }
        let day = parts[0].split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard day.count == 3, day[0].count == 4, day[1].count == 2, day[2].count == 2,
              let y = Int(day[0]), let m = Int(day[1]), let d = Int(day[2]), y > 0, (1...12).contains(m) else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let first = calendar.date(from: DateComponents(year: y, month: m, day: 1)),
              let days = calendar.range(of: .day, in: .month, for: first), days.contains(d) else { return false }
        guard parts.count == 2 else { return true }
        let time = parts[1].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard time.count == 2, time[0].count == 2, time[1].count == 2, let h = Int(time[0]), let mi = Int(time[1]) else { return false }
        return (0...23).contains(h) && (0...59).contains(mi)
    }
    /// Only commands that read or write the index resolve it; the saved Settings path is read lazily.
    var database: (url: URL, source: String) {
        FolioIndexConfig.resolveDatabase(explicit: explicitDatabase, setting: FolioIndexConfig.savedIndexSetting())
    }
}

// MARK: - Output
private let encoder: JSONEncoder = {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.keyEncodingStrategy = .convertToSnakeCase; encoder.dateEncodingStrategy = .iso8601
    return encoder
}()
private func emit<T: Encodable>(_ value: T) throws {
    FileHandle.standardOutput.write(try encoder.encode(value)); FileHandle.standardOutput.write(Data([10]))
}
/// `{ok: …, <fields of extra>, <fields of value>}` in one object.
private struct Reply<T: Encodable, E: Encodable>: Encodable {
    let value: T, extra: E
    func encode(to encoder: Encoder) throws { try extra.encode(to: encoder); try value.encode(to: encoder) }
}
private struct Located: Encodable { var ok = true; let database: String; let databaseSource: String }
private struct ErrorReply: Encodable { var ok = false; let command: String?; let error: String; let code: String; let usage: Bool }

private func displayPath(_ path: String) -> String { FolioIndexConfig.inside(path, FolioIndexConfig.home) ? "~" + path.dropFirst(FolioIndexConfig.home.count) : path }
private func oneLine(_ value: String) -> String {
    let breaks = Set("\n\r\u{b}\u{c}\u{1c}\u{1d}\u{1e}\u{85}\u{2028}\u{2029}".unicodeScalars)
    return String(String.UnicodeScalarView(value.unicodeScalars.map { breaks.contains($0) ? " ".unicodeScalars.first! : $0 }))
}
private func cut(_ value: String, _ count: Int) -> String {
    let n = count < 0 ? max(0, value.unicodeScalars.count + count) : count
    return FolioIndexEngine.scalarPrefix(value, n)
}
/// --width 0 keeps the whole line.
private func clipped(_ value: String, _ width: Int) -> String { width == 0 ? oneLine(value) : cut(oneLine(value), width) }
private func padded(_ value: String, _ width: Int) -> String { value + String(repeating: " ", count: max(0, width - value.unicodeScalars.count)) }
private func number(_ value: Int, _ width: Int) -> String { String(repeating: " ", count: max(0, width - String(value).count)) + String(value) }
private func localTime(_ date: Date?) -> String {
    guard let date else { return "未知" }
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: date)
}

// MARK: - Commands
private func run(_ options: Options) throws {
    switch options.command {
    case "index":
        let config = try FolioIndexConfig.load(from: options.config)
        let database = options.database
        let result = try FolioIndexEngine.rebuild(config: config, database: database.url, full: options.full, cancelled: { interrupted != 0 })
        if let archive = result.recoveredDatabase { stderr("[recover] 索引库损坏，已移到 \(archive) 并重建") }
        if options.json { try emit(Reply(value: result, extra: Located(database: database.url.path, databaseSource: database.source))) }
        else { print("Built\tdocs=\(result.count)\trepos=\(result.repositories)\tchars=\(result.characters)\tskipped_binary=\(result.skippedBinary)\tunreadable=\(result.unreadable)\tsymlink_dup=\(result.symlinks)\tbroken_link=\(result.brokenLinks)\t\(String(format: "%.1f", result.elapsed))s\t\(database.url.path)") }
    case "stats":
        let database = options.database
        let result = try FolioIndexEngine.stats(database: database.url)
        if options.json { try emit(StatsReport(result, database)); return }
        print("docs=\(result.count)\trepos=\(result.repositories)\tchars=\(result.characters) (\(String(format: "%.1f", Double(result.characters) / 1024 / 1024)) MB)\tupdated=\(localTime(result.updatedAt))")
        print("\n-- 按 workspace --")
        for group in result.workspaces { print("  ~/\(padded(group.name, 12)) \(number(group.count, 5)) 篇 \(String(format: "%7.1f", Double(group.characters) / 1024 / 1024)) MB") }
        print("\n-- 篇数 top15 repo --")
        for group in result.topRepositories { print("  \(padded(cut(URL(fileURLWithPath: group.name).lastPathComponent, 34), 36)) \(group.count)") }
        print("\n-- 按最后修改年月 (近12) --")
        for group in result.months { print("  \(group.name) \(group.count)") }
    case "files", "search":
        var q = options.query
        if options.command == "files" { q.perFile = 0 }
        let database = options.database
        let result = try FolioIndexEngine.find(database: database.url, query: q)
        // Keep the legacy diagnostic byte-for-byte for shell callers.
        if result.mode == .like { stderr("[note] 查询词 \(result.query.count) 字符 < \(FolioIndexEngine.trigramMinimum), 已自动改走 LIKE (结果等价, 略慢)") }
        if options.json { try emit(SearchReport(options.command, result, q, database)); return }
        if options.command == "files" {
            for doc in result.files { print("\(displayPath(doc.path))\t\(URL(fileURLWithPath: doc.repository).lastPathComponent)\t\(doc.mtime)\t\(cut(oneLine(doc.title), 60))") }
            return
        }
        if result.files.isEmpty { stderr("(no match)"); return }
        for doc in result.files {
            let path = displayPath(doc.path)
            print("\n\(path)   [\(URL(fileURLWithPath: doc.repository).lastPathComponent)] \(doc.mtime)  \(cut(oneLine(doc.title), 60))")
            for hit in doc.lines { print("  \(path):\(hit.line)\t\(clipped(hit.text, q.width))") }
        }
        fflush(stdout)
        stderr("\n-- \(result.files.count) 个文件命中 (limit=\(q.limit)) --")
    case "config":
        try config(options)
    case "status":
        try status(options)
    case "read":
        try readDocument(options)
    case "outline":
        try outline(options)
    case "write":
        try writeDocument(options)
    case "open":
        try openDocuments(options)
    case "roots":
        try roots(options)
    case "session":
        try session(options)
    case "settings":
        try settings(options)
    case "recent":
        try recent(options)
    case "graph":
        let config = FileManager.default.fileExists(atPath: options.config.path) ? try FolioIndexConfig.load(from: options.config) : FolioIndexConfig()
        let result = try FolioGraphEngine.generateReport(root: options.root!, output: options.output, launcher: options.launcher, config: config, cancelled: { interrupted != 0 })
        if options.json { try emit(Reply(value: result, extra: OK())) } else { print(result.path) }
        if !options.noOpen && !options.json {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/open"); process.arguments = [result.path]
            try process.run(); process.waitUntilExit()
            if process.terminationStatus != 0 { throw FolioIndexError.message("图谱已生成，但默认浏览器未能打开：\(result.path)") }
        }
    case "asset":
        try asset(options)
    default: break
    }
}
private struct OK: Encodable { var ok = true }

private struct StatsReport: Encodable {
    var ok = true
    let count: Int, updatedAt: Date?, characters: Int, repositories: Int
    let workspaces: [FolioIndexGroup], topRepositories: [FolioIndexGroup], months: [FolioIndexGroup]
    let database: String, databaseSource: String
    init(_ s: FolioIndexStats, _ db: (url: URL, source: String)) {
        count = s.count; updatedAt = s.updatedAt; characters = s.characters; repositories = s.repositories
        workspaces = s.workspaces; topRepositories = s.topRepositories; months = s.months
        database = db.url.path; databaseSource = db.source
    }
}
private struct SearchReport: Encodable {
    struct Line: Encodable { let line: Int; let text: String }
    struct File: Encodable {
        let id: Int, path: String, workspace: String, repository: String, title: String, mtime: String
        let lines: [Line], body: String?
    }
    var ok = true
    let command: String, query: String, mode: FolioSearchMode, elapsed: Double, truncated: Bool, limit: Int, count: Int
    let database: String, databaseSource: String
    let files: [File]
    init(_ command: String, _ r: FolioSearchResult, _ q: FolioIndexQuery, _ db: (url: URL, source: String)) {
        self.command = command; query = r.query; mode = r.mode; elapsed = r.elapsed; truncated = r.truncated
        limit = q.limit; count = r.files.count; database = db.url.path; databaseSource = db.source
        files = r.files.map { hit in
            File(id: hit.id, path: hit.path, workspace: hit.workspace, repository: hit.repository, title: hit.title, mtime: hit.mtime,
                 lines: hit.lines.map { Line(line: $0.line, text: clipped($0.text, q.width)) }, body: hit.body)
        }
    }
}

// MARK: config
private struct ConfigReport: Encodable {
    struct File: Encodable { let path: String; let exists: Bool; let error: String? }
    struct Database: Encodable { let path: String; let source: String; let exists: Bool }
    struct Index: Encodable { let count: Int; let updatedAt: Date?; let error: String? }
    struct Root: Encodable { let path: String; let exists: Bool }
    struct Rules: Encodable {
        let skipDirectories: Int, skipPaths: Int, fullTextExcludedPaths: Int, skipDirectorySuffixes: Int
        let skipHidden: Bool, restrictedNames: Int, restrictedPrefixes: Int, restrictedSubstrings: Int
    }
    var ok: Bool
    let stateDirectory: String
    let config: File, database: Database, index: Index?, roots: [Root], rules: Rules
    let ruleValues: FolioIndexConfig?
}
private func configReport(_ options: Options) -> (report: ConfigReport, loaded: FolioIndexConfig, error: String?) {
    let fm = FileManager.default, url = options.config
    var loaded = FolioIndexConfig(), configError: String?
    let configExists = fm.fileExists(atPath: url.path)
    if configExists {
        do { loaded = try FolioIndexConfig.load(from: url) } catch { configError = error.localizedDescription }
    }
    let database = options.database, databaseExists = fm.fileExists(atPath: database.url.path)
    var index: ConfigReport.Index?
    if databaseExists {
        do { let s = try FolioIndexEngine.summary(database: database.url); index = .init(count: s.count, updatedAt: s.updatedAt, error: nil) }
        catch { index = .init(count: 0, updatedAt: nil, error: error.localizedDescription) }
    }
    let roots = loaded.roots.map { root -> ConfigReport.Root in
        var directory: ObjCBool = false
        return .init(path: root, exists: fm.fileExists(atPath: FolioIndexConfig.expanded(root), isDirectory: &directory) && directory.boolValue)
    }
    let rules = ConfigReport.Rules(skipDirectories: loaded.skipDirectories.count, skipPaths: loaded.skipPaths.count, fullTextExcludedPaths: loaded.fullTextExcludedPaths.count,
                                   skipDirectorySuffixes: loaded.skipDirectorySuffixes.count, skipHidden: loaded.skipHidden, restrictedNames: loaded.restrictedNames.count,
                                   restrictedPrefixes: loaded.restrictedPrefixes.count, restrictedSubstrings: loaded.restrictedSubstrings.count)
    let ok = configError == nil && index?.error == nil
    let report = ConfigReport(ok: ok, stateDirectory: FolioIndexConfig.stateDirectory.path, config: .init(path: url.path, exists: configExists, error: configError),
                              database: .init(path: database.url.path, source: database.source, exists: databaseExists), index: index, roots: roots, rules: rules,
                              ruleValues: options.showRules && configError == nil ? loaded : nil)
    return (report, loaded, configError ?? index?.error)
}
private func config(_ options: Options) throws {
    let (report, loaded, failure) = configReport(options)
    let url = options.config, configExists = report.config.exists, configError = report.config.error
    let database = options.database, index = report.index, roots = report.roots, rules = report.rules, ok = report.ok
    if options.json { try emit(report) }
    else {
        let sources = ["option": "--db 参数", "environment": "MDINDEX_DB", "settings": "Folio 设置的自定义位置", "default": "默认位置"]
        print("配置文件  \(displayPath(url.path))\(configExists ? "" : "（尚未创建：还没有添加索引文件夹）")")
        if let configError { print("  无法读取：\(configError)") }
        print("索引库    \(displayPath(database.url.path))（\(sources[database.source] ?? database.source)）")
        if let index { print(index.error.map { "  无法读取：\($0)" } ?? "索引      \(index.count) 篇，最后更新 \(localTime(index.updatedAt))") }
        else { print("索引      尚未建立（folio index）") }
        print("索引文件夹（\(roots.count)）")
        for root in roots { print("  \(displayPath(root.path))\(root.exists ? "" : "  [不存在]")") }
        print("规则      跳过目录 \(rules.skipDirectories) · 排除路径 \(rules.skipPaths) · 仅全文排除 \(rules.fullTextExcludedPaths) · 目录后缀 \(rules.skipDirectorySuffixes) · 跳过隐藏 \(rules.skipHidden ? "是" : "否")")
        print("图谱受限  名称 \(rules.restrictedNames) · 前缀 \(rules.restrictedPrefixes) · 名称片段 \(rules.restrictedSubstrings)")
        if options.showRules, configError == nil {
            for (name, values) in [("跳过目录", loaded.skipDirectories), ("排除路径", loaded.skipPaths), ("仅全文排除", loaded.fullTextExcludedPaths), ("目录后缀", loaded.skipDirectorySuffixes),
                                   ("受限名称", loaded.restrictedNames), ("受限前缀", loaded.restrictedPrefixes), ("受限片段", loaded.restrictedSubstrings)] where !values.isEmpty {
                print("  \(name)：\(values.joined(separator: ", "))")
            }
        }
    }
    if !ok { stderr("[fail] \(failure ?? "")"); throw ReportedFailure() }
}

// MARK: status
private struct StatusReport: Encodable {
    struct Session: Encodable {
        let path: String, exists: Bool, modified: Date?, error: String?
        let documents: Int, unsaved: Int, conflicts: Int, recent: Int, closedDrafts: Int
    }
    var ok: Bool
    let version: String, build: String?, app: String?, stateDirectory: String
    let config: ConfigReport.File, database: ConfigReport.Database, index: ConfigReport.Index?, roots: [ConfigReport.Root]
    let session: Session, settings: SessionReport.Settings?
}
private func status(_ options: Options) throws {
    let (config, _, configFailure) = configReport(options)
    let disk = SessionDisk(directory: FolioIndexConfig.stateDirectory), fm = FileManager.default
    var snapshot: SessionSnapshot?, sessionError: String?
    do { snapshot = try disk.read() } catch { sessionError = error.localizedDescription }
    let docs = snapshot?.documents ?? []
    let session = StatusReport.Session(path: disk.file.path, exists: fm.fileExists(atPath: disk.file.path),
                                       modified: (try? fm.attributesOfItem(atPath: disk.file.path))?[.modificationDate] as? Date, error: sessionError,
                                       documents: docs.count, unsaved: docs.filter(\.dirty).count, conflicts: docs.filter(\.conflict).count,
                                       recent: snapshot?.recent.count ?? 0, closedDrafts: snapshot?.closedDrafts?.count ?? 0)
    let settings = snapshot.map { s in
        SessionReport.Settings(fontFamily: s.settings.fontFamily, fontSize: s.settings.fontSize, contentWidth: s.settings.contentWidth,
                               restoreSession: s.settings.restoreSession, imageFolder: s.settings.imageFolder, noteIndexPath: s.settings.noteIndexPath)
    }
    let bundle = bundled(), failure = configFailure ?? sessionError
    let report = StatusReport(ok: failure == nil, version: bundle?.release ?? "development", build: bundle?.build, app: bundle?.app?.path,
                              stateDirectory: config.stateDirectory, config: config.config, database: config.database, index: config.index,
                              roots: config.roots, session: session, settings: settings)
    if options.json { try emit(report) }
    else {
        print(version() + ((bundle?.app).map { "  \(displayPath($0.path))" } ?? ""))
        print("状态目录  \(displayPath(report.stateDirectory))")
        print("配置文件  \(displayPath(report.config.path))\(report.config.exists ? "" : "（尚未创建）")\(report.config.error.map { "  无法读取：\($0)" } ?? "")")
        print("索引库    \(displayPath(report.database.path))（\(report.database.source)）" + (report.index.map { $0.error.map { "  无法读取：\($0)" } ?? "  \($0.count) 篇，最后更新 \(localTime($0.updatedAt))" } ?? "  尚未建立"))
        print("索引文件夹（\(report.roots.count)）")
        for root in report.roots { print("  \(displayPath(root.path))\(root.exists ? "" : "  [不存在]")") }
        if let sessionError { print("会话记录  无法读取：\(sessionError)") }
        else { print("会话记录  \(session.exists ? "保存于 " + localTime(session.modified) : "尚无")：打开 \(session.documents) · 未保存 \(session.unsaved) · 冲突 \(session.conflicts) · 最近 \(session.recent) · 关闭的草稿 \(session.closedDrafts)") }
        if let s = settings { print("阅读设置  字体 \(s.fontFamily ?? "system") · 字号 \(Int(s.fontSize)) · 宽度 \(Int(s.contentWidth)) · 启动恢复 \(s.restoreSession ? "是" : "否") · 图片目录 \(s.imageFolder)") }
        print("权限      不需要系统权限")
    }
    if let failure { stderr("[fail] \(failure)"); throw ReportedFailure() }
}

// MARK: documents (read / write / open)
private let documentExtensions: Set<String> = ["md", "markdown", "txt"]
private func documentURL(_ raw: String) -> URL { URL(fileURLWithPath: FolioIndexConfig.expanded(raw)).standardizedFileURL.resolvingSymlinksInPath() }
private func endingName(_ ending: String) -> String { ending == "\r\n" ? "crlf" : (ending == "\r" ? "cr" : "lf") }
/// What the window holds for this path, from the app's own session record (read-only).
private func windowState(_ path: String) -> (open: Bool, dirty: Bool, conflict: Bool) {
    guard let doc = (try? SessionDisk(directory: FolioIndexConfig.stateDirectory).read())?.documents.first(where: { $0.path == path }) else { return (false, false, false) }
    return (true, doc.dirty, doc.conflict)
}
private func existingFile(_ url: URL) -> Bool {
    var directory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && !directory.boolValue
}
private struct ReadReport: Encodable {
    var ok = true
    let path: String, title: String, characters: Int, lines: Int, bytes: Int, lineEnding: String, bom: Bool
    let openInFolio: Bool, dirty: Bool, conflict: Bool, text: String
}
private func readDocument(_ options: Options) throws {
    let url = documentURL(options.operands[0])
    guard existingFile(url) else { throw CodedFailure(code: "not_found", message: "文档不存在：\(url.path)") }
    let doc = try DocumentIO.open(url), window = windowState(url.path)
    // Lines as an editor counts them: a trailing newline does not start another line.
    let lines = doc.text.isEmpty ? 0 : doc.text.split(separator: "\n", omittingEmptySubsequences: false).count - (doc.text.hasSuffix("\n") ? 1 : 0)
    if options.json {
        try emit(ReadReport(path: url.path, title: doc.title, characters: doc.text.count, lines: lines,
                            bytes: doc.diskData?.count ?? 0, lineEnding: endingName(doc.lineEnding), bom: doc.bom,
                            openInFolio: window.open, dirty: window.dirty, conflict: window.conflict, text: doc.text))
        return
    }
    FileHandle.standardOutput.write(Data(doc.text.utf8))
    if window.dirty || window.conflict { stderr("[note] 此文档在 Folio 窗口里有未保存修改\(window.conflict ? "（冲突）" : "")；窗口里的正文见 folio session --file … --text") }
}
private struct OutlineReport: Encodable {
    struct Heading: Encodable { let line: Int, level: Int, title: String, offset: Int }
    var ok = true
    let path: String, count: Int, headings: [Heading]
}
private func outline(_ options: Options) throws {
    let url = documentURL(options.operands[0])
    guard existingFile(url) else { throw CodedFailure(code: "not_found", message: "文档不存在：\(url.path)") }
    let headings = MarkdownOutline.headings(in: try DocumentIO.open(url).text)
    if options.json { try emit(OutlineReport(path: url.path, count: headings.count, headings: headings.map { .init(line: $0.line, level: $0.level, title: $0.title, offset: $0.offset) })) }
    else { for item in headings { print("\(item.line)\t\(String(repeating: "  ", count: item.level - 1))\(item.title)") } }
}
private struct WriteReport: Encodable {
    var ok = true
    let path: String, created: Bool, changed: Bool, characters: Int, bytes: Int, lineEnding: String, bom: Bool, openInFolio: Bool
}
private func writeDocument(_ options: Options) throws {
    let url = documentURL(options.operands[0]), fm = FileManager.default
    guard documentExtensions.contains(url.pathExtension.lowercased()) else { throw FolioIndexError.message("只写 .md、.markdown、.txt：\(url.lastPathComponent)") }
    var raw: String
    if let content = options.content { raw = content }
    else {
        let data: Data
        if let from = options.from { data = try Data(contentsOf: URL(fileURLWithPath: FolioIndexConfig.expanded(from))) }
        else {
            guard isatty(0) == 0 else { throw UsageError(message: "需要正文：--content 文本、--from 文件，或从标准输入传入") }
            data = FileHandle.standardInput.readDataToEndOfFile()
        }
        guard let decoded = String(data: data, encoding: .utf8), !decoded.contains("\0") else { throw DocumentError.encoding }
        raw = decoded
    }
    // The editor holds text with \n only; the file keeps its own line ending and BOM on save.
    if raw.hasPrefix("\u{FEFF}") { raw.removeFirst() }
    let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    let window = windowState(url.path)
    if (window.dirty || window.conflict) && !options.force {
        throw CodedFailure(code: "window_unsaved", message: "此文档在 Folio 窗口里有未保存修改\(window.conflict ? "（冲突）" : "")，未写入；先在窗口里保存或处理，或加 --force（窗口会标记冲突，不覆盖窗口里的修改）")
    }
    var directory: ObjCBool = false
    let exists = fm.fileExists(atPath: url.path, isDirectory: &directory)
    if exists && directory.boolValue { throw FolioIndexError.message("是文件夹，不是文档：\(url.path)") }
    var doc: OpenDocument, changed = true
    if exists {
        doc = try DocumentIO.open(url); changed = doc.text != text
        doc.text = text; try DocumentIO.save(&doc)
    } else {
        guard fm.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &directory), directory.boolValue else {
            throw FolioIndexError.message("所在文件夹不存在：\(url.deletingLastPathComponent().path)")
        }
        doc = OpenDocument(path: nil); doc.text = text
        try DocumentIO.save(&doc, to: url)
    }
    if options.json {
        // Resolve again: a path that did not exist before the save may now resolve differently.
        try emit(WriteReport(path: documentURL(options.operands[0]).path, created: !exists, changed: changed, characters: text.count, bytes: doc.diskData?.count ?? 0,
                             lineEnding: endingName(doc.lineEnding), bom: doc.bom, openInFolio: window.open))
    } else { print(documentURL(options.operands[0]).path); stderr(!exists ? "已新建。" : (changed ? "已保存。" : "内容相同，未写入。")) }
}
private struct OpenReport: Encodable { var ok = true; let files: [String], app: String, opened: Bool }
private func openDocuments(_ options: Options) throws {
    var files: [String] = []
    var requested = options.operands
    if options.example {
        // Resources/bin/folio sits beside the bundle's Resources/欢迎使用.md, the file the welcome page opens.
        let original = FolioExecutable.url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(ExampleDocument.name)
        guard existingFile(original) else { throw CodedFailure(code: "not_found", message: "示例文档随 Folio.app 提供；这个命令不在应用包里") }
        requested = [try ExampleDocument.install(from: original, into: FolioIndexConfig.stateDirectory).path]
    }
    for raw in requested {
        let url = documentURL(raw)
        guard existingFile(url) else { throw CodedFailure(code: "not_found", message: "文件不存在：\(url.path)") }
        guard documentExtensions.contains(url.pathExtension.lowercased()) else { throw FolioIndexError.message("Folio 只打开 .md、.markdown、.txt：\(url.lastPathComponent)") }
        _ = try DocumentIO.open(url)
        files.append(url.path)
    }
    // The bundle this command ships in; a development binary asks LaunchServices for the installed app.
    let app = bundled()?.app?.path, target = app.map { ["-a", $0] } ?? ["-b", "cyou.tianli.TLMarkdown"]
    if !options.noOpen {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/open"); process.arguments = ["-g"] + target + files
        try process.run(); process.waitUntilExit()
        if process.terminationStatus != 0 { throw FolioIndexError.message("系统未能把文件交给 Folio（open 退出 \(process.terminationStatus)）") }
    }
    if options.json { try emit(OpenReport(files: files, app: app ?? "cyou.tianli.TLMarkdown", opened: !options.noOpen)) }
    else { for file in files { print(file) }; stderr(options.noOpen ? "校验通过，未打开（-n）。" : "已交给 Folio 打开。") }
}

// MARK: roots
private struct RootsReport: Encodable {
    var ok = true
    let action: String, config: String, roots: [String]
    let added: [String], removed: [String], unchanged: [String], notFound: [String], changed: Bool
}
private func roots(_ options: Options) throws {
    let change: FolioRootsChange
    switch options.action {
    case "add": change = try FolioIndexConfig.addRoots(options.operands, at: options.config)
    case "remove": change = try FolioIndexConfig.removeRoots(options.operands, at: options.config)
    default:
        // list: the same read the Settings folder list shows; a missing file is an empty list.
        var listed = FolioRootsChange(configPath: options.config.path)
        if FileManager.default.fileExists(atPath: options.config.path) { listed.roots = try FolioIndexConfig.load(from: options.config).roots }
        change = listed
    }
    if options.json {
        try emit(RootsReport(action: options.action, config: change.configPath, roots: change.roots, added: change.added, removed: change.removed,
                             unchanged: change.unchanged, notFound: change.notFound, changed: change.changed))
        return
    }
    for path in change.added { print("已加入  \(displayPath(path))") }
    for path in change.removed { print("已移除  \(displayPath(path))") }
    for path in change.unchanged { print("已在列表中  \(displayPath(path))") }
    for path in change.notFound { stderr("[note] 不在索引文件夹中：\(path)") }
    if options.action == "list" { for path in change.roots { print(displayPath(path)) } }
    else if change.changed { stderr("索引文件夹已保存（\(change.roots.count) 个）；运行 folio index 或在设置中「更新索引」后生效。") }
}

// MARK: session
private struct SessionReport: Encodable {
    struct Document: Encodable {
        let id: String, path: String?, title: String, active: Bool, dirty: Bool, conflict: Bool, message: String, characters: Int, text: String?
    }
    struct Recent: Encodable { let path: String, name: String, pinned: Bool, opened: Date }
    struct Draft: Encodable { let id: String, path: String?, title: String, dirty: Bool, characters: Int, text: String? }
    struct Settings: Encodable {
        let fontFamily: String?, fontSize: Double, contentWidth: Double, restoreSession: Bool, imageFolder: String, noteIndexPath: String?
    }
    var ok = true
    let sessionFile: String, exists: Bool, modified: Date?, activeId: String?
    let documents: [Document], recent: [Recent], closedDrafts: [Draft], settings: Settings
    let unreadableRecords: [String]
}
private func sessionFailureRecords(_ directory: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasPrefix("session-unreadable-") && $0.hasSuffix(".json") }.sorted()
}
private func session(_ options: Options) throws {
    let disk = SessionDisk(directory: FolioIndexConfig.stateDirectory)
    let fm = FileManager.default
    let exists = fm.fileExists(atPath: disk.file.path)
    let modified = (try? fm.attributesOfItem(atPath: disk.file.path))?[.modificationDate] as? Date
    let records = sessionFailureRecords(disk.directory)
    // SessionDisk.read is the decoder the app uses at launch; it never writes or creates anything.
    let snapshot: SessionSnapshot
    do { snapshot = try disk.read() }
    catch {
        if options.json { try emit(ErrorReply(command: "session", error: error.localizedDescription, code: errorCode(error), usage: false)) }
        stderr("[fail] \(error.localizedDescription)"); if !records.isEmpty { stderr("另存的损坏记录：\(records.joined(separator: ", "))") }
        throw ReportedFailure()
    }
    let target = options.file.map { URL(fileURLWithPath: FolioIndexConfig.expanded($0)).standardizedFileURL.resolvingSymlinksInPath().path }
    func wanted(_ path: String?) -> Bool { target == nil || path == target }
    let documents = snapshot.documents.filter { wanted($0.path) }.map { doc in
        SessionReport.Document(id: doc.id, path: doc.path, title: doc.title, active: doc.id == snapshot.activeID, dirty: doc.dirty, conflict: doc.conflict,
                               message: doc.message, characters: doc.text.count, text: options.text && doc.dirty ? doc.text : nil)
    }
    let recent = snapshot.recent.filter { wanted($0.path) }.map { SessionReport.Recent(path: $0.path, name: $0.name, pinned: $0.pinned, opened: $0.opened) }
    let drafts = (snapshot.closedDrafts ?? []).filter { wanted($0.path) }.map { doc in
        SessionReport.Draft(id: doc.id, path: doc.path, title: doc.title, dirty: doc.dirty, characters: doc.text.count, text: options.text ? doc.text : nil)
    }
    let s = snapshot.settings
    let report = SessionReport(sessionFile: disk.file.path, exists: exists, modified: modified, activeId: snapshot.activeID, documents: documents, recent: recent,
                               closedDrafts: drafts, settings: .init(fontFamily: s.fontFamily, fontSize: s.fontSize, contentWidth: s.contentWidth,
                                                                     restoreSession: s.restoreSession, imageFolder: s.imageFolder, noteIndexPath: s.noteIndexPath),
                               unreadableRecords: records)
    if options.json { try emit(report); return }
    if !exists { print("Folio 尚无会话记录：\(displayPath(disk.file.path))") }
    else { print("会话记录  \(displayPath(disk.file.path))（保存于 \(localTime(modified))）") }
    print("\n-- 打开的文档（\(documents.count)）--")
    for doc in documents {
        var flags: [String] = []
        if doc.active { flags.append("当前") }
        if doc.conflict { flags.append("冲突") }
        if doc.dirty { flags.append(doc.path == nil ? "未命名草稿" : "未保存") }
        print("  \(doc.path.map(displayPath) ?? doc.title)  \(doc.characters) 字符\(flags.isEmpty ? "" : "  [" + flags.joined(separator: "·") + "]")\(doc.message.isEmpty ? "" : "  " + oneLine(doc.message))")
        if let text = doc.text { print(text.split(separator: "\n", omittingEmptySubsequences: false).map { "    | " + $0 }.joined(separator: "\n")) }
    }
    print("\n-- 最近文件（\(recent.count)）--")
    for item in recent { print("  \(item.pinned ? "[固定] " : "")\(displayPath(item.path))") }
    print("\n-- 关闭的草稿（\(drafts.count)）--")
    for draft in drafts {
        print("  \(draft.path.map(displayPath) ?? draft.title)  \(draft.characters) 字符")
        if let text = draft.text { print(text.split(separator: "\n", omittingEmptySubsequences: false).map { "    | " + $0 }.joined(separator: "\n")) }
    }
    if !records.isEmpty { print("\n另存的损坏记录：\(records.joined(separator: ", "))") }
}

// MARK: settings and recent (session.json, shared with the window)
/// A Folio window started by a build from before the window held the session lock: it would write
/// its own copy of session.json over a file edit. Only the default state directory can have one.
private func outdatedWindowRunning() -> Bool {
    guard (ProcessInfo.processInfo.environment["TL_MARKDOWN_STATE_DIR"] ?? "").isEmpty else { return false }
    var pids = [pid_t](repeating: 0, count: 8192)
    let bytes = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
    var path = [CChar](repeating: 0, count: 4096)
    for pid in pids.prefix(max(0, Int(bytes))) where pid > 0 {
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
        if String(cString: path).hasSuffix(".app/Contents/MacOS/TLMarkdown") { return true }
    }
    return false
}
/// One writer at a time: the window when it is running (it applies the edit itself and shows it),
/// otherwise this command, holding the same lock while it rewrites the file through SessionDisk.
private func applySessionEdit(_ edit: SessionEdit) throws -> (outcome: SessionEditOutcome, by: String) {
    let state = FolioIndexConfig.stateDirectory
    guard let lock = SessionLock.acquire(in: state) else { return (try SessionRequests.send(edit, state: state), "window") }
    defer { withExtendedLifetime(lock) {} }
    if outdatedWindowRunning() {
        throw CodedFailure(code: "window_outdated", message: "开着的 Folio 窗口是装新版之前启动的，不接收命令的修改，也会覆盖对记录文件的修改；退出并重新打开 Folio 后再试。未写入。")
    }
    let disk = SessionDisk(directory: state)
    var snapshot = try disk.read()   // an unreadable record is left as it is
    let outcome = try SessionEdits.apply(edit, settings: &snapshot.settings, recent: &snapshot.recent)
    if outcome.changed { try disk.write(snapshot) }
    return (outcome, "file")
}
private struct SettingsReport: Encodable {
    struct Limits: Encodable { let fontFamily: [String], fontSize: [Int], contentWidth: [Int], contentWidthStep: Int }
    var ok = true
    let sessionFile: String, exists: Bool, settings: SessionReport.Settings, limits: Limits
    let changed: [String]?, appliedBy: String?
}
private func settingsView(_ s: EditorSettings) -> SessionReport.Settings {
    .init(fontFamily: s.fontFamily, fontSize: s.fontSize, contentWidth: s.contentWidth, restoreSession: s.restoreSession, imageFolder: s.imageFolder, noteIndexPath: s.noteIndexPath)
}
private func settings(_ options: Options) throws {
    let disk = SessionDisk(directory: FolioIndexConfig.stateDirectory)
    var current: EditorSettings, changed: [String]?, by: String?
    if let edit = options.edit {
        let result = try applySessionEdit(edit)
        current = result.outcome.settings; changed = result.outcome.settingsChanged; by = result.by
    } else { current = try disk.read().settings }
    let limits = SettingsReport.Limits(fontFamily: SessionEdits.fontFamilies, fontSize: [Int(SessionEdits.fontSizes.lowerBound), Int(SessionEdits.fontSizes.upperBound)],
                                       contentWidth: [Int(SessionEdits.contentWidths.lowerBound), Int(SessionEdits.contentWidths.upperBound)], contentWidthStep: Int(SessionEdits.contentWidthStep))
    if options.json {
        try emit(SettingsReport(sessionFile: disk.file.path, exists: FileManager.default.fileExists(atPath: disk.file.path), settings: settingsView(current), limits: limits, changed: changed, appliedBy: by))
        return
    }
    print("font_family\t\(current.fontFamily ?? "system")")
    print("font_size\t\(Int(current.fontSize))")
    print("content_width\t\(Int(current.contentWidth))")
    print("restore_session\t\(current.restoreSession)")
    print("image_folder\t\(current.imageFolder)")
    print("note_index_path\t\(current.noteIndexPath ?? "")")
    if let changed, let by { stderr(changed.isEmpty ? "已是所要的值，未改动。" : "已修改 \(changed.joined(separator: "、"))（\(by == "window" ? "由 Folio 窗口应用" : "写入会话记录")）。") }
}
private struct RecentReport: Encodable {
    struct Item: Encodable { let path: String, name: String, pinned: Bool, opened: Date, exists: Bool }
    var ok = true
    let sessionFile: String, exists: Bool, count: Int, recent: [Item]
    let action: String?, changed: [String]?, unchanged: [String]?, notFound: [String]?, cleared: Int?, appliedBy: String?
}
private func recent(_ options: Options) throws {
    let disk = SessionDisk(directory: FolioIndexConfig.stateDirectory), fm = FileManager.default
    var list: [RecentFile], outcome: SessionEditOutcome?, by: String?
    if options.action == "list" { list = try disk.read().recent }
    else {
        // The window may run in another folder: name files by absolute path.
        let paths = options.operands.map { URL(fileURLWithPath: FolioIndexConfig.expanded($0)).path }
        var edit = SessionEdit()
        switch options.action {
        case "pin": edit.pin = paths
        case "unpin": edit.unpin = paths
        case "remove": edit.remove = paths
        default: edit.clearRecent = true
        }
        let result = try applySessionEdit(edit)
        list = result.outcome.recent; outcome = result.outcome; by = result.by
    }
    let items = list.map { RecentReport.Item(path: $0.path, name: $0.name, pinned: $0.pinned, opened: $0.opened, exists: fm.fileExists(atPath: $0.path)) }
    if options.json {
        try emit(RecentReport(sessionFile: disk.file.path, exists: fm.fileExists(atPath: disk.file.path), count: items.count, recent: items,
                              action: outcome == nil ? nil : options.action, changed: outcome?.recentChanged, unchanged: outcome?.recentUnchanged,
                              notFound: outcome?.notFound, cleared: outcome.map { $0.cleared }, appliedBy: by))
        return
    }
    for item in items { print("\(item.pinned ? "[固定] " : "")\(displayPath(item.path))\(item.exists ? "" : "  [文件不在]")") }
    if let outcome, let by {
        for path in outcome.notFound { stderr("[note] 不在最近记录中：\(path)") }
        let count = outcome.recentChanged.count + outcome.cleared
        stderr(count == 0 ? "没有需要改动的记录。" : "已改动 \(count) 条最近记录（\(by == "window" ? "由 Folio 窗口应用" : "写入会话记录")）。")
    }
}

// MARK: asset
private struct AssetReport: Encodable {
    var ok = true
    let document: String, source: String, path: String, folder: String, markdown: String, bytes: Int
}
private func asset(_ options: Options) throws {
    let fm = FileManager.default
    let document = URL(fileURLWithPath: FolioIndexConfig.expanded(options.operands[0])).standardizedFileURL.resolvingSymlinksInPath()
    let image = URL(fileURLWithPath: FolioIndexConfig.expanded(options.operands[1]))
    var directory: ObjCBool = false
    guard fm.fileExists(atPath: document.path, isDirectory: &directory), !directory.boolValue else { throw FolioIndexError.message("文档不存在：\(document.path)") }
    guard fm.fileExists(atPath: image.path, isDirectory: &directory), !directory.boolValue else { throw FolioIndexError.message("图片不存在：\(image.path)") }
    guard DocumentIO.isImageFile(image) else { throw DocumentError.imageType }
    // The default folder is the one Settings shows; an unreadable session falls back to the app default.
    let folder = options.folder ?? ((try? SessionDisk(directory: FolioIndexConfig.stateDirectory).read())?.settings.imageFolder ?? EditorSettings().imageFolder)
    let size = (try fm.attributesOfItem(atPath: image.path)[.size] as? NSNumber)?.intValue ?? 0
    guard size < DocumentIO.imageByteLimit else { throw DocumentError.imageTooLarge }
    let data = try Data(contentsOf: image)
    let stored = try DocumentIO.storeImage(data, extension: image.pathExtension, document: OpenDocument(path: document.path), folder: folder)
    if options.json { try emit(AssetReport(document: document.path, source: image.path, path: stored.url.path, folder: folder, markdown: stored.markdown, bytes: data.count)) }
    else { print(stored.markdown); stderr("已复制到 \(displayPath(stored.url.path))；文档未修改。") }
}

// MARK: - Entry
/// The first word before `--` that is not an option value names the command.
private func commandName(_ args: [String]) -> String? {
    var i = 0
    while i < args.count {
        let arg = args[i]
        if arg == "--" { return nil }
        if valueOptions.contains(arg) { i += 2; continue }
        if !arg.hasPrefix("-") { return arg }
        i += 1
    }
    return nil
}

@main enum FolioCLI {
    static func main() {
        signal(SIGINT) { _ in interrupted = 1 }
        signal(SIGTERM) { _ in interrupted = 1 }
        let args = Array(CommandLine.arguments.dropFirst())
        let flags = Array(args.prefix { $0 != "--" })
        if flags.contains("--version") { print(version()); exit(0) }
        if flags.contains("--help") || flags.contains("-h") {
            let name = commandName(args).map { $0 == "build" ? "index" : $0 }
            print(name.flatMap { commandUsage[$0] } ?? overview); exit(0)
        }
        let json = flags.contains("--json")
        var command: String?
        do { let options = try Options(args); command = options.invoked; try run(options); exit(0) }
        catch is ReportedFailure { exit(1) }
        catch let error as UsageError {
            if json { try? emit(ErrorReply(command: command ?? commandName(args), error: error.message, code: error.code, usage: true)) }
            stderr("[usage] \(error.message)"); exit(2)
        }
        catch {
            if json { try? emit(ErrorReply(command: command, error: error.localizedDescription, code: errorCode(error), usage: false)) }
            stderr("[fail] \(error.localizedDescription)"); exit(1)
        }
    }
}
