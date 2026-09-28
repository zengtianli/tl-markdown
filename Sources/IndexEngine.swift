import Foundation
import SQLite3
import Darwin

/// Lexical "." / ".." cleanup that keeps a leading /private. Foundation's
/// standardizedFileURL rewrites /private/var to the /var symlink, so paths
/// would no longer match scanned children or survive O_NOFOLLOW walks.
extension URL {
    var lexicalPath: String {
        var parts: [String] = []
        for part in absoluteURL.path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { _ = parts.popLast(); continue }
            parts.append(String(part))
        }
        return "/" + parts.joined(separator: "/")
    }
}

/// The running binary's real location. argv[0] is only "folio" when the
/// command is started through PATH, so it cannot locate the enclosing .app.
enum FolioExecutable {
    static var url: URL {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size) + 1)
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath() }
        return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath()
    }
}

/// The on-disk configuration is local user state, never part of the app bundle.
struct FolioIndexConfig: Codable, Sendable {
    var roots: [String] = []
    var skipDirectories: [String] = [".git", "node_modules", ".venv", "venv", "__pycache__", "build", "dist", "DerivedData", ".build", "target"]
    var skipPaths: [String] = []
    var fullTextExcludedPaths: [String] = []
    var skipDirectorySuffixes: [String] = []
    var skipHidden: Bool = true
    var restrictedNames: [String] = []
    var restrictedPrefixes: [String] = []

    init() {}

    static var home: String { ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory() }
    static var stateDirectory: URL {
        if let state = ProcessInfo.processInfo.environment["TL_MARKDOWN_STATE_DIR"], !state.isEmpty {
            return URL(fileURLWithPath: state, isDirectory: true)
        }
        return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Library/Application Support/TLMarkdown", isDirectory: true)
    }
    static var defaultURL: URL { stateDirectory.appendingPathComponent("index.json") }

    enum CodingKeys: String, CodingKey {
        case roots, skipDirectories = "skip_directories", skipPaths = "skip_paths"
        case fullTextExcludedPaths = "full_text_excluded_paths", skipDirectorySuffixes = "skip_directory_suffixes"
        case skipHidden = "skip_hidden", restrictedNames = "restricted_names", restrictedPrefixes = "restricted_prefixes"
    }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roots = try c.decodeIfPresent([String].self, forKey: .roots) ?? roots
        skipDirectories = try c.decodeIfPresent([String].self, forKey: .skipDirectories) ?? skipDirectories
        skipPaths = try c.decodeIfPresent([String].self, forKey: .skipPaths) ?? skipPaths
        fullTextExcludedPaths = try c.decodeIfPresent([String].self, forKey: .fullTextExcludedPaths) ?? fullTextExcludedPaths
        skipDirectorySuffixes = try c.decodeIfPresent([String].self, forKey: .skipDirectorySuffixes) ?? skipDirectorySuffixes
        skipHidden = try c.decodeIfPresent(Bool.self, forKey: .skipHidden) ?? skipHidden
        restrictedNames = try c.decodeIfPresent([String].self, forKey: .restrictedNames) ?? restrictedNames
        restrictedPrefixes = try c.decodeIfPresent([String].self, forKey: .restrictedPrefixes) ?? restrictedPrefixes
    }
    static func load(from url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FolioIndexError.message("尚未配置索引文件夹：\(url.path)；请先在 Folio 设置中选择文件夹，或使用 --config 指定配置。")
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
    func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func expanded(_ path: String) -> String {
        let p = path == "~" ? home : path.hasPrefix("~/") ? home + String(path.dropFirst()) : path
        return URL(fileURLWithPath: p).lexicalPath
    }
    static func inside(_ path: String, _ root: String) -> Bool { path == root || path.hasPrefix(root == "/" ? root : root + "/") }
    /// A trailing /**/name denotes a component anywhere below that prefix.
    func excludes(_ path: String, fullText: Bool) -> Bool {
        for pattern in skipPaths + (fullText ? fullTextExcludedPaths : []) {
            if let range = pattern.range(of: "/**/") {
                let base = Self.expanded(String(pattern[..<range.lowerBound]))
                let component = String(pattern[range.upperBound...])
                if Self.inside(path, base), path.dropFirst(base.count).split(separator: "/").contains(Substring(component)) { return true }
            } else if Self.inside(path, Self.expanded(pattern)) { return true }
        }
        return false
    }
    func excludesComponent(_ name: String) -> Bool {
        skipDirectories.contains(name) || (skipHidden && name.hasPrefix(".")) || skipDirectorySuffixes.contains(where: name.hasSuffix)
    }
}

