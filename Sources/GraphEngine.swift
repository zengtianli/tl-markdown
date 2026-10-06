import Foundation
import CryptoKit
import Darwin

/// A deliberately bounded YAML reader for graph catalogs and frontmatter.
/// Supports mappings, sequences, flow collections, quoted scalars and block
/// text; it does not resolve anchors, tags, includes or executable extensions.
enum FolioGraphYAML {
    struct Invalid: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }
    private struct Line { var indent: Int; var text: String; var raw: String }
    static func parse(_ source: String) throws -> [String: Any] {
        var parser = Parser(source)
        guard parser.lines.count <= 50_000 else { throw Invalid(message: "YAML 超出行数限制") }
        guard !parser.lines.isEmpty else { return [:] }
        let value = try parser.block(parser.lines[0].indent, depth: 0)
        guard parser.index == parser.lines.count, let mapping = value as? [String: Any] else {
            throw Invalid(message: "YAML 顶层必须是映射，且缩进必须完整")
        }
        return mapping
    }
    private struct Parser {
        var lines: [Line]
        var index = 0
        init(_ source: String) {
            lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").compactMap { raw in
                let clean = FolioGraphYAML.withoutComment(raw).trimmingCharacters(in: .whitespaces)
                guard !clean.isEmpty, clean != "---", clean != "..." else { return nil }
                return Line(indent: raw.prefix(while: { $0 == " " }).count, text: clean, raw: raw)
            }
        }
        mutating func block(_ indent: Int, depth: Int) throws -> Any {
            guard depth < 48 else { throw Invalid(message: "YAML 嵌套过深") }
            if lines[index].text == "-" || lines[index].text.hasPrefix("- ") {
                var values: [Any] = []
                while index < lines.count, lines[index].indent == indent,
                      lines[index].text == "-" || lines[index].text.hasPrefix("- ") {
                    let text = String(lines[index].text.dropFirst()).trimmingCharacters(in: .whitespaces)
                    index += 1
                    if text.isEmpty {
                        values.append(index < lines.count && lines[index].indent > indent ? try block(lines[index].indent, depth: depth + 1) : NSNull())
                    } else if FolioGraphYAML.pair(text) != nil {
                        var mapping: [String: Any] = [:]
                        try entry(text, indent: indent + 2, depth: depth, into: &mapping)
                        if index < lines.count, lines[index].indent > indent {
                            let rest = try block(lines[index].indent, depth: depth + 1)
                            guard let rest = rest as? [String: Any] else { throw Invalid(message: "YAML 列表项缩进无效") }
                            for (key, value) in rest {
                                guard mapping[key] == nil else { throw Invalid(message: "YAML 出现重复键") }
                                mapping[key] = value
                            }
                        }
                        values.append(mapping)
                    } else { values.append(try FolioGraphYAML.scalar(text, depth: depth + 1)) }
                }
                return values
            }
            var mapping: [String: Any] = [:]
            while index < lines.count, lines[index].indent == indent {
                let text = lines[index].text
                index += 1
                try entry(text, indent: indent, depth: depth, into: &mapping)
            }
            return mapping
        }
        mutating func entry(_ text: String, indent: Int, depth: Int, into mapping: inout [String: Any]) throws {
            guard let (rawKey, rawValue) = FolioGraphYAML.pair(text),
                  let key = try FolioGraphYAML.scalar(rawKey, depth: depth + 1) as? String,
                  !key.isEmpty, mapping[key] == nil else { throw Invalid(message: "YAML 键或缩进无效") }
            if rawValue.isEmpty {
                if index < lines.count, lines[index].indent > indent {
                    mapping[key] = try block(lines[index].indent, depth: depth + 1)
                } else if index < lines.count, lines[index].indent == indent, lines[index].text.hasPrefix("- ") {
                    // YAML permits an indentless sequence as a mapping value.
                    mapping[key] = try block(indent, depth: depth + 1)
                } else { mapping[key] = NSNull() }
            } else if ["|", "|-", "|+", ">", ">-", ">+"].contains(rawValue) {
                var textLines: [String] = []
                let contentIndent = index < lines.count ? lines[index].indent : indent + 2
                while index < lines.count, lines[index].indent > indent {
                    textLines.append(String(lines[index].raw.dropFirst(contentIndent)))
                    index += 1
                }
                mapping[key] = textLines.joined(separator: rawValue.hasPrefix(">") ? " " : "\n") + (rawValue.hasSuffix("-") ? "" : "\n")
            } else { mapping[key] = try FolioGraphYAML.scalar(rawValue, depth: depth + 1) }
        }
    }
    private static func withoutComment(_ value: String) -> String {
        var quote: Character?; var escaped = false; var result = ""
        for character in value {
            if escaped { result.append(character); escaped = false; continue }
            if character == "\\", quote == "\"" { escaped = true; result.append(character); continue }
            if let active = quote { if character == active { quote = nil } }
            else if character == "\"" || character == "'" { quote = character }
            else if character == "#", result.isEmpty || result.last?.isWhitespace == true { break }
            result.append(character)
        }
        return result
    }
    private static func split(_ value: String, separator: Character) -> [String] {
        var parts: [String] = []; var current = ""; var quote: Character?; var depth = 0; var escaped = false
        for character in value {
            if escaped { current.append(character); escaped = false; continue }
            if character == "\\", quote == "\"" { escaped = true; current.append(character); continue }
            if let active = quote { if character == active { quote = nil } }
            else if character == "\"" || character == "'" { quote = character }
            else if character == "[" || character == "{" { depth += 1 }
            else if character == "]" || character == "}" { depth -= 1 }
            else if character == separator, depth == 0 { parts.append(current); current = ""; continue }
            current.append(character)
        }
        parts.append(current)
        return parts
    }
    private static func pair(_ value: String) -> (String, String)? {
        var quote: Character?; var escaped = false; var depth = 0
        for index in value.indices {
            let character = value[index]
            if escaped { escaped = false; continue }
            if character == "\\", quote == "\"" { escaped = true; continue }
            if let active = quote { if character == active { quote = nil }; continue }
            if character == "\"" || character == "'" { quote = character; continue }
            if character == "[" || character == "{" { depth += 1 }
            if character == "]" || character == "}" { depth -= 1 }
            let next = value.index(after: index)
            if character == ":", depth == 0, next == value.endIndex || value[next].isWhitespace {
                return (String(value[..<index]).trimmingCharacters(in: .whitespaces), String(value[next...]).trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }
    private static func scalar(_ source: String, depth: Int) throws -> Any {
        guard depth < 48 else { throw Invalid(message: "YAML 嵌套过深") }
        let value = source.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("["), value.hasSuffix("]") {
            let body = String(value.dropFirst().dropLast())
            return body.trimmingCharacters(in: .whitespaces).isEmpty ? [] : try split(body, separator: ",").map { try scalar($0, depth: depth + 1) }
        }
        if value.hasPrefix("{"), value.hasSuffix("}") {
            var result: [String: Any] = [:]
            for item in split(String(value.dropFirst().dropLast()), separator: ",") where !item.trimmingCharacters(in: .whitespaces).isEmpty {
                guard let (key, raw) = pair(item), let key = try scalar(key, depth: depth + 1) as? String, result[key] == nil else { throw Invalid(message: "YAML 行内映射无效") }
                result[key] = try scalar(raw, depth: depth + 1)
            }
            return result
        }
        if value.hasPrefix("\""), value.hasSuffix("\"") {
            guard let data = value.data(using: .utf8), let text = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String else { throw Invalid(message: "YAML 双引号字符串无效") }
            return text
        }
        if value.hasPrefix("'"), value.hasSuffix("'") { return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
        if value == "true" || value == "True" { return true }
        if value == "false" || value == "False" { return false }
        if value == "null" || value == "~" { return NSNull() }
        if value.hasPrefix("&") || value.hasPrefix("*") || value.hasPrefix("!") { throw Invalid(message: "YAML 不支持别名、锚点或类型标签") }
        // Keep numeric-looking titles/identifiers as text; this subset has no numeric fields.
        return value
    }
}

struct FolioGraphReport: Codable {
    var path: String
    var launcher: String?
    var directories: Int
    var files: Int
    var nodes: Int
    var edges: Int
    var metadataWarnings: Int
}

enum FolioGraphEngine {
    static let marker = "<meta name=\"folder-graph-generator\" content=\"folio-folder-graph-v1\">"
    private static let legacyMarker = "<meta name=\"folder-graph-generator\" content=\"shared-folder-graph-v1\">"
    private static let commandMarker = "# Generated by Folio folder graph"
    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }
    private struct Entry {
        var url: URL; var directory: Bool; var size: Int64; var modified: Int64
        var metadata: [String: Any] = [:]; var catalog: [String: Any] = [:]
        var text = ""; var links: [String] = []; var tags: [String] = []
    }
    /// Generates an offline document, never opens a browser or takes UI focus.
    static func generate(root: URL, output: URL? = nil, launcher: Bool = false,
                         config: FolioIndexConfig, cancelled: @escaping () -> Bool = { false }) throws -> URL {
        URL(fileURLWithPath: try generateReport(root: root, output: output, launcher: launcher, config: config, cancelled: cancelled).path)
    }
    /// The same generation, plus the counts the page itself shows (for `folio graph --json`).
    static func generateReport(root: URL, output: URL? = nil, launcher: Bool = false,
                               config: FolioIndexConfig, cancelled: @escaping () -> Bool = { false }) throws -> FolioGraphReport {
        let root = lexical(root)
        let output = lexical(output ?? root.appendingPathComponent("知识图谱.html"))
        let command = root.appendingPathComponent("知识图谱.command")
        guard try safeInfo(root).st_mode & S_IFMT == S_IFDIR else { throw Failure(message: "请选择存在的真实目录；不跟随软链") }
        guard output != root, output != command else { throw Failure(message: "图谱输出不能替换目录或刷新入口") }
        try checkOutput(output, markers: [marker, legacyMarker])
        if launcher { try checkOutput(command, markers: [commandMarker, "# Generated by shared folder_graph.py"]) }
        let scanner = Scanner(root: root, output: output, config: config, cancelled: cancelled)
        let payload = try scanner.payload()
        let template = try String(contentsOf: templateURL(), encoding: .utf8)
        guard template.components(separatedBy: "__PAYLOAD__").count == 2 else { throw Failure(message: "图谱模板缺少唯一数据入口") }
        let raw = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
        let data = String(decoding: raw, as: UTF8.self).replacingOccurrences(of: "<", with: "\\u003c")
        let html = template.replacingOccurrences(of: "__PAYLOAD__", with: data).replacingOccurrences(of: "<head>", with: "<head>\n" + marker)
        guard !cancelled() else { throw CancellationError() }
        // Recheck immediately before replacement. Temporary names are exclusive,
        // unpredictable and owned by this operation, never an existing .tmp file.
        try checkOutput(output, markers: [marker, legacyMarker])
        if launcher { try checkOutput(command, markers: [commandMarker, "# Generated by shared folder_graph.py"]) }
        try atomicWrite(html, to: output, mode: 0o600)
        if launcher {
            let script = "#!/bin/zsh\n" + commandMarker + "\nset -eu\nexport PATH=\"$HOME/.local/bin:$PATH\"\ncd \"${0:A:h}\"\nfolio graph \"$PWD\" --launcher\n"
            try atomicWrite(script, to: command, mode: 0o700)
        }
        let status = payload["status"] as? [String: Any], counts = status?["counts"] as? [String: Any]
        let coverage = payload["coverage"] as? [String: Any], atlas = payload["atlas"] as? [String: Any]
        return FolioGraphReport(path: output.path, launcher: launcher ? command.path : nil,
                                directories: counts?["directory"] as? Int ?? 0, files: counts?["file"] as? Int ?? 0,
                                nodes: coverage?["rendered_nodes"] as? Int ?? 0, edges: (atlas?["edges"] as? [Any])?.count ?? 0,
                                metadataWarnings: (payload["metadata_warnings"] as? [Any])?.count ?? 0)
    }
    private static func templateURL() throws -> URL {
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["FOLIO_GRAPH_TEMPLATE"] { candidates.append(URL(fileURLWithPath: override)) }
        if let resources = Bundle.main.resourceURL { candidates.append(resources.appendingPathComponent("graph-view.html")) }
        let executable = FolioExecutable.url
        candidates.append(executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("graph-view.html"))
        guard let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { throw Failure(message: "没有找到随 Folio 安装的图谱模板") }
        return found
    }
    private static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined().prefix(20).description }
    /// Lexical "." / ".." cleanup. Foundation's standardizedFileURL also drops a
    /// leading /private, turning /private/var into the /var symlink that the
    /// O_NOFOLLOW walk below must reject.
    static func lexical(_ url: URL) -> URL { URL(fileURLWithPath: url.lexicalPath) }
    private static func under(_ path: String, _ root: String) -> Bool { path == root || path.hasPrefix(root == "/" ? "/" : root + "/") }
    /// Walk from the filesystem root with O_NOFOLLOW on every component. Reads
    /// through a symlinked ancestor are rejected as well as a symlink leaf.
    private static func descriptor(_ url: URL, directory: Bool = false) throws -> Int32 {
        var current = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard current >= 0 else { throw Failure(message: "无法读取文件系统根目录") }
        let parts = lexical(url).pathComponents.filter { $0 != "/" }
        for (offset, part) in parts.enumerated() {
            let next = openat(current, part, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC | (offset < parts.count - 1 || directory ? O_DIRECTORY : 0))
            close(current)
            guard next >= 0 else { throw Failure(message: "目录或文件无法安全读取；不跟随软链") }
            current = next
        }
        return current
    }
    private static func safeInfo(_ url: URL) throws -> stat {
        let fd = try descriptor(url); defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw Failure(message: "无法读取文件信息") }
        return info
    }
    private static func safeText(_ url: URL) throws -> String {
        let fd = try descriptor(url); defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= 1_048_576 else { throw Failure(message: "元数据必须是不超过 1 MiB 的普通文件") }
        var bytes = [UInt8](repeating: 0, count: Int(info.st_size) + 1)
        let count = bytes.withUnsafeMutableBytes { buffer in read(fd, buffer.baseAddress, buffer.count) }
        guard count >= 0, count <= 1_048_576 else { throw Failure(message: "文件读取失败或读取期间发生变化") }
        let data = bytes.prefix(count)
        guard !data.contains(0) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    private static func checkOutput(_ url: URL, markers: [String]) throws {
        let parent = try descriptor(url.deletingLastPathComponent(), directory: true); defer { close(parent) }
        var info = stat()
        if fstatat(parent, url.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw Failure(message: "无法读取输出位置") }; return
        }
        guard info.st_mode & S_IFMT == S_IFREG else { throw Failure(message: "输出位置不是普通文件或是软链，未覆盖") }
        let fd = openat(parent, url.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw Failure(message: "无法检查已有图谱，未覆盖") }; defer { close(fd) }
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = bytes.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
        guard count >= 0, markers.contains(where: { String(decoding: bytes.prefix(max(0, count)), as: UTF8.self).contains($0) }) else {
            throw Failure(message: "同名文件不是本工具生成，未覆盖；请另存现有文件或选择其他输出位置")
        }
    }
    private static func atomicWrite(_ text: String, to target: URL, mode: mode_t) throws {
        let parent = try descriptor(target.deletingLastPathComponent(), directory: true); defer { close(parent) }
        let temporary = ".folio-graph-" + UUID().uuidString + ".tmp"
        let fd = openat(parent, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode)
        guard fd >= 0 else { throw Failure(message: "无法创建图谱临时文件") }
        defer { close(fd); unlinkat(parent, temporary, 0) }
        let data = Data(text.utf8)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                guard count > 0 else { throw Failure(message: "图谱写入失败") }; offset += count
            }
        }
        guard fsync(fd) == 0, renameat(parent, temporary, parent, target.lastPathComponent) == 0 else { throw Failure(message: "无法保存图谱") }
    }
    private final class Scanner {
        let root: URL; let output: URL; let config: FolioIndexConfig; let cancelled: () -> Bool
        var entries: [String: Entry] = [:]
        var warnings: [[String: Any]] = []; var unresolved: [[String: Any]] = []
        init(root: URL, output: URL, config: FolioIndexConfig, cancelled: @escaping () -> Bool) {
            self.root = root; self.output = output; self.config = config; self.cancelled = cancelled
        }
        func checkCancellation() throws { if cancelled() { throw CancellationError() } }
        func identifier(_ path: String) -> String { path == root.path ? "home" : "p" + digest(path) }
        func allowed(_ path: String) -> Bool {
            guard under(path, root.path) else { return false }
            if config.excludes(path, fullText: false) { return false }
            if path == output.path || ["知识图谱.html", "知识图谱.command", "知识图谱.html.tmp"].contains(URL(fileURLWithPath: path).lastPathComponent) { return false }
            let relative = path == root.path ? "" : String(path.dropFirst(root.path.count + 1))
            for part in relative.split(separator: "/").map(String.init) {
                if config.skipDirectories.contains(part) || config.restrictedNames.contains(where: { $0.lowercased() == part.lowercased() }) || config.restrictedPrefixes.contains(where: { part.hasPrefix($0) }) || config.restrictedSubstrings.contains(where: { !$0.isEmpty && part.contains($0) }) || config.skipDirectorySuffixes.contains(where: { part.hasSuffix($0) }) || (config.skipHidden && part.hasPrefix(".")) { return false }
            }
            return true
        }
        func path(_ value: Any?, from source: String) -> String? {
            guard let value = value as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let expanded = (value.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
            if expanded.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) != nil { return nil }
            return URL(fileURLWithPath: expanded, relativeTo: URL(fileURLWithPath: source).deletingLastPathComponent()).lexicalPath
        }
        func tags(_ value: Any?) -> [String] {
            let raw = (value as? [String]) ?? (value as? String).map { [$0] } ?? []
            var found: [String] = []
            for value in raw {
                let value = value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty, !found.contains(value) { found.append(value) }
            }
            return found
        }
        func matches(_ pattern: String, _ text: String, group: Int = 1) -> [String] {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
            return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { result in
                guard result.numberOfRanges > group, let range = Range(result.range(at: group), in: text) else { return nil }; return String(text[range])
            }
        }
        func scan() throws {
            guard allowed(root.path) else { throw Failure(message: "所选目录已被本机图谱配置排除") }
            var stack = [root]
            while let directory = stack.popLast() {
                try checkCancellation()
                let info = try safeInfo(directory)
                guard info.st_mode & S_IFMT == S_IFDIR else { throw Failure(message: "扫描中的目录已变化；未覆盖图谱") }
                entries[directory.path] = Entry(url: directory, directory: true, size: 0, modified: Int64(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_mtimespec.tv_nsec))
                let children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
                for child in children where allowed(child.path) {
                    try checkCancellation()
                    var info = stat()
                    guard lstat(child.path, &info) == 0 else { throw Failure(message: "目录读取未完成；未覆盖既有图谱") }
                    let type = info.st_mode & S_IFMT
                    if type == S_IFDIR { stack.append(child); continue }
                    guard type == S_IFREG else { continue }
                    var entry = Entry(url: child, directory: false, size: info.st_size, modified: Int64(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_mtimespec.tv_nsec))
                    if ["md", "markdown"].contains(child.pathExtension.lowercased()) || ["catalog.yaml", "project.yaml"].contains(child.lastPathComponent) {
                        if info.st_size > 1_048_576 { warnings.append(["source_path": child.path, "reason": "content_larger_than_1MiB"]) }
                        else {
                            entry.text = try safeText(child)
                            do {
                                if ["catalog.yaml", "project.yaml"].contains(child.lastPathComponent) { entry.catalog = try FolioGraphYAML.parse(entry.text) }
                                else {
                                    var content = entry.text.replacingOccurrences(of: "\r\n", with: "\n")
                                    if content.hasPrefix("---\n") {
                                        let sections = content.components(separatedBy: "\n")
                                        if let end = sections.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }) {
                                            entry.metadata = try FolioGraphYAML.parse(sections[1..<end].joined(separator: "\n"))
                                            content = sections.dropFirst(end + 1).joined(separator: "\n")
                                        } else { throw Failure(message: "frontmatter 未闭合") }
                                    }
                                    let clean = content.replacingOccurrences(of: "(?s)```.*?```|~~~.*?~~~", with: "", options: .regularExpression)
                                    entry.links = matches("\\[[^\\[\\]\\n]*\\]\\(([^()\\[\\]\\n]*)\\)", clean) + matches("\\[\\[([^\\[\\]\\n]+)\\]\\]", clean)
                                }
                            } catch { warnings.append(["source_path": child.path, "reason": "metadata_parse_error", "detail": error.localizedDescription]) }
                        }
                    }
                    entries[child.path] = entry
                }
            }
            // Directory registration is the merge of legacy catalog and current
            // project metadata; the newer registration wins one key at a time.
            for path in entries.keys.sorted() where entries[path]!.directory {
                for name in ["catalog.yaml", "project.yaml"] {
                    let source = URL(fileURLWithPath: path).appendingPathComponent(name).path
                    for (key, value) in entries[source]?.catalog ?? [:] { entries[path]!.metadata[key] = value }
                }
            }
            // Package metadata only annotates actual descendants, never invents
            // paths; nested registrations override their ancestor annotation.
            for source in entries.keys.sorted(by: { $0.count < $1.count }) {
                guard let packages = entries[source]?.catalog["packages"] as? [String: [String: Any]] else { continue }
                for (relative, values) in packages {
                    guard let target = path(relative, from: source), under(target, URL(fileURLWithPath: source).deletingLastPathComponent().path), entries[target] != nil else { continue }
                    entries[target]!.metadata = values.merging(entries[target]!.metadata) { _, own in own }
                }
            }
            for path in entries.keys { entries[path]!.tags = tags(entries[path]!.metadata["tags"]) }
        }
        func payload() throws -> [String: Any] {
            try scan()
            var nodes: [String: [String: Any]] = [:]; var atlas: [String: [String: Any]] = [:]
            var aliases: [String: String] = [:]; var edges: [[String: Any]] = []; var semantic: [[String: Any]] = []
            var seenEdges = Set<String>(); var tagMembers: [String: [String]] = [:]
            func source(_ path: String, note: String = "") -> [String: Any] { ["title": URL(fileURLWithPath: path).lastPathComponent, "path": path, "note": note, "status": "present"] }
            func edge(_ a: String, _ b: String, label: String, kind: String, basis: String, sources: [[String: Any]], both: Bool = false) {
                guard a != b else { return }
                let signature = [a, b, label, kind].joined(separator: "\u{1f}")
                guard seenEdges.insert(signature).inserted else { return }
                edges.append(["id": "e:" + digest(signature), "a": a, "b": b, "label": label, "kind": kind, "basis": basis, "src": sources, "both": both])
            }
            func sources(_ raw: Any?, catalog: String) -> [[String: Any]] {
                guard let list = raw as? [Any] else { return [] }
                return list.compactMap { item in
                    let item = (item as? [String: Any]) ?? ["path": item]
                    guard let target = path(item["path"], from: catalog) else { return nil }
                    guard allowed(target), (try? safeInfo(URL(fileURLWithPath: target))) != nil else { return ["title": "范围外或不可用来源", "path": NSNull(), "note": "", "status": "excluded"] }
                    return ["title": item["title"] as? String ?? URL(fileURLWithPath: target).lastPathComponent, "path": target, "note": item["note"] as? String ?? "", "status": entries[target] == nil ? "missing" : "present"]
                }
            }
            for path in entries.keys.sorted() {
                let item = entries[path]!, id = identifier(path)
                let parent: Any = path == root.path ? NSNull() : identifier(item.url.deletingLastPathComponent().path)
                let kind = item.directory ? "directory" : "file"
                let name = item.metadata["display_name"] as? String ?? item.metadata["name"] as? String ?? item.url.lastPathComponent
                let description = item.metadata["description"] as? String ?? ""
                nodes[id] = ["id": id, "name": name, "path": path, "parent": parent, "children": [String](), "kind": kind, "type": item.directory ? "目录" : "文件", "domain": "local", "color": "#187b68", "tags": item.tags, "function": description, "size": item.size, "mtime_ns": item.modified]
                atlas[id] = ["id": id, "name": name, "path": path, "parent": parent, "children": [String](), "kind": item.directory ? "目录" : "文档", "group": "local", "sub": item.directory ? "目录" : "文件", "icon": item.directory ? "layers" : "source", "tags": item.tags, "desc": description, "src": [source(path)]]
            }
            for (id, item) in nodes {
                if let parent = item["parent"] as? String, var children = nodes[parent]?["children"] as? [String] {
                    children.append(id); children.sort(); nodes[parent]!["children"] = children; atlas[parent]!["children"] = children
                }
            }
            let catalogs = entries.keys.sorted().compactMap { path -> (String, [String: Any])? in
                guard let graph = entries[path]?.catalog["knowledge_graph"] as? [String: Any] else { return nil }; return (path, graph)
            }
            for (catalog, graph) in catalogs {
                for declared in graph["nodes"] as? [[String: Any]] ?? [] {
                    guard let alias = declared["id"] as? String, alias.range(of: "^[\\w.-]+:[\\w:.-]+$", options: .regularExpression) != nil, aliases[alias] == nil else { warnings.append(["source_path": catalog, "reason": "atlas_node_requires_unique_namespaced_id"]); continue }
                    let target = path(declared["path"], from: catalog)
                    if declared["path"] != nil && (target == nil || entries[target!] == nil || !allowed(target!)) { warnings.append(["source_path": catalog, "reason": "atlas_node_path_missing_or_excluded"]); continue }
                    let id = target.map(identifier) ?? alias
                    aliases[alias] = id
                    var value = atlas[id] ?? ["id": id, "group": "local", "parent": NSNull(), "children": [String](), "src": [[String: Any]]()]
                    value["name"] = declared["name"] as? String ?? value["name"] as? String ?? alias
                    value["sub"] = declared["subtitle"] as? String ?? value["sub"] as? String ?? ""
                    value["kind"] = declared["kind"] as? String ?? value["kind"] as? String ?? "topic"
                    value["icon"] = declared["icon"] as? String ?? value["icon"] as? String ?? "layers"
                    value["desc"] = declared["description"] as? String ?? value["desc"] as? String ?? ""
                    value["tags"] = Array(Set((value["tags"] as? [String] ?? []) + tags(declared["tags"]))).sorted()
                    value["src"] = (value["src"] as? [[String: Any]] ?? []) + sources(declared["sources"], catalog: catalog)
                    value["catalog"] = catalog
                    atlas[id] = value
                }
            }
            func resolve(_ value: Any?, catalog: String) -> String? {
                guard let raw = value as? String else { return nil }
                if let id = aliases[raw] { return id }; if atlas[raw] != nil { return raw }
                if let target = path(raw, from: catalog), entries[target] != nil { return identifier(target) }
                return nil
            }
            for (catalog, graph) in catalogs {
                for declared in graph["edges"] as? [[String: Any]] ?? [] {
                    guard let a = resolve(declared["source"], catalog: catalog), let b = resolve(declared["target"], catalog: catalog) else { warnings.append(["source_path": catalog, "reason": "atlas_edge_unknown_endpoint"]); continue }
                    edge(a, b, label: declared["label"] as? String ?? "关联", kind: "relation", basis: declared["basis"] as? String ?? "catalog", sources: sources(declared["sources"], catalog: catalog), both: declared["both"] as? Bool ?? false)
                }
            }
            let byStem = Dictionary(grouping: entries.keys.filter { ["md", "markdown"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }, by: { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent })
            for path in entries.keys.sorted() {
                try checkCancellation()
                let item = entries[path]!, a = identifier(path)
                var relations: [(String, String, String)] = []
                for raw in item.links {
                    let cleaned = raw.components(separatedBy: "|")[0].components(separatedBy: "#")[0].trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
                    guard !cleaned.isEmpty, let candidate = self.path(cleaned.removingPercentEncoding ?? cleaned, from: path) else { continue }
                    var target = candidate
                    if entries[target] == nil, URL(fileURLWithPath: target).pathExtension.isEmpty, entries[target + ".md"] != nil { target += ".md" }
                    if entries[target] == nil, !cleaned.contains("/"), let matches = byStem[URL(fileURLWithPath: cleaned).deletingPathExtension().lastPathComponent], matches.count == 1 { target = matches[0] }
                    if entries[target] != nil { relations.append((target, "reference", "引用")) }
                }
                for declared in item.metadata["relations"] as? [[String: Any]] ?? [] {
                    let referenceSource = item.directory ? item.url.appendingPathComponent("metadata.yaml").path : path
                    guard let kind = declared["type"] as? String, let target = self.path(declared["target"], from: referenceSource), entries[target] != nil, allowed(target) else { unresolved.append(["source": a, "reason": "target_missing_or_excluded"]); continue }
                    relations.append((target, kind, declared["label"] as? String ?? kind))
                }
                for (target, kind, label) in relations {
                    let b = identifier(target); guard a != b else { continue }
                    semantic.append(["source": a, "target": b, "kind": kind, "label": label, "source_path": path, "evidence": kind == "reference" ? "reference" : "explicit_metadata"])
                    edge(a, b, label: label, kind: "semantic", basis: kind, sources: [source(path)])
                }
            }
            for (catalog, graph) in catalogs {
                for declared in graph["nodes"] as? [[String: Any]] ?? [] where declared["table_rows"] as? Bool == true {
                    guard let alias = declared["id"] as? String, let parent = aliases[alias], let path = path(declared["path"], from: catalog), let item = entries[path], ["md", "markdown"].contains(item.url.pathExtension.lowercased()) else { continue }
                    var headers: [String]? = nil
                    for (number, line) in item.text.components(separatedBy: "\n").enumerated() {
                        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard line.hasPrefix("|") else { headers = nil; continue }
                        let sentinel = "\u{1f}"
                        let cells = line.trimmingCharacters(in: CharacterSet(charactersIn: "|")).replacingOccurrences(of: "\\|", with: sentinel).components(separatedBy: "|").map { $0.replacingOccurrences(of: sentinel, with: "|").trimmingCharacters(in: .whitespaces) }
                        guard cells.count >= 2 else { continue }
                        if cells.allSatisfy({ $0.range(of: "^:?-{2,}:?$", options: .regularExpression) != nil }) { continue }
                        guard let columns = headers else { headers = cells; continue }
                        guard columns.count == cells.count else { continue }
                        let titleColumn = ["#", "序号"].contains(columns[0]) ? 1 : 0
                        let title = cells[titleColumn].components(separatedBy: "<br")[0].replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]+\\)", with: "$1", options: .regularExpression).replacingOccurrences(of: "<[^>]+>|[`*_]", with: "", options: .regularExpression)
                        let key = "table:" + digest(path + ":" + String(number + 1))
                        let evidence = [source(path, note: "第 \(number + 1) 行；导航表原始记录，未核验当前状态")]
                        atlas[key] = ["id": key, "name": String(title.prefix(36)), "sub": "原表记录 · 状态未核验", "kind": "导航表记录", "group": "local", "icon": "source", "tags": [String](), "desc": zip(columns, cells).map { $0 + "：" + $1 }.joined(separator: "\n"), "src": evidence, "parent": parent, "children": [String](), "source_line": number + 1, "confidence": "来源记录，未经独立核验"]
                        edge(parent, key, label: "原表条目", kind: "relation", basis: "原导航表记录（非核验结论）", sources: evidence)
                        for (heading, cell) in zip(columns, cells) {
                            for reference in matches("`([^`\\n]+)`", cell) + matches("\\[[^\\]]*\\]\\(([^)]+)\\)", cell) {
                                let clean = reference.components(separatedBy: "#")[0].removingPercentEncoding ?? reference
                                if let target = self.path(clean, from: path), entries[target] != nil { edge(key, identifier(target), label: heading, kind: "relation", basis: "原表路径引用（非提交或有效性判断）", sources: evidence) }
                            }
                        }
                    }
                }
            }
            for (id, node) in atlas { for name in node["tags"] as? [String] ?? [] { tagMembers[name, default: []].append(id) } }
            var tagList: [[String: Any]] = []
            for name in tagMembers.keys.sorted() {
                let id = "tag:" + digest(name), members = tagMembers[name]!.sorted()
                tagList.append(["id": id, "name": name, "members": members])
                atlas[id] = ["id": id, "name": name, "sub": "主题标签", "kind": "tag", "group": "tags", "icon": "layers", "tags": [String](), "desc": "", "src": [[String: Any]](), "members": members]
                for member in members { edge(member, id, label: "标签", kind: "tag", basis: "explicit_metadata", sources: atlas[member]?["src"] as? [[String: Any]] ?? []) }
            }
            let connectedPairs = Set(edges.filter { $0["kind"] as? String != "tag" }.map { [$0["a"] as! String, $0["b"] as! String].sorted().joined(separator: "\u{1f}") })
            for (id, node) in nodes {
                if let parent = node["parent"] as? String, !connectedPairs.contains([parent, id].sorted().joined(separator: "\u{1f}")) {
                    edge(parent, id, label: node["kind"] as? String == "directory" ? "目录包含" : "包含文件", kind: "entry", basis: "真实目录结构（非知识关系）", sources: [source(nodes[parent]!["path"] as! String)])
                }
            }
            var overview: [String] = []
            // The merged root registration owns the selected folder overview.
            if let graph = entries[root.path]?.metadata["knowledge_graph"] as? [String: Any] {
                let sourcePath = root.appendingPathComponent("project.yaml").path
                for reference in graph["overview"] as? [Any] ?? [] {
                    if let id = resolve(reference, catalog: sourcePath), id != "home", !overview.contains(id) { overview.append(id) }
                }
            }
            if overview.isEmpty { overview = (nodes["home"]?["children"] as? [String] ?? []).sorted { (nodes[$0]?["name"] as? String ?? "") < (nodes[$1]?["name"] as? String ?? "") } }
            for id in overview where !edges.contains(where: { ($0["a"] as? String == "home" && $0["b"] as? String == id) || ($0["b"] as? String == "home" && $0["a"] as? String == id) }) {
                edge("home", id, label: "事项入口", kind: "entry", basis: "原目录导航声明", sources: [source(root.path)])
            }
            let generated = ISO8601DateFormatter().string(from: Date())
            let revision = digest(entries.keys.sorted().map { $0 + ":" + String(entries[$0]!.modified) }.joined(separator: "\n"))
            return ["static_mode": true, "scope_root": root.path, "generated_at": generated, "home_overview": overview, "nodes": nodes, "domains": [String](), "rows": nodes.keys.filter { $0 != "home" }.sorted(), "aliases": [String](), "maintenance_modules": [Any](), "tags": tagList, "semantic_edges": semantic,
                    "atlas": ["nodes": atlas.keys.sorted().map { atlas[$0]! }, "edges": edges, "modules": [Any](), "aliases": aliases, "diagnostics": warnings],
                    "metadata_warnings": warnings, "unresolved_semantic_relations": unresolved, "snapshot": generated,
                    "status": ["state": "snapshot", "revision": revision, "counts": ["directory": entries.values.filter(\.directory).count, "file": entries.values.filter { !$0.directory }.count], "scanned_at": generated],
                    "coverage": ["indexed_entries": entries.count, "rendered_nodes": nodes.count, "content_policy": "本目录 Markdown 与目录元数据；其他文件仅元数据", "excluded_components": config.skipDirectories + config.restrictedNames],
                    "scope_notes": ["不跟随软链；仅解析不超过 1 MiB 的 Markdown 和目录元数据", "\(warnings.count) 条元数据提示"], "refresh_command": "folio graph \"$PWD\" --launcher"]
        }
    }
}

