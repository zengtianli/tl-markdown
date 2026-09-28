import Foundation
import SQLite3
import Darwin

@main enum IndexEngineTests {
    static func main() throws {
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("folio-index-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let root = temporary.appendingPathComponent("Notes"), repo = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let a = repo.appendingPathComponent("a.md"), b = repo.appendingPathComponent("b.md")
        func write(_ url: URL, _ body: String) throws { try body.write(to: url, atomically: true, encoding: .utf8) }
        try write(a, "# 水库调度\n生态流量 Kelly\n第三行\n")
        try write(b, "# Another\nreservoir\n")
        try Data([65, 0, 66]).write(to: repo.appendingPathComponent("binary.md"))
        try FileManager.default.createSymbolicLink(at: repo.appendingPathComponent("alias.md"), withDestinationURL: a)
        mkfifo(repo.appendingPathComponent("pipe.md").path, 0o600)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("build"), withIntermediateDirectories: true)
        try write(repo.appendingPathComponent("build/ignored.md"), "# ignored")
        try write(repo.appendingPathComponent(".hidden.md"), "# hidden")
        let excluded = repo.appendingPathComponent("private"), nestedMemory = repo.appendingPathComponent("nested/memory")
        try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nestedMemory, withIntermediateDirectories: true)
        try write(excluded.appendingPathComponent("excluded.md"), "# excluded")
        try write(nestedMemory.appendingPathComponent("excluded.md"), "# excluded")
        var config = FolioIndexConfig(); config.roots = [root.path]
        config.fullTextExcludedPaths = [excluded.path]; config.skipPaths = [repo.path + "/**/memory"]
        let database = temporary.appendingPathComponent("state/index.db"), configURL = temporary.appendingPathComponent("state/config.json")
        try config.save(to: configURL)
        var failures = 0
        func check(_ condition: Bool, _ name: String) { print((condition ? "PASS " : "FAIL ") + name); if !condition { failures += 1 } }
        check(try FolioIndexConfig.load(from: configURL).roots == config.roots, "configuration round-trips")
        let raw = try String(contentsOf: configURL, encoding: .utf8)
        check(raw.contains("skip_directories") && !raw.contains("skipDirectories"), "configuration keys use snake_case")
        let first = try FolioIndexEngine.rebuild(config: config, database: database)
        check(first.count == 2 && first.changed == 2 && first.skippedBinary == 1 && first.unreadable == 1, "regular Markdown only; NUL/FIFO/hidden/build/private scope excluded")
        check(first.symlinks == 1 && first.repositories == 1 && first.updatedAt != nil, "symlinks excluded and nearest repository retained")
        check(FileManager.default.fileExists(atPath: database.path + "-wal") && FileManager.default.fileExists(atPath: database.path + "-shm"), "WAL coordination retained for read-only clients")
        var q = FolioIndexQuery(); q.query = "生态流量"
        check(try FolioIndexEngine.search(database: database, query: q).map(\.path) == [a.path], "FTS finds long words")
        q.query = "水库"
        check(try FolioIndexEngine.search(database: database, query: q).count == 1, "two-character query falls back to LIKE")
        q.workspace = "Notes"; q.repository = "project"; q.path = "a.md"; q.since = "2020-01-01"; q.titleOnly = true
        check(try FolioIndexEngine.search(database: database, query: q).count == 1, "workspace/repo/path/since/title filters combine")
        q.since = "2999-01-01"
        check(try FolioIndexEngine.search(database: database, query: q).isEmpty, "since filter excludes older documents")
        let unchanged = try FolioIndexEngine.rebuild(config: config, database: database)
        check(unchanged.changed == 0 && unchanged.unchanged == 2, "unchanged mtime and size skip document reads")
        try write(a, "# Changed\nupdated body\n")
        try FileManager.default.removeItem(at: b)
        let c = repo.appendingPathComponent("c.md"); try write(c, "# New\nnew body\n")
        let incremental = try FolioIndexEngine.rebuild(config: config, database: database)
        check(incremental.count == 2 && incremental.changed == 2 && incremental.removed == 1, "incremental modifies, inserts, and removes in one refresh")
        q = FolioIndexQuery(); q.query = "生态流量"
        check(try FolioIndexEngine.search(database: database, query: q).isEmpty, "removed text disappears from FTS")
        q.query = "updated"
        check(try FolioIndexEngine.search(database: database, query: q).map(\.path) == [a.path], "updated text enters FTS")
        var totalPolls = 0
        _ = try FolioIndexEngine.rebuild(config: config, database: database, full: true, cancelled: { totalPolls += 1; return false })
        let beforeCancellation = try FolioIndexEngine.stats(database: database).updatedAt
        try write(a, "# Should roll back\nreplacement\n")
        var polls = 0, cancelled = false
        // Same tiny file tree means the final poll occurs after all document and
        // FTS writes, immediately before commit: this tests a real rollback.
        do { _ = try FolioIndexEngine.rebuild(config: config, database: database, full: true, cancelled: { polls += 1; return polls == totalPolls }) }
        catch FolioIndexError.cancelled { cancelled = true }
        check(cancelled, "cancellation propagates as a distinct failure")
        check(try FolioIndexEngine.search(database: database, query: q).map(\.path) == [a.path], "cancelled refresh preserves previous searchable contents")
        check(try FolioIndexEngine.stats(database: database).updatedAt == beforeCancellation, "cancelled transaction preserves update metadata")
        let rebuilt = try FolioIndexEngine.rebuild(config: config, database: database, full: true)
        check(rebuilt.changed == 2 && rebuilt.unchanged == 0, "full forces all documents to be read")
        let bad = temporary.appendingPathComponent("bad.db")
        try write(bad, "This is not SQLite")
        let recovered = try FolioIndexEngine.rebuild(config: config, database: bad)
        check(recovered.count == 2 && recovered.recoveredDatabase != nil && FileManager.default.fileExists(atPath: bad.path + ".corrupt"), "bad database is archived and rebuilt")
        let missing = temporary.appendingPathComponent("missing/config.json")
        var missingFailed = false
        do { _ = try FolioIndexConfig.load(from: missing) } catch { missingFailed = error.localizedDescription.contains("尚未配置") }
        check(missingFailed && !FileManager.default.fileExists(atPath: missing.path), "missing config fails without creating configuration or scanning")
        var emptyFailed = false
        do { _ = try FolioIndexEngine.rebuild(config: FolioIndexConfig(), database: temporary.appendingPathComponent("never.db")) } catch { emptyFailed = true }
        check(emptyFailed && !FileManager.default.fileExists(atPath: temporary.appendingPathComponent("never.db").path), "empty roots do not create a database")
        check(try FolioIndexEngine.stats(database: database).count == 2, "stats reads real database")
        try FileManager.default.removeItem(at: a); try FileManager.default.removeItem(at: c)
        let emptied = try FolioIndexEngine.rebuild(config: config, database: database)
        check(emptied.count == 0 && emptied.removed == 2, "deleting all documents commits an empty index")
        print(failures == 0 ? "Index engine checks passed" : "\(failures) checks failed")
        exit(failures == 0 ? 0 : 1)
    }
}
