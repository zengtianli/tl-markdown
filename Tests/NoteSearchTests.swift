import Foundation
import SQLite3

// Real SQLite FTS5 trigram fixture with the md-index schema; no user notes are read.
@main enum NoteSearchTests {
    static func check(_ failures: inout Int, _ condition: Bool, _ name: String) { print((condition ? "PASS " : "FAIL ") + name); if !condition { failures += 1 } }
    static func main() {
        var failures = 0

        let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory() + "folio-note-search")
        try? FileManager.default.removeItem(at: root)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("index.db")
        var db: OpaquePointer?
        sqlite3_open(file.path, &db)
        let exec: (String) -> Void = { sql in var error: UnsafeMutablePointer<CChar>?; if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK { print("SQL", String(cString: error!)); exit(2) } }
        exec("CREATE TABLE doc(id INTEGER PRIMARY KEY, path TEXT, ws TEXT, repo TEXT, rel TEXT, title TEXT, body TEXT, nchar INT, mtime TEXT)")
        exec("CREATE VIRTUAL TABLE doc_fts USING fts5(title, body, content='doc', content_rowid='id', tokenize='trigram')")
        exec("INSERT INTO doc VALUES (1, '/notes/a.md', 'Work', 'r', 'a.md', '水库调度', '# 水库调度\n第二行\n汛限水位需要复核\n100% 完成', 20, '2026-09-01')")
        exec("INSERT INTO doc VALUES (2, '/notes/b.md', 'Dev', 'r', 'b.md', 'Notes', 'plain\nnothing here\n50_percent', 10, '2026-09-02')")
        exec("INSERT INTO doc_fts(doc_fts) VALUES('rebuild')")
        sqlite3_close(db)

        let index = NoteIndex(path: file)
        let long = index.search("汛限水位")
        check(&failures, long.mode == .fts && long.files.map(\.path) == ["/notes/a.md"] && long.files[0].lines.map(\.line) == [3], "three+ characters use the index and report the real line")
        let short = index.search("水库")
        check(&failures, short.mode == .like && short.files.count == 1 && short.files[0].lines.first?.line == 1, "two-character Chinese falls back instead of silently finding nothing")
        check(&failures, index.search("%").files.map(\.path) == ["/notes/a.md"], "percent is literal, not a wildcard")
        check(&failures, index.search("_").files.map(\.path) == ["/notes/b.md"], "underscore is literal, not a wildcard")
        check(&failures, index.search("   ").files.isEmpty && index.search("   ").error == nil, "blank query does nothing")
        let missing = NoteIndex(path: root.appendingPathComponent("absent.db")).search("水库调度")
        check(&failures, missing.error?.contains("没有找到笔记索引") == true && missing.files.isEmpty, "missing index reports the reason, never substitute data")
        let before = (try? Data(contentsOf: file)) ?? Data()
        _ = index.search("水库调度")
        check(&failures, ((try? Data(contentsOf: file)) ?? Data()) == before, "index file is never written")
        let text = "一\n二二\r\n😀三\n四"
        check(&failures, noteLineOffset(text, line: 1) == 0 && noteLineOffset(text, line: 3) == ("一\n二二\r\n" as NSString).length && noteLineOffset(text, line: 99) == (text as NSString).length, "line offsets are UTF-16 and clamp at the end")
        print(failures == 0 ? "Note search checks passed" : "\(failures) note search checks failed")
        exit(failures == 0 ? 0 : 1)
    }
}
