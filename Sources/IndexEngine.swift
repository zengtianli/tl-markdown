import Foundation
import SQLite3
import Darwin
import MachO

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
    /// Graph-only: a component containing any of these texts is withheld.
    var restrictedSubstrings: [String] = []

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
        case restrictedSubstrings = "restricted_substrings"
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
        restrictedSubstrings = try c.decodeIfPresent([String].self, forKey: .restrictedSubstrings) ?? restrictedSubstrings
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
    /// Exclusion patterns are matched against every walked entry; expanding
    /// them once per HOME keeps the walk dominated by filesystem calls.
    private static let expandedCache = NSCache<NSString, NSString>()
    static func expanded(_ path: String) -> String {
        // Only "~" patterns depend on HOME; reading the environment builds a
        // dictionary, so it stays off the path for absolute patterns.
        let tilde = path == "~" || path.hasPrefix("~/"), home = tilde ? home : ""
        let key = (home + "\u{0}" + path) as NSString
        if let hit = expandedCache.object(forKey: key) { return hit as String }
        let p = !tilde ? path : path == "~" ? home : home + String(path.dropFirst())
        let value = URL(fileURLWithPath: p).lexicalPath
        expandedCache.setObject(value as NSString, forKey: key)
        return value
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

    // MARK: Index database location
    /// Every reader and writer (Settings, sidebar search, `folio`) resolves the database the same
    /// way: an explicit path, then MDINDEX_DB, then the custom index path saved in Folio Settings,
    /// then md_index.db beside index.json. `setting` is only evaluated when it is needed.
    static func resolveDatabase(explicit: String? = nil, setting: @autoclosure () -> String?) -> (url: URL, source: String) {
        if let explicit, !explicit.isEmpty { return (URL(fileURLWithPath: expanded(explicit)), "option") }
        if let env = ProcessInfo.processInfo.environment["MDINDEX_DB"], !env.isEmpty { return (URL(fileURLWithPath: expanded(env)), "environment") }
        if let saved = setting()?.trimmingCharacters(in: .whitespaces), !saved.isEmpty { return (URL(fileURLWithPath: expanded(saved)), "settings") }
        return (FolioIndexEngine.defaultDatabaseURL, "default")
    }
    /// The custom index path the running app saved in session.json (settings.noteIndexPath). The
    /// session file is large (base64 tab snapshots), so a byte scan skips the parse when the key is
    /// absent; a quoted key cannot occur inside escaped JSON string content. Read-only.
    static func savedIndexSetting(in directory: URL = stateDirectory) -> String? {
        let file = directory.appendingPathComponent("session.json")
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe), data.range(of: Data("\"noteIndexPath\"".utf8)) != nil,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = object["settings"] as? [String: Any], let path = settings["noteIndexPath"] as? String else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: Index folders (Settings 添加/移除文件夹 and `folio roots`)
    /// A root as Settings stores it: tilde-expanded and standardized, like an NSOpenPanel URL.
    static func normalizedRoot(_ path: String) -> String {
        let tilde = path == "~" || path.hasPrefix("~/")
        let raw = tilde ? (path == "~" ? home : home + String(path.dropFirst())) : path
        return URL(fileURLWithPath: raw).standardizedFileURL.path
    }
    /// Re-reads the file before every change so a stale copy never overwrites another writer's
    /// edit. A missing file starts from defaults; an unreadable one is never replaced.
    static func loadForEditing(from url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        do { return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url)) }
        catch { throw FolioIndexError.message("无法读取索引配置 \(url.path)：\(error.localizedDescription)；未做任何修改。") }
    }
    static func addRoots(_ paths: [String], at url: URL) throws -> FolioRootsChange {
        var config = try loadForEditing(from: url), change = FolioRootsChange(configPath: url.path)
        for raw in paths {
            let path = normalizedRoot(raw)
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else {
                throw FolioIndexError.message("不是存在的文件夹：\(path)；未做任何修改。")
            }
            if config.roots.contains(where: { $0 == path || expanded($0) == path }) || change.added.contains(path) { change.unchanged.append(path) }
            else { config.roots.append(path); change.added.append(path) }
        }
        if !change.added.isEmpty { try config.save(to: url) }
        change.roots = config.roots
        return change
    }
    static func removeRoots(_ paths: [String], at url: URL) throws -> FolioRootsChange {
        var config = try loadForEditing(from: url), change = FolioRootsChange(configPath: url.path)
        for raw in paths {
            // Settings removes the stored text itself; typed paths also match their expanded form.
            let path = normalizedRoot(raw)
            let matches = config.roots.filter { $0 == raw || $0 == path || expanded($0) == path }
            if matches.isEmpty { change.notFound.append(raw) }
            else { config.roots.removeAll { matches.contains($0) }; change.removed.append(contentsOf: matches) }
        }
        if !change.removed.isEmpty { try config.save(to: url) }
        change.roots = config.roots
        return change
    }
}

