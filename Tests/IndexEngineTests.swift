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
        check(try FolioIndexEngine.find(database: database, query: q).files.map(\.path) == [a.path], "FTS finds long words")
        q.query = "水库"
        check(try FolioIndexEngine.find(database: database, query: q).files.count == 1, "two-character query falls back to LIKE")
        q.workspace = "Notes"; q.repository = "project"; q.path = "a.md"; q.since = "2020-01-01"; q.titleOnly = true
        check(try FolioIndexEngine.find(database: database, query: q).files.count == 1, "workspace/repo/path/since/title filters combine")
        q.since = "2999-01-01"
        check(try FolioIndexEngine.find(database: database, query: q).files.isEmpty, "since filter excludes older documents")
        let unchanged = try FolioIndexEngine.rebuild(config: config, database: database)
        check(unchanged.changed == 0 && unchanged.unchanged == 2, "unchanged mtime and size skip document reads")
        try write(a, "# Changed\nupdated body\n")
        try FileManager.default.removeItem(at: b)
        let c = repo.appendingPathComponent("c.md"); try write(c, "# New\nnew body\n")
        let incremental = try FolioIndexEngine.rebuild(config: config, database: database)
        check(incremental.count == 2 && incremental.changed == 2 && incremental.removed == 1, "incremental modifies, inserts, and removes in one refresh")
        q = FolioIndexQuery(); q.query = "生态流量"
        check(try FolioIndexEngine.find(database: database, query: q).files.isEmpty, "removed text disappears from FTS")
        q.query = "updated"
        check(try FolioIndexEngine.find(database: database, query: q).files.map(\.path) == [a.path], "updated text enters FTS")
        func ftsConsistent() -> Bool {
            var handle: OpaquePointer?
            defer { sqlite3_close(handle) }
            // rank=1 compares the FTS index against the external content table.
            return sqlite3_open(database.path, &handle) == SQLITE_OK
                && sqlite3_exec(handle, "INSERT INTO doc_fts(doc_fts, rank) VALUES('integrity-check', 1)", nil, nil, nil) == SQLITE_OK
        }
        check(ftsConsistent(), "row-level incremental FTS maintenance matches content table")
        try write(c, "# New\nnew body again\n")
        _ = try FolioIndexEngine.rebuild(config: config, database: database)
        check(ftsConsistent(), "second incremental update keeps FTS consistent")
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
        check(try FolioIndexEngine.find(database: database, query: q).files.map(\.path) == [a.path], "cancelled refresh preserves previous searchable contents")
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
        let summary = try FolioIndexEngine.summary(database: database), full = try FolioIndexEngine.stats(database: database)
        check(summary.count == full.count && summary.updatedAt == full.updatedAt, "summary matches the full statistics")
        try FileManager.default.removeItem(at: a); try FileManager.default.removeItem(at: c)
        let emptied = try FolioIndexEngine.rebuild(config: config, database: database)
        check(emptied.count == 0 && emptied.removed == 2, "deleting all documents commits an empty index")

        // One search implementation serves the sidebar and `folio search/files`.
        let search = temporary.appendingPathComponent("Search"), searchRepo = search.appendingPathComponent("my_repo")
        try FileManager.default.createDirectory(at: searchRepo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try write(searchRepo.appendingPathComponent("percent.md"), "# Plan\n取 10% 多年平均\n  Reservoir level  \nreservoir again\nRESERVOIR third\n")
        try write(searchRepo.appendingPathComponent("under.md"), "# Other\nsnake_case name\n")
        try write(searchRepo.appendingPathComponent("水库.md"), "no heading here\n")
        var searchConfig = FolioIndexConfig(); searchConfig.roots = [search.path]
        let searchDB = temporary.appendingPathComponent("state/search.db")
        _ = try FolioIndexEngine.rebuild(config: searchConfig, database: searchDB)
        func found(_ text: String, _ edit: (inout FolioIndexQuery) -> Void = { _ in }) throws -> FolioSearchResult {
            var request = FolioIndexQuery(); request.query = text; edit(&request); return try FolioIndexEngine.find(database: searchDB, query: request)
        }
        check(try found("%").files.map { URL(fileURLWithPath: $0.path).lastPathComponent } == ["percent.md"], "percent is literal, not a wildcard")
        check(try found("_").files.map { URL(fileURLWithPath: $0.path).lastPathComponent } == ["under.md"], "underscore is literal, not a wildcard")
        let titleOnly = try found("水库")
        check(titleOnly.mode == .like && titleOnly.files.count == 1 && titleOnly.files[0].lines.isEmpty, "short query matches title or body; title-only match has no line hits")
        let reservoir = try found("  reservoir  ")
        check(reservoir.query == "reservoir" && reservoir.mode == .fts, "query is trimmed before choosing the path")
        check(reservoir.files.first?.lines.map(\.line) == [3, 4, 5] && reservoir.files.first?.lines.first?.text == "Reservoir level", "line hits are case-insensitive, 1-based and trimmed")
        check(try found("reservoir") { $0.perFile = 1 }.files.first?.lines.count == 1, "per-file cap limits line hits")
        check(try found("reservoir") { $0.perFile = 0 }.files.first?.lines.isEmpty == true, "per-file 0 skips line hits")
        check(try found("reservoir").files.first?.body == nil && found("reservoir") { $0.includeBody = true }.files.first?.body?.contains("again") == true, "bodies only on request")
        check(try found("   ").mode == .filter && found("   ").files.count == 3, "blank query lists by filters only")
        check(try found("") { $0.limit = 2 }.truncated && !(try found("") { $0.limit = 4 }).truncated, "truncation reported when the limit is reached")
        let unlimited = try found("") { $0.limit = 0 }
        check(unlimited.files.count == 3 && !unlimited.truncated, "limit 0 means no limit, never an empty result")
        check(try found("") { $0.path = "percent" }.files.count == 1 && found("") { $0.path = "percen_" }.files.isEmpty, "path filter is a literal substring")
        check(try found("reservoir") { $0.titleOnly = true }.files.isEmpty && found("Plan") { $0.titleOnly = true }.files.count == 1, "title-only search")

        // Database resolution: --db, MDINDEX_DB, the custom path saved in Settings, the default.
        unsetenv("MDINDEX_DB")
        check(FolioIndexConfig.resolveDatabase(setting: nil).source == "default", "default database when nothing is set")
        check(FolioIndexConfig.resolveDatabase(setting: " /tmp/custom.db ").url.path == "/tmp/custom.db", "Settings custom path applies")
        setenv("MDINDEX_DB", "/tmp/env.db", 1)
        check(FolioIndexConfig.resolveDatabase(setting: "/tmp/custom.db").source == "environment", "environment overrides the saved setting")
        check(FolioIndexConfig.resolveDatabase(explicit: "/tmp/option.db", setting: "/tmp/custom.db").url.path == "/tmp/option.db", "explicit path wins")
        unsetenv("MDINDEX_DB")
        let sessionState = temporary.appendingPathComponent("session-state")
        try FileManager.default.createDirectory(at: sessionState, withIntermediateDirectories: true)
        try write(sessionState.appendingPathComponent("session.json"), #"{"documents":[{"text":"\"noteIndexPath\": x"}],"settings":{"imageFolder":"assets"}}"#)
        check(FolioIndexConfig.savedIndexSetting(in: sessionState) == nil, "escaped key text inside a document is not a setting")
        try write(sessionState.appendingPathComponent("session.json"), #"{"documents":[],"settings":{"noteIndexPath":"~/custom.db"}}"#)
        check(FolioIndexConfig.savedIndexSetting(in: sessionState) == "~/custom.db", "saved custom index path is read")
        check(FolioIndexConfig.savedIndexSetting(in: temporary.appendingPathComponent("absent")) == nil, "missing session has no setting")

        // Index folders: Settings and `folio roots` share add/remove.
        let rootsURL = temporary.appendingPathComponent("roots/index.json")
        let added = try FolioIndexConfig.addRoots([search.path, search.path + "/"], at: rootsURL)
        check(added.added == [search.path] && added.unchanged == [search.path] && added.roots == [search.path], "add standardizes and de-duplicates")
        check((try FileManager.default.attributesOfItem(atPath: rootsURL.path)[.posixPermissions] as? Int) == 0o600, "saved configuration is private")
        let before = try Data(contentsOf: rootsURL)
        var missingRoot = false
        do { _ = try FolioIndexConfig.addRoots([search.path, temporary.appendingPathComponent("nope").path], at: rootsURL) } catch { missingRoot = true }
        check(try missingRoot && Data(contentsOf: rootsURL) == before, "a missing folder rejects the whole change")
        let again = try FolioIndexConfig.addRoots([search.path], at: rootsURL)
        check(try !again.changed && Data(contentsOf: rootsURL) == before, "adding an existing folder writes nothing")
        var external = try FolioIndexConfig.load(from: rootsURL); external.roots.append(root.path); external.skipHidden = false; try external.save(to: rootsURL)
        let removed = try FolioIndexConfig.removeRoots([search.path, "/not/configured"], at: rootsURL)
        let kept = try FolioIndexConfig.load(from: rootsURL)
        check(removed.removed == [search.path] && removed.notFound == ["/not/configured"] && kept.roots == [root.path] && !kept.skipHidden, "remove re-reads the file and keeps other edits")
        try write(rootsURL, "{ not json")
        var unreadable = false
        do { _ = try FolioIndexConfig.addRoots([search.path], at: rootsURL) } catch { unreadable = true }
        check(try unreadable && String(contentsOf: rootsURL, encoding: .utf8) == "{ not json", "an unreadable configuration is never replaced")
        print(failures == 0 ? "Index engine checks passed" : "\(failures) checks failed")
        exit(failures == 0 ? 0 : 1)
    }
}
