import Foundation
import Darwin

private var interrupted: Int32 = 0
private func stderr(_ message: String) { FileHandle.standardError.write(Data((message + "\n").utf8)) }
private let usage = """
Folio — Markdown 索引与目录图谱

用法：folio <命令> [参数]
  index [--full]                  按配置增量更新索引（build 是兼容别名）
  search [词]                    全文检索，显示 path:line
  files [词]                     只列命中文件
  stats                          索引概况
  graph <目录> [--launcher] [-o 文件] [-n]
                                 生成目录图谱；-n 不打开浏览器

通用参数：--db 文件 --config 文件 --json --help --version
检索参数：--ws --repo --path --since --title --limit 20 --per-file 3 --width 120
先在 Folio 设置中选择索引文件夹，或用 --config 指定本机 index.json。
"""

private func version() -> String {
    let executable = FolioExecutable.url
    // Resources/bin/folio shares the app's version; no second version counter.
    let contents = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    if let data = try? Data(contentsOf: contents.appendingPathComponent("Info.plist")),
       let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
       let release = info["CFBundleShortVersionString"] as? String {
        return "folio \(release) (\(info["CFBundleVersion"] as? String ?? "0"))"
    }
    // A development binary outside the .app still has a meaningful explicit identity.
    return "folio development"
}

private struct Options {
    var command = ""
    var database = ProcessInfo.processInfo.environment["MDINDEX_DB"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: FolioIndexConfig.expanded($0)) } ?? FolioIndexEngine.defaultDatabaseURL
    var config = FolioIndexConfig.defaultURL
    var query = FolioIndexQuery()
    var json = false, full = false, launcher = false, noOpen = false
    var output: URL?, root: URL?
    init(_ args: [String]) throws {
        var positional: [String] = [], i = 0
        while i < args.count {
            let option = args[i]
            func value() throws -> String {
                i += 1
                guard i < args.count else { throw FolioIndexError.message("参数 \(option) 需要一个值") }
                return args[i]
            }
            func integer() throws -> Int {
                let raw = try value()
                guard let n = Int(raw) else { throw FolioIndexError.message("参数 \(option) 需要整数：\(raw)") }
                return n
            }
            switch option {
            case "--db": database = URL(fileURLWithPath: FolioIndexConfig.expanded(try value()))
            case "--config": config = URL(fileURLWithPath: FolioIndexConfig.expanded(try value()))
            case "--json": json = true
            case "--full": full = true
            case "--launcher": launcher = true
            case "-n", "--no-open": noOpen = true
            case "-o", "--output": output = URL(fileURLWithPath: FolioIndexConfig.expanded(try value()))
            case "--ws": query.workspace = try value()
            case "--repo": query.repository = try value()
            case "--path": query.path = try value()
            case "--since": query.since = try value()
            case "--title": query.titleOnly = true
            case "--limit": query.limit = try integer()
            case "--per-file": query.perFile = try integer()
            case "--width": query.width = try integer()
            case "--": positional.append(contentsOf: args.dropFirst(i + 1)); i = args.count
            default:
                guard !option.hasPrefix("-") else { throw FolioIndexError.message("不认识的参数：\(option)") }
                positional.append(option)
            }
            i += 1
        }
        guard let name = positional.first, ["index", "build", "stats", "search", "files", "graph"].contains(name) else { throw FolioIndexError.message("请指定 index、search、files、stats 或 graph；运行 folio --help 查看用法。") }
        command = name
        let rest = Array(positional.dropFirst())
        if ["search", "files"].contains(name) {
            guard rest.count <= 1 else { throw FolioIndexError.message("查询词包含空格时请用引号包起来") }
            query.query = rest.first ?? ""
        } else if name == "graph" {
            guard rest.count == 1 else { throw FolioIndexError.message("用法：folio graph <目录> [--launcher] [-o 文件] [-n]") }
            root = URL(fileURLWithPath: FolioIndexConfig.expanded(rest[0]), isDirectory: true)
        } else if !rest.isEmpty { throw FolioIndexError.message("\(name) 不接受位置参数") }
    }
}

private func json<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.keyEncodingStrategy = .convertToSnakeCase; encoder.dateEncodingStrategy = .iso8601
    FileHandle.standardOutput.write(try encoder.encode(value)); FileHandle.standardOutput.write(Data([10]))
}
private func displayPath(_ path: String) -> String { path.replacingOccurrences(of: FolioIndexConfig.home, with: "~") }
private func oneLine(_ value: String) -> String {
    let breaks = Set("\n\r\u{b}\u{c}\u{1c}\u{1d}\u{1e}\u{85}\u{2028}\u{2029}".unicodeScalars)
    return String(String.UnicodeScalarView(value.unicodeScalars.map { breaks.contains($0) ? " ".unicodeScalars.first! : $0 }))
}
private func cut(_ value: String, _ count: Int) -> String {
    let n = count < 0 ? max(0, value.unicodeScalars.count + count) : count
    return FolioIndexEngine.scalarPrefix(value, n)
}
private func padded(_ value: String, _ width: Int) -> String { value + String(repeating: " ", count: max(0, width - value.unicodeScalars.count)) }
private func number(_ value: Int, _ width: Int) -> String { String(repeating: " ", count: max(0, width - String(value).count)) + String(value) }