struct FolioRootsChange: Codable {
    var configPath: String
    var roots: [String] = []
    var added: [String] = []
    var removed: [String] = []
    var unchanged: [String] = []
    var notFound: [String] = []
    var changed: Bool { !added.isEmpty || !removed.isEmpty }
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
struct FolioIndexSummary: Codable { var count: Int; var updatedAt: Date? }
struct FolioIndexQuery {
    var query = ""
    var workspace: String?
    var repository: String?
    var path: String?
    var since: String?
    var titleOnly = false
    /// Maximum files; 0 = no limit.
    var limit = 20
    /// Matching lines reported per file; 0 skips reading bodies for line hits.
    var perFile = 3
    var width = 120
    var includeBody = false
}
/// fts: trigram full-text index; like: literal scan for queries under three characters;
/// filter: no query text, only workspace/repository/path/date filters.
enum FolioSearchMode: String, Codable { case fts, like, filter }
struct FolioLineHit: Codable, Hashable {
    var line: Int        // 1-based line in the indexed body
    var text: String     // the line with surrounding spaces trimmed
}
struct FolioSearchHit: Codable {
    var id: Int; var path: String; var workspace: String; var repository: String; var title: String; var mtime: String
    var lines: [FolioLineHit]
    var body: String?
}
struct FolioSearchResult: Codable {
    var query: String
    var mode: FolioSearchMode
    var elapsed: Double
    var truncated: Bool
    var files: [FolioSearchHit]
}

private struct FolioSQLiteError: Error, LocalizedError {
    let code: Int32; let detail: String
    var errorDescription: String? { "索引库不可读 (\(detail))" }
}
private final class FolioSQLite {
    var handle: OpaquePointer?
    private let owned: Bool
    init(_ url: URL, readonly: Bool = false) throws {
        owned = true
        let flags = readonly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let result = sqlite3_open_v2(url.path, &handle, flags | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else {
            let error = failure(result); sqlite3_close(handle); handle = nil; throw error
        }
        sqlite3_busy_timeout(handle, 3000)
    }
    /// A connection someone else opened and closes (the sidebar's interruptible reader).
    init(borrowing handle: OpaquePointer) { self.handle = handle; owned = false }
    deinit { if owned { close() } }
    func close() { if owned, let handle { sqlite3_close_v2(handle); self.handle = nil } }
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
            // Children are only visited after lstat proved them real directories,
            // so only the configured root needs its ancestors checked.
            guard !config.excludes(path, fullText: true), let info = lstatPath(path), isType(info, S_IFDIR), path != root || noSymlinkComponents(path, root: root) else { return }
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
    /// `thorough` scans every page (seconds on a large index), so only full
    /// rebuilds pay for it; incremental runs read the schema, which already
    /// rejects a non-database file, and retry as full on page corruption.
    private static func databaseForWrite(_ url: URL, thorough: Bool) throws -> (FolioSQLite, String?) {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            let db = try FolioSQLite(url)
            try db.rows(thorough ? "PRAGMA quick_check" : "SELECT 'ok' FROM sqlite_master LIMIT 1") { s in
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
        do { return try update(config: config, database: database, full: full, cancelled: cancelled) }
        catch let error as FolioSQLiteError where !full && (error.code & 0xff == SQLITE_CORRUPT || error.code & 0xff == SQLITE_NOTADB) {
            // The failed transaction rolled back; a full pass archives and rebuilds.
            return try update(config: config, database: database, full: true, cancelled: cancelled)
        }
    }
    private static func update(config: FolioIndexConfig, database: URL, full: Bool, cancelled: () -> Bool) throws -> FolioIndexStats {
        let start = Date()
        guard !config.roots.isEmpty else { throw FolioIndexError.message("尚未配置索引文件夹；请先在 Folio 设置中选择文件夹。") }
        try check(cancelled)
        let (found, symlinks, broken, validRoots) = try walk(config: config, cancelled: cancelled)
        guard validRoots > 0 else { throw FolioIndexError.message("\(config.roots.count) 个 workspace 下 0 篇 md —— 扫描根不存在或全被 SKIP_DIRS 吃掉") }
        // An empty valid folder is a real result: deleting its last document must
        // remove that document from an existing index, rather than retain stale data.
        guard !found.isEmpty || FileManager.default.fileExists(atPath: database.path) else { throw FolioIndexError.message("扫描目录下 0 篇 md；尚未建立索引。") }
        try check(cancelled)
        let (db, recovered) = try databaseForWrite(database, thorough: full)
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
        // External-content FTS5 is kept in step row by row: the old terms are
        // removed with the stored values before the row changes, then re-added.
        let ftsRemove = try db.prepare("INSERT INTO doc_fts(doc_fts,rowid,title,body) SELECT 'delete',id,title,body FROM doc WHERE path=?")
        let ftsAdd = try db.prepare("INSERT INTO doc_fts(rowid,title,body) SELECT id,title,body FROM doc WHERE path=?")
        defer { for s in [insert, signature, delete, deleteSignature, ftsRemove, ftsAdd] { sqlite3_finalize(s) } }
        // A database without Folio signatures (first takeover, or --full) has an
        // FTS view this run did not maintain; rebuild it once instead.
        let rebuildFTS = full || prior.isEmpty
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
            let values = [file.path, file.workspace, file.repo, rel, scalarPrefix(title, 120), body, String(body.unicodeScalars.count), formatter.string(from: Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)))]
            if !rebuildFTS && oldPaths.contains(file.path) { try db.run(ftsRemove, [file.path]) }
            try db.run(insert, values)
            if !rebuildFTS { try db.run(ftsAdd, [file.path]) }
            try db.run(signature, [file.path, "\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec)", String(info.st_size)])
            validPaths.insert(file.path); changed += 1
        }
        let removed = oldPaths.subtracting(validPaths)
        for path in removed {
            try check(cancelled)
            if !rebuildFTS { try db.run(ftsRemove, [path]) }
            try db.run(delete, [path]); try db.run(deleteSignature, [path])
        }
        try check(cancelled)
        // The content table and FTS view change together in the same transaction.
        if rebuildFTS { try db.exec("INSERT INTO doc_fts(doc_fts) VALUES('rebuild')") }
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
    /// What Settings shows (count and last update) without the full-table aggregates of `stats`:
    /// about 1 ms instead of ~100 ms on a large index, so it is cheap on the main thread.
    static func summary(database: URL) throws -> FolioIndexSummary {
        let db = try openReader(database)
        var result = FolioIndexSummary(count: 0, updatedAt: updatedAt(db))
        try db.rows("SELECT COUNT(*) FROM doc") { result.count = Int(sqlite3_column_int64($0, 0)) }
        return result
    }
    private static func updatedAt(_ db: FolioSQLite) -> Date? {
        var value: Date?
        try? db.rows("SELECT value FROM folio_meta WHERE key='updated_at'") { s in value = Double(FolioSQLite.text(s, 0)).map { Date(timeIntervalSince1970: $0) } }
        return value
    }
    private static func readStats(_ db: FolioSQLite) throws -> FolioIndexStats {
        var result = FolioIndexStats(count: 0, updatedAt: updatedAt(db))
        try db.rows("SELECT COUNT(*),COALESCE(SUM(nchar),0),COUNT(DISTINCT repo) FROM doc") { s in
            result.count = Int(sqlite3_column_int64(s, 0)); result.characters = Int(sqlite3_column_int64(s, 1)); result.repositories = Int(sqlite3_column_int64(s, 2))
        }
        func group(_ sql: String) throws -> [FolioIndexGroup] {
            var values: [FolioIndexGroup] = []
            try db.rows(sql) { s in values.append(FolioIndexGroup(name: FolioSQLite.text(s, 0), count: Int(sqlite3_column_int64(s, 1)), characters: Int(sqlite3_column_int64(s, 2)))) }; return values
        }
        result.workspaces = try group("SELECT ws,COUNT(*),SUM(nchar) FROM doc GROUP BY 1 ORDER BY 2 DESC")
        result.topRepositories = try group("SELECT repo,COUNT(*),0 FROM doc GROUP BY 1 ORDER BY 2 DESC LIMIT 15")
        result.months = try group("SELECT substr(mtime,1,7),COUNT(*),0 FROM doc GROUP BY 1 ORDER BY 1 DESC LIMIT 12")
        return result
    }
    // MARK: Search (sidebar ⌘⇧F and `folio search/files` share this one implementation)
    /// The trigram tokenizer silently matches nothing for queries under three characters, and
    /// two-character words are the most common Chinese queries; shorter queries scan literally.
    static let trigramMinimum = 3
    /// `%`, `_` and `\` in a query are literal text, not wildcards.
    static func escapeLike(_ value: String) -> String {
        var out = ""; for character in value { if "\\%_".contains(character) { out.append("\\") }; out.append(character) }; return out
    }
    /// Real 1-based line numbers (the unit the editor jumps to), matched case-insensitively
    /// like the trigram index itself.
    static func lineHits(body: String, needle: String, cap: Int) -> [FolioLineHit] {
        guard cap > 0, !needle.isEmpty else { return [] }
        var out: [FolioLineHit] = [], number = 0
        body.enumerateLines { line, stop in
            number += 1
            if line.range(of: needle, options: .caseInsensitive) != nil {
                out.append(FolioLineHit(line: number, text: line.trimmingCharacters(in: .whitespaces)))
                if out.count >= cap { stop = true }
            }
        }
        return out
    }
    static func find(database: URL, query: FolioIndexQuery) throws -> FolioSearchResult { try find(openReader(database), query) }
    /// For a caller that owns the connection, e.g. to interrupt a superseded query from another thread.
    static func find(handle: OpaquePointer, query: FolioIndexQuery) throws -> FolioSearchResult { try find(FolioSQLite(borrowing: handle), query) }
    private static func find(_ db: FolioSQLite, _ query: FolioIndexQuery) throws -> FolioSearchResult {
        let started = Date()
        let text = query.query.trimmingCharacters(in: .whitespacesAndNewlines)
        var conditions: [String] = [], params: [String] = []
        if let value = query.workspace { conditions.append("doc.ws = ?"); params.append(value) }
        if let value = query.repository { conditions.append("doc.repo LIKE ? ESCAPE '\\'"); params.append("%" + escapeLike(value) + "%") }
        if let value = query.path { conditions.append("doc.path LIKE ? ESCAPE '\\'"); params.append("%" + escapeLike(value) + "%") }
        if let value = query.since { conditions.append("doc.mtime >= ?"); params.append(value) }
        var source = "doc", mode = FolioSearchMode.filter
        if text.count >= trigramMinimum {
            mode = .fts; source = "doc_fts JOIN doc ON doc.id = doc_fts.rowid"
            conditions.append("doc_fts MATCH ?")
            params.append((query.titleOnly ? "title" : "{title body}") + " : \"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"")
        } else if !text.isEmpty {
            mode = .like
            let pattern = "%" + escapeLike(text) + "%"
            if query.titleOnly { conditions.append("doc.title LIKE ? ESCAPE '\\'"); params.append(pattern) }
            else { conditions.append("(doc.body LIKE ? ESCAPE '\\' OR doc.title LIKE ? ESCAPE '\\')"); params += [pattern, pattern] }
        }
        let wantsLines = mode != .filter && !query.titleOnly && query.perFile > 0
        let body = wantsLines || query.includeBody ? "doc.body" : "''"
        let sql = "SELECT doc.id,doc.path,doc.ws,doc.repo,doc.title,doc.mtime," + body + " FROM " + source + (conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")) + " ORDER BY doc.mtime DESC LIMIT ?"
        // 0 (or less) means no limit; SQLite reads a negative LIMIT as unbounded.
        let limit = max(0, query.limit)
        params.append(String(limit > 0 ? limit : -1))
        var files: [FolioSearchHit] = []
        try db.rows(sql, params) { s in
            let content = FolioSQLite.text(s, 6)
            files.append(FolioSearchHit(id: Int(sqlite3_column_int64(s, 0)), path: FolioSQLite.text(s, 1), workspace: FolioSQLite.text(s, 2), repository: FolioSQLite.text(s, 3),
                                        title: FolioSQLite.text(s, 4), mtime: FolioSQLite.text(s, 5),
                                        lines: wantsLines ? lineHits(body: content, needle: text, cap: query.perFile) : [],
                                        body: query.includeBody ? content : nil))
        }
        return FolioSearchResult(query: text, mode: mode, elapsed: Date().timeIntervalSince(started), truncated: limit > 0 && files.count >= limit, files: files)
    }
    static func scalarPrefix(_ string: String, _ count: Int) -> String {
        String(String.UnicodeScalarView(string.unicodeScalars.prefix(max(0, count))))
    }
}
