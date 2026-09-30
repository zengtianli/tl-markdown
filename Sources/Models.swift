import Foundation
import SQLite3
import UniformTypeIdentifiers

struct RecentFile: Codable, Identifiable {
    var path: String
    var opened: Date = Date()
    var pinned = false
    var scroll: Double = 0
    var selection = 0
    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}
struct EditorSettings: Codable {
    var fontFamily: String? = "system"
    var fontSize: Double = 17
    var contentWidth: Double = 820
    var restoreSession = true
    var imageFolder = "assets"
    /// Optional full-text index for “全部笔记”; nil uses NoteIndex.defaultPath.
    var noteIndexPath: String?
}
struct OpenDocument: Codable, Identifiable {
    var id = UUID().uuidString
    var path: String?
    var text = ""
    var savedText = ""
    var diskData: Data?
    var lineEnding = "\n"
    var bom = false
    var scroll: Double = 0
    var selection = 0
    var revision = 0
    var conflict = false
    var message = ""
    var title: String { path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "未命名" }
    var dirty: Bool { text != savedText || (path == nil && !text.isEmpty) }
}
struct SessionSnapshot: Codable {
    var documents: [OpenDocument] = []
    var activeID: String?
    var recent: [RecentFile] = []
    var settings = EditorSettings()
    var closedDrafts: [OpenDocument]? = []
}
enum DocumentError: LocalizedError {
    case conflict, missing, encoding, readOnly, imageFolder, imageTooLarge, imageType, state(String)
    var errorDescription: String? {
        switch self {
        case .conflict: return "文件已被其他软件修改。你的修改已保留，请选择重新载入或另存为。"
        case .missing: return "原文件已移动或删除。你的修改已保留，请另存为。"
        case .encoding: return "文件不是 UTF-8 文本，暂不支持直接编辑；原文件未改动。"
        case .readOnly: return "文件为只读或不可写。你的修改已保留，请另存为。"
        case .imageFolder: return "图片目录必须是文档旁的相对目录，不能包含 .. 或绝对路径。"
        case .imageTooLarge: return "图片过大（上限 40 MB）"
        case .imageType: return "不是可插入的图片文件"
        case .state(let detail): return "恢复记录无法读取：\(detail)；原记录已保留。"
        }
    }
}

/// App and tests use this exact implementation; no alternate test-only save path.
struct DocumentIO {
    static func open(_ url: URL) throws -> OpenDocument {
        let real = url.standardizedFileURL.resolvingSymlinksInPath()
        let data = try Data(contentsOf: real)
        guard var text = String(data: data, encoding: .utf8), !text.contains("\0") else { throw DocumentError.encoding }
        let bom = data.starts(with: [0xEF, 0xBB, 0xBF])
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let ending = text.contains("\r\n") ? "\r\n" : (text.contains("\r") ? "\r" : "\n")
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return OpenDocument(path: real.path, text: text, savedText: text, diskData: data, lineEnding: ending, bom: bom)
    }
    static func encoded(_ document: OpenDocument) -> Data {
        Data(((document.bom ? "\u{FEFF}" : "") + document.text.replacingOccurrences(of: "\n", with: document.lineEnding)).utf8)
    }
    static func save(_ document: inout OpenDocument, to destination: URL? = nil) throws {
        guard let url = destination ?? document.path.map({ URL(fileURLWithPath: $0) }) else { throw DocumentError.missing }
        let real = url.standardizedFileURL.resolvingSymlinksInPath()
        let fm = FileManager.default
        let same = real.path == document.path
        if same {
            guard fm.fileExists(atPath: real.path) else { throw DocumentError.missing }
            guard try Data(contentsOf: real) == document.diskData else { throw DocumentError.conflict }
            if document.text == document.savedText { return }
        }
        if fm.fileExists(atPath: real.path) {
            let attributes = try fm.attributesOfItem(atPath: real.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
            guard fm.isWritableFile(atPath: real.path), permissions & 0o222 != 0 else { throw DocumentError.readOnly }
        }
        let data = encoded(document)
        let baseline = document.diskData
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: real, options: [], error: &coordinationError) { target in
            do {
                if same, try Data(contentsOf: target) != baseline { throw DocumentError.conflict }
                try data.write(to: target, options: .atomic)
            } catch { writeError = error }
        }
        if let error = coordinationError { throw error }
        if let error = writeError { throw error }
        document.path = real.path; document.diskData = data; document.savedText = document.text
        document.conflict = false; document.message = ""
    }
    static func imageDestination(document: OpenDocument, folder: String, extension ext: String) throws -> URL {
        guard let path = document.path else { throw DocumentError.missing }
        guard !folder.isEmpty, !folder.hasPrefix("/"), !folder.split(separator: "/").contains("..") else { throw DocumentError.imageFolder }
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("image-\(UUID().uuidString.prefix(12)).\(ext)")
    }
    /// Paste, drag, the Insert Image menu and `folio asset add` share this size limit.
    static let imageByteLimit = 40_000_000
    /// A dropped or chosen file is insertable when its extension names an image type.
    static func isImageFile(_ url: URL) -> Bool { UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false }
    /// Copies image bytes beside the document under `folder` with a unique name and returns the
    /// Markdown reference the editor inserts. The document itself is not modified.
    static func storeImage(_ data: Data, extension ext: String, document: OpenDocument, folder: String) throws -> (url: URL, markdown: String) {
        guard data.count < imageByteLimit else { throw DocumentError.imageTooLarge }
        let url = try imageDestination(document: document, folder: folder, extension: ext)
        try data.write(to: url, options: .atomic)
        return (url, "![图片](<\(folder)/\(url.lastPathComponent)>)")
    }
}
final class SessionDisk {
    let directory: URL
    let file: URL
    init(directory: URL) { self.directory = directory; file = directory.appendingPathComponent("session.json") }
    func read() throws -> SessionSnapshot {
        guard FileManager.default.fileExists(atPath: file.path) else { return SessionSnapshot() }
        do { return try JSONDecoder().decode(SessionSnapshot.self, from: Data(contentsOf: file)) }
        catch { throw DocumentError.state(error.localizedDescription) }
    }
    func write(_ snapshot: SessionSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

/// User-facing name comes from project.yaml through the built Info.plist.
enum ProductIdentity {
    static var name: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ProcessInfo.processInfo.processName }
}


// MARK: - Note search
// The sidebar's read-only view of Folio's SQLite FTS5 index (doc + doc_fts, trigram tokenizer).
// Folio's IndexEngine maintains that index (Settings 更新索引 and `folio index`); search itself is
// FolioIndexEngine.find, the same implementation `folio search/files` prints. This connection only
// adds a serial queue and interruption for typing, and never writes.

struct NoteLineHit: Identifiable, Hashable {
    let path: String
    let line: Int        // 1-based line in the indexed body
    let text: String
    var id: String { "\(path)#\(line)" }
}
struct NoteFileHit: Identifiable, Hashable {
    let path: String, workspace: String, title: String, modified: String
    var lines: [NoteLineHit]
    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}
struct NoteSearchResult {
    enum Mode: String { case fts = "全文索引", like = "逐字匹配", idle = "" }
    var query = ""
    var files: [NoteFileHit] = []
    var mode: Mode = .idle
    var elapsed: TimeInterval = 0
    var truncated = false
    var error: String?
}

/// All sqlite calls stay on `queue`; `interrupt()` is the one call SQLite allows from another thread.
final class NoteIndex: @unchecked Sendable {
    /// Without a custom path in Settings: MDINDEX_DB, else the default beside index.json.
    static var defaultPath: URL { FolioIndexConfig.resolveDatabase(setting: nil).url }
    let path: URL
    let queue = DispatchQueue(label: "cyou.tianli.folio.note-index", qos: .userInitiated)
    private var db: OpaquePointer?
    private(set) var openError: String?
    init(path: URL) { self.path = path }
    deinit { if let db { sqlite3_close_v2(db) } }