enum FolioIndexError: Error, LocalizedError {
    case message(String), cancelled
    var errorDescription: String? {
        switch self { case .message(let value): return value; case .cancelled: return "索引更新已取消，原索引保持不变。" }
    }
}

struct FolioIndexGroup: Codable { var name: String; var count: Int; var characters: Int }
struct FolioIndexStats: Codable {
    var count: Int
    var updatedAt: Date?
    var characters: Int = 0
    var repositories: Int = 0
    var workspaces: [FolioIndexGroup] = []
    var topRepositories: [FolioIndexGroup] = []
    var months: [FolioIndexGroup] = []
    var changed: Int = 0
    var unchanged: Int = 0
    var removed: Int = 0
    var skippedBinary: Int = 0
    var unreadable: Int = 0
    var symlinks: Int = 0
    var brokenLinks: Int = 0
    var elapsed: Double = 0
    var recoveredDatabase: String?
}
struct FolioIndexQuery {
    var query = ""
    var workspace: String?
    var repository: String?
    var path: String?
    var since: String?
    var titleOnly = false
    var limit = 20
    var perFile = 3
    var width = 120
}
struct FolioIndexDocument: Codable {
    var id: Int; var path: String; var repository: String; var title: String; var mtime: String; var body: String
}

private struct FolioSQLiteError: Error, LocalizedError {
    let code: Int32; let detail: String
    var errorDescription: String? { "索引库不可读 (\(detail))" }
}
private final class FolioSQLite {
    var handle: OpaquePointer?
    init(_ url: URL, readonly: Bool = false) throws {
        let flags = readonly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let result = sqlite3_open_v2(url.path, &handle, flags | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else {
            let error = failure(result); sqlite3_close(handle); handle = nil; throw error
        }
        sqlite3_busy_timeout(handle, 3000)
    }
    deinit { close() }
    func close() { if let handle { sqlite3_close_v2(handle); self.handle = nil } }
    func failure(_ code: Int32) -> FolioSQLiteError {
        FolioSQLiteError(code: code, detail: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite error \(code)")
    }
    func exec(_ sql: String) throws {
        let result = sqlite3_exec(handle, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw failure(result) }
    }
    func prepare(_ sql: String) throws -> OpaquePointer {
        var s: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &s, nil)
        guard result == SQLITE_OK, let s else { throw failure(result) }
        return s
    }
    func rows(_ sql: String, _ params: [String] = [], _ receive: (OpaquePointer) throws -> Void) throws {
        let s = try prepare(sql); defer { sqlite3_finalize(s) }
        for (offset, value) in params.enumerated() { bind(s, Int32(offset + 1), value) }
        while true {
            let result = sqlite3_step(s)
            if result == SQLITE_DONE { return }
            guard result == SQLITE_ROW else { throw failure(result) }
            try receive(s)
        }
    }
    func bind(_ s: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(s, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    func run(_ s: OpaquePointer, _ values: [String]) throws {
        sqlite3_reset(s); sqlite3_clear_bindings(s)
        for (offset, value) in values.enumerated() { bind(s, Int32(offset + 1), value) }
        let result = sqlite3_step(s)
        guard result == SQLITE_DONE else { throw failure(result) }
    }
    static func text(_ s: OpaquePointer, _ index: Int32) -> String {
        guard let bytes = sqlite3_column_text(s, index) else { return "" }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(s, index))), as: UTF8.self)
    }
}

enum FolioIndexEngine {
    static var defaultDatabaseURL: URL { FolioIndexConfig.stateDirectory.appendingPathComponent("md_index.db") }
    private struct Candidate { let path: String; let workspace: String; let repo: String; let root: String }
    private struct Signature { let mtime: String; let size: Int64 }