private func run(_ options: Options) throws {
    switch options.command {
    case "index", "build":
        let config = try FolioIndexConfig.load(from: options.config)
        let result = try FolioIndexEngine.rebuild(config: config, database: options.database, full: options.full, cancelled: { interrupted != 0 })
        if let archive = result.recoveredDatabase { stderr("[recover] 索引库损坏，已移到 \(archive) 并重建") }
        if options.json { try json(result) }
        else { print("Built\tdocs=\(result.count)\trepos=\(result.repositories)\tchars=\(result.characters)\tskipped_binary=\(result.skippedBinary)\tunreadable=\(result.unreadable)\tsymlink_dup=\(result.symlinks)\tbroken_link=\(result.brokenLinks)\t\(String(format: "%.1f", result.elapsed))s\t\(options.database.path)") }
    case "stats":
        let result = try FolioIndexEngine.stats(database: options.database)
        if options.json { try json(result); return }
        print("docs=\(result.count)\trepos=\(result.repositories)\tchars=\(result.characters) (\(String(format: "%.1f", Double(result.characters) / 1024 / 1024)) MB)")
        print("\n-- 按 workspace --")
        for group in result.workspaces { print("  ~/\(padded(group.name, 12)) \(number(group.count, 5)) 篇 \(String(format: "%7.1f", Double(group.characters) / 1024 / 1024)) MB") }
        print("\n-- 篇数 top15 repo --")
        for group in result.topRepositories { print("  \(padded(cut(URL(fileURLWithPath: group.name).lastPathComponent, 34), 36)) \(group.count)") }
        print("\n-- 按最后修改年月 (近12) --")
        for group in result.months { print("  \(group.name) \(group.count)") }
    case "files", "search":
        let q = options.query
        // Keep the legacy diagnostic byte-for-byte for shell callers.
        let documents = try FolioIndexEngine.search(database: options.database, query: q)
        if !q.query.isEmpty, q.query.unicodeScalars.count < 3 { stderr("[note] 查询词 \(q.query.unicodeScalars.count) 字符 < 3, 已自动改走 LIKE (结果等价, 略慢)") }
        if options.json { try json(documents); return }
        if options.command == "files" {
            for doc in documents { print("\(displayPath(doc.path))\t\(URL(fileURLWithPath: doc.repository).lastPathComponent)\t\(doc.mtime)\t\(cut(oneLine(doc.title), 60))") }
            return
        }
        if documents.isEmpty { stderr("(no match)"); return }
        for doc in documents {
            let path = displayPath(doc.path)
            print("\n\(path)   [\(URL(fileURLWithPath: doc.repository).lastPathComponent)] \(doc.mtime)  \(cut(oneLine(doc.title), 60))")
            if !q.query.isEmpty, !q.titleOnly {
                var shown = 0
                for (offset, line) in doc.body.components(separatedBy: "\n").enumerated() where line.contains(q.query) {
                    let text = cut(oneLine(line.trimmingCharacters(in: .whitespacesAndNewlines)), q.width)
                    print("  \(path):\(offset + 1)\t\(text)")
                    shown += 1; if shown >= q.perFile { break }
                }
            }
        }
        fflush(stdout)
        stderr("\n-- \(documents.count) 个文件命中 (limit=\(q.limit)) --")
    case "graph":
        let config = FileManager.default.fileExists(atPath: options.config.path) ? try FolioIndexConfig.load(from: options.config) : FolioIndexConfig()
        let result = try FolioGraphEngine.generate(root: options.root!, output: options.output, launcher: options.launcher, config: config, cancelled: { interrupted != 0 })
        if options.json { try json(["path": result.path]) } else { print(result.path) }
        if !options.noOpen {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/open"); process.arguments = [result.path]
            try process.run(); process.waitUntilExit()
            if process.terminationStatus != 0 { throw FolioIndexError.message("图谱已生成，但默认浏览器未能打开：\(result.path)") }
        }
    default: break
    }
}

@main enum FolioCLI {
    static func main() {
        signal(SIGINT) { _ in interrupted = 1 }
        signal(SIGTERM) { _ in interrupted = 1 }
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--version") { print(version()); exit(0) }
        if args.contains("--help") || args.contains("-h") { print(usage); exit(0) }
        do { try run(Options(args)); exit(0) }
        catch { stderr("[fail] \(error.localizedDescription)"); exit(1) }
    }
}