    /// Opens read-only and reports the real reason on failure; never shows substitute data.
    @discardableResult func open() -> Bool {
        if db != nil { return true }
        guard FileManager.default.fileExists(atPath: path.path) else {
            openError = "没有找到笔记索引：\((path.path as NSString).abbreviatingWithTildeInPath)"; return false
        }
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2("file:\(path.path)?mode=ro", &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        guard rc == SQLITE_OK, let handle else {
            openError = "无法读取笔记索引（\(rc)）"; sqlite3_close_v2(handle); return false
        }
        db = handle
        var found = Set<String>()
        rows("SELECT name FROM sqlite_master WHERE name IN ('doc','doc_fts')") { found.insert(Self.text($0, 0)) }
        guard found == ["doc", "doc_fts"] else {
            openError = "笔记索引结构不认识"; sqlite3_close_v2(handle); db = nil; return false
        }
        openError = nil; return true
    }
    func interrupt() { if let db { sqlite3_interrupt(db) } }
    var documentCount: Int { var n = 0; rows("SELECT COUNT(*) FROM doc") { n = Int(sqlite3_column_int64($0, 0)) }; return n }

    private func rows(_ sql: String, _ params: [String] = [], _ row: (OpaquePointer) -> Void) {
        guard let db else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        for (i, value) in params.enumerated() { sqlite3_bind_text(statement, Int32(i + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        while sqlite3_step(statement) == SQLITE_ROW { row(statement) }
    }
    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }
    func search(_ raw: String, limit: Int = 60, perFile: Int = 6) -> NoteSearchResult {
        var result = NoteSearchResult()
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        result.query = query
        guard open() else { result.error = openError; return result }
        guard !query.isEmpty, let db else { return result }
        var request = FolioIndexQuery(); request.query = query; request.limit = limit; request.perFile = perFile
        do {
            let found = try FolioIndexEngine.find(handle: db, query: request)
            result.mode = found.mode == .fts ? .fts : .like
            result.files = found.files.map { hit in
                NoteFileHit(path: hit.path, workspace: hit.workspace, title: hit.title, modified: hit.mtime, lines: hit.lines.map {
                    // Opening a hit jumps to exactly this line; the sidebar shows at most 240 characters of it.
                    NoteLineHit(path: hit.path, line: $0.line, text: $0.text.count > 240 ? String($0.text.prefix(240)) + " …" : $0.text)
                })
            }
            result.truncated = found.truncated; result.elapsed = found.elapsed
        } catch { result.error = error.localizedDescription }
        return result
    }
}

/// UTF-16 offset of the start of a 1-based line — the unit both editors use for positions.
func noteLineOffset(_ text: String, line: Int) -> Int {
    let ns = text as NSString
    var location = 0, current = 1
    while current < line && location < ns.length {
        location = NSMaxRange(ns.lineRange(for: NSRange(location: location, length: 0))); current += 1
    }
    return min(location, ns.length)
}