    private static func check(_ cancelled: () -> Bool) throws { if cancelled() { throw FolioIndexError.cancelled } }
    private static func lstatPath(_ path: String) -> stat? { var value = stat(); return lstat(path, &value) == 0 ? value : nil }
    private static func isType(_ info: stat, _ type: mode_t) -> Bool { info.st_mode & S_IFMT == type }
    private static func noSymlinkComponents(_ path: String, root: String) -> Bool {
        guard let rootInfo = lstatPath(root), !isType(rootInfo, S_IFLNK) else { return false }
        var current = root
        for component in path.dropFirst(root.count).split(separator: "/") {
            current = (current as NSString).appendingPathComponent(String(component))
            if let info = lstatPath(current), isType(info, S_IFLNK) { return false }
        }
        return true
    }
    private static func walk(config: FolioIndexConfig, cancelled: () -> Bool) throws -> ([Candidate], Int, Int, Int) {
        var found: [Candidate] = [], seen = Set<String>(), symlinks = 0, broken = 0, validRoots = 0
        let fm = FileManager.default
        func visit(_ path: String, _ workspace: String, _ inheritedRepo: String, _ root: String) throws {
            try check(cancelled)
            guard !config.excludes(path, fullText: true), let info = lstatPath(path), isType(info, S_IFDIR), noSymlinkComponents(path, root: root) else { return }
            let entries = try fm.contentsOfDirectory(atPath: path)
            let repo = entries.contains(".git") ? path : inheritedRepo
            for name in entries {
                try check(cancelled)
                let next = (path as NSString).appendingPathComponent(name)
                guard !config.excludes(next, fullText: true), !config.excludesComponent(name), let info = lstatPath(next) else { continue }
                if isType(info, S_IFLNK) {
                    if name.hasSuffix(".md") { if fm.fileExists(atPath: next) { symlinks += 1 } else { broken += 1 } }
                    continue
                }
                if isType(info, S_IFDIR) { try visit(next, workspace, repo, root) }
                else if name.hasSuffix(".md"), seen.insert(next).inserted { found.append(Candidate(path: next, workspace: workspace, repo: repo, root: root)) }
            }
        }
        for root in config.roots {
            let path = FolioIndexConfig.expanded(root)
            if let info = lstatPath(path), isType(info, S_IFDIR), !config.excludes(path, fullText: true) { validRoots += 1 }
            try visit(path, (path as NSString).lastPathComponent, path, path)
        }
        return (found, symlinks, broken, validRoots)
    }
    private static func schema(_ db: FolioSQLite) throws {
        try db.exec("""
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS doc(id INTEGER PRIMARY KEY,path TEXT NOT NULL UNIQUE,ws TEXT NOT NULL,repo TEXT NOT NULL,rel TEXT NOT NULL,title TEXT,body TEXT NOT NULL,nchar INTEGER NOT NULL,mtime TEXT NOT NULL);
            CREATE VIRTUAL TABLE IF NOT EXISTS doc_fts USING fts5(title,body,content='doc',content_rowid='id',tokenize='trigram');
            CREATE INDEX IF NOT EXISTS idx_ws ON doc(ws);
            CREATE INDEX IF NOT EXISTS idx_repo ON doc(repo);
            CREATE INDEX IF NOT EXISTS idx_mtime ON doc(mtime);
            CREATE TABLE IF NOT EXISTS folio_file(path TEXT PRIMARY KEY,mtime_ns TEXT NOT NULL,size INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS folio_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);
            """)
        // Retain coordination files when the last writer closes, including for strict read-only GUI readers.
        var persist: Int32 = 1
        sqlite3_file_control(db.handle, "main", SQLITE_FCNTL_PERSIST_WAL, &persist)
    }
    private static func databaseForWrite(_ url: URL) throws -> (FolioSQLite, String?) {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            let db = try FolioSQLite(url)
            try db.rows("PRAGMA quick_check") { s in
                if FolioSQLite.text(s, 0) != "ok" { throw FolioSQLiteError(code: SQLITE_CORRUPT, detail: FolioSQLite.text(s, 0)) }
            }
            try schema(db)
            return (db, nil)
        } catch let error as FolioSQLiteError where error.code & 0xff == SQLITE_CORRUPT || error.code & 0xff == SQLITE_NOTADB {
            var archive = url.path + ".corrupt"
            if FileManager.default.fileExists(atPath: archive) { archive += "." + UUID().uuidString }
            for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: url.path + suffix) {
                try FileManager.default.moveItem(atPath: url.path + suffix, toPath: archive + suffix)
            }
            let db = try FolioSQLite(url); try schema(db)
            return (db, archive)
        }
    }
    static func rebuild(config: FolioIndexConfig, database: URL, full: Bool = false, cancelled: () -> Bool = { false }) throws -> FolioIndexStats {
        let start = Date()
        guard !config.roots.isEmpty else { throw FolioIndexError.message("尚未配置索引文件夹；请先在 Folio 设置中选择文件夹。") }
        try check(cancelled)
        let (found, symlinks, broken, validRoots) = try walk(config: config, cancelled: cancelled)
        guard validRoots > 0 else { throw FolioIndexError.message("\(config.roots.count) 个 workspace 下 0 篇 md —— 扫描根不存在或全被 SKIP_DIRS 吃掉") }
        // An empty valid folder is a real result: deleting its last document must
        // remove that document from an existing index, rather than retain stale data.
        guard !found.isEmpty || FileManager.default.fileExists(atPath: database.path) else { throw FolioIndexError.message("扫描目录下 0 篇 md；尚未建立索引。") }
        try check(cancelled)
        let (db, recovered) = try databaseForWrite(database)
        defer { db.close() }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: database.path)
        var prior: [String: Signature] = [:], oldPaths = Set<String>()
        try db.rows("SELECT path,mtime_ns,size FROM folio_file") { prior[FolioSQLite.text($0, 0)] = Signature(mtime: FolioSQLite.text($0, 1), size: sqlite3_column_int64($0, 2)) }
        try db.rows("SELECT path FROM doc") { oldPaths.insert(FolioSQLite.text($0, 0)) }
        var validPaths = Set<String>(), changed = 0, unchanged = 0, skipped = 0, binary = 0
        let insert = try db.prepare("INSERT INTO doc(path,ws,repo,rel,title,body,nchar,mtime) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(path) DO UPDATE SET ws=excluded.ws,repo=excluded.repo,rel=excluded.rel,title=excluded.title,body=excluded.body,nchar=excluded.nchar,mtime=excluded.mtime")
        let signature = try db.prepare("INSERT OR REPLACE INTO folio_file(path,mtime_ns,size) VALUES(?,?,?)")
        let delete = try db.prepare("DELETE FROM doc WHERE path=?")
        let deleteSignature = try db.prepare("DELETE FROM folio_file WHERE path=?")
        defer { for s in [insert, signature, delete, deleteSignature] { sqlite3_finalize(s) } }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let titleRegex = try NSRegularExpression(pattern: "^#\\s+(.+)$", options: [.anchorsMatchLines])
        try db.exec("BEGIN IMMEDIATE")
        var committed = false
        defer { if !committed { try? db.exec("ROLLBACK") } }
        for file in found {
            try check(cancelled)
            guard noSymlinkComponents(file.path, root: file.root), !config.excludes(file.path, fullText: true) else { skipped += 1; continue }
            let fd = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard fd >= 0 else { skipped += 1; continue }
            let result: (stat, Data?)? = {
                defer { close(fd) }
                var info = stat()
                guard fstat(fd, &info) == 0, isType(info, S_IFREG) else { return nil }
                let stamp = "\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec)"
                if !full, let old = prior[file.path], old.mtime == stamp, old.size == info.st_size, oldPaths.contains(file.path) { return (info, nil) }
                var data = Data(), buffer = [UInt8](repeating: 0, count: 65_536)
                while true {
                    if cancelled() { return nil }
                    let count = read(fd, &buffer, buffer.count)
                    if count == 0 { return (info, data) }
                    if count < 0 { if errno == EINTR { continue }; return nil }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }()
            try check(cancelled)
            guard let (info, data) = result else { skipped += 1; continue }
            guard let data else { validPaths.insert(file.path); unchanged += 1; continue }
            if data.contains(0) { binary += 1; continue }
            let body = String(decoding: data, as: UTF8.self)
            let nsBody = body as NSString
            let match = titleRegex.firstMatch(in: body, range: NSRange(location: 0, length: nsBody.length))
            let title = match.map { nsBody.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines) } ?? URL(fileURLWithPath: file.path).deletingPathExtension().lastPathComponent
            let rel = String(file.path.dropFirst(file.repo.count + 1))
            try db.run(insert, [file.path, file.workspace, file.repo, rel, scalarPrefix(title, 120), body, String(body.unicodeScalars.count), formatter.string(from: Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)))])
            try db.run(signature, [file.path, "\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec)", String(info.st_size)])
            validPaths.insert(file.path); changed += 1
        }
        let removed = oldPaths.subtracting(validPaths)
        for path in removed { try check(cancelled); try db.run(delete, [path]); try db.run(deleteSignature, [path]) }
        try check(cancelled)
        // The content table and FTS view change together in the same transaction.
        if changed > 0 || !removed.isEmpty || full { try db.exec("INSERT INTO doc_fts(doc_fts) VALUES('rebuild')") }
        try check(cancelled)
        let meta = try db.prepare("INSERT OR REPLACE INTO folio_meta(key,value) VALUES('updated_at',?)")
        defer { sqlite3_finalize(meta) }
        try db.run(meta, [String(Date().timeIntervalSince1970)])
        try db.exec("COMMIT"); committed = true
        try db.exec("PRAGMA busy_timeout=0; PRAGMA wal_checkpoint(TRUNCATE)")
        var result = try readStats(db)
        result.changed = changed; result.unchanged = unchanged; result.removed = removed.count
        result.skippedBinary = binary; result.unreadable = skipped; result.symlinks = symlinks; result.brokenLinks = broken
        result.elapsed = Date().timeIntervalSince(start); result.recoveredDatabase = recovered
        return result
    }
    private static func openReader(_ database: URL) throws -> FolioSQLite {
        guard FileManager.default.fileExists(atPath: database.path) else { throw FolioIndexError.message("索引不存在: \(database.path)\n  先跑: folio index") }
        return try FolioSQLite(database, readonly: true)
    }
    static func stats(database: URL) throws -> FolioIndexStats { try readStats(openReader(database)) }
    private static func readStats(_ db: FolioSQLite) throws -> FolioIndexStats {
        var result = FolioIndexStats(count: 0, updatedAt: nil)
        try db.rows("SELECT COUNT(*),COALESCE(SUM(nchar),0),COUNT(DISTINCT repo) FROM doc") { s in
            result.count = Int(sqlite3_column_int64(s, 0)); result.characters = Int(sqlite3_column_int64(s, 1)); result.repositories = Int(sqlite3_column_int64(s, 2))
        }
        try? db.rows("SELECT value FROM folio_meta WHERE key='updated_at'") { s in result.updatedAt = Double(FolioSQLite.text(s, 0)).map { Date(timeIntervalSince1970: $0) } }
        func group(_ sql: String) throws -> [FolioIndexGroup] {
            var values: [FolioIndexGroup] = []
            try db.rows(sql) { s in values.append(FolioIndexGroup(name: FolioSQLite.text(s, 0), count: Int(sqlite3_column_int64(s, 1)), characters: Int(sqlite3_column_int64(s, 2)))) }; return values
        }
        result.workspaces = try group("SELECT ws,COUNT(*),SUM(nchar) FROM doc GROUP BY 1 ORDER BY 2 DESC")
        result.topRepositories = try group("SELECT repo,COUNT(*),0 FROM doc GROUP BY 1 ORDER BY 2 DESC LIMIT 15")
        result.months = try group("SELECT substr(mtime,1,7),COUNT(*),0 FROM doc GROUP BY 1 ORDER BY 1 DESC LIMIT 12")
        return result
    }
    static func search(database: URL, query: FolioIndexQuery) throws -> [FolioIndexDocument] {
        let db = try openReader(database)
        var conditions: [String] = [], params: [String] = []
        if let value = query.workspace { conditions.append("doc.ws = ?"); params.append(value) }
        if let value = query.repository { conditions.append("doc.repo LIKE ?"); params.append("%" + value + "%") }
        if let value = query.path { conditions.append("doc.path LIKE ?"); params.append("%" + value + "%") }
        if let value = query.since { conditions.append("doc.mtime >= ?"); params.append(value) }
        var source = "doc"
        if !query.query.isEmpty, query.query.unicodeScalars.count >= 3 {
            source = "doc_fts JOIN doc ON doc.id = doc_fts.rowid"
            conditions.append("doc_fts MATCH ?")
            params.append((query.titleOnly ? "title" : "{title body}") + " : \"" + query.query.replacingOccurrences(of: "\"", with: "\"\"") + "\"")
        } else if !query.query.isEmpty {
            conditions.append(query.titleOnly ? "doc.title LIKE ?" : "doc.body LIKE ?")
            // Preserve the original CLI's LIKE semantics, including wildcard queries.
            params.append("%" + query.query + "%")
        }
        let sql = "SELECT doc.id,doc.path,doc.repo,doc.title,doc.mtime,doc.body FROM " + source + (conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")) + " ORDER BY doc.mtime DESC LIMIT ?"
        params.append(String(query.limit))
        var result: [FolioIndexDocument] = []
        try db.rows(sql, params) { s in result.append(FolioIndexDocument(id: Int(sqlite3_column_int64(s, 0)), path: FolioSQLite.text(s, 1), repository: FolioSQLite.text(s, 2), title: FolioSQLite.text(s, 3), mtime: FolioSQLite.text(s, 4), body: FolioSQLite.text(s, 5))) }
        return result
    }
    static func scalarPrefix(_ string: String, _ count: Int) -> String {
        String(String.UnicodeScalarView(string.unicodeScalars.prefix(max(0, count))))
    }
}