// MARK: - Document outline
// The sidebar outline and `folio outline` share this. It lives in this engine file because the app,
// the command line and the tests all compile it, while the mobile target does not show an outline.

/// One heading: `offset` is the UTF-16 position of its `#` (the unit the editor uses to jump there).
struct MarkdownHeading { let offset: Int, line: Int, level: Int, title: String }
enum MarkdownOutline {
    static let heading = try! NSRegularExpression(pattern: "(?m)^(#{1,6})[ \\t]+(.+)$")
    /// ATX headings outside fenced code; a fence closes only on the same marker at least as long.
    static func headings(in text: String) -> [MarkdownHeading] {
        let ns = text as NSString
        var items: [MarkdownHeading] = [], location = 0, number = 0
        var fence: (marker: Character, count: Int)?
        while location < ns.length {
            let line = ns.lineRange(for: NSRange(location: location, length: 0)), raw = ns.substring(with: line)
            number += 1
            defer { location = NSMaxRange(line) }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let marker = trimmed.first
            let count = marker.map { character in trimmed.prefix(while: { $0 == character }).count } ?? 0
            if let open = fence {
                if marker == open.marker && count >= open.count && trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                continue
            }
            if let marker, (marker == "`" || marker == "~"), count >= 3 {
                if marker != "`" || !trimmed.dropFirst(count).contains("`") { fence = (marker, count); continue }
            }
            if let match = heading.firstMatch(in: raw, range: NSRange(location: 0, length: (raw as NSString).length)) {
                items.append(MarkdownHeading(offset: location + match.range.location, line: number, level: match.range(at: 1).length,
                                             title: (raw as NSString).substring(with: match.range(at: 2))))
            }
        }
        return items
    }
}
