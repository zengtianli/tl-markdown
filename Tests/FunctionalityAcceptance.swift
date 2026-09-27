import AppKit
import Foundation
import SQLite3

/// Fixed, noninteractive acceptance against production classes and synthetic files only.
@main enum FunctionalityAcceptance {
    struct Failure: Error { let label: String }

    static func require(_ condition: @autoclosure () throws -> Bool, _ label: String) throws {
        guard try condition() else { throw Failure(label: label) }
        print("PASS \(label)")
    }

    @MainActor static func main() async {
        do {
            try await run()
            print("Functionality acceptance passed; synthetic data only, no windows or input events.")
        } catch let error as Failure {
            fputs("FAIL \(error.label)\n", stderr)
            exit(1)
        } catch {
            // Do not expose fixture paths or document content in public acceptance logs.
            fputs("FAIL functionality fixture or production operation (\((error as NSError).domain))\n", stderr)
            exit(1)
        }
    }

    @MainActor static func run() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        guard CommandLine.arguments.count == 2 else { throw Failure(label: "isolated fixture directory required") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL.resolvingSymlinksInPath()
        let state = root.appendingPathComponent("state")
        let a = root.appendingPathComponent("中文 文稿 😀.md")
        let b = root.appendingPathComponent("第二份 文稿.markdown")
        let original = "\u{FEFF}# 中文标题\r\n\r\n原稿 😀\r\n"
        let other = "# 第二份\n\n保持不变\n"
        try Data(original.utf8).write(to: a)
        try Data(other.utf8).write(to: b)
        let store = EditorStore(directory: state)
        store.open(a)
        try require(store.documents.count == 1 && store.active?.path == a.path, "open Unicode, emoji and spaced Markdown filename")
        guard let aid = store.activeID else { throw Failure(label: "opened document has identity") }
        try require(store.active?.bom == true && store.active?.lineEnding == "\r\n", "production open detects BOM and CRLF")
        try require(store.save(), "unchanged production store save succeeds")
        try require(Data(contentsOf: a) == Data(original.utf8), "unchanged save preserves exact UTF-8 bytes")

        let edited = "# 中文标题\n\n自动保存 😀\n"
        store.changed(id: aid, text: edited, selection: 7, scroll: 120)
        try await waitUntil("timed autosave writes edited document") {
            (try? DocumentIO.open(a).text) == edited && store.active?.dirty == false
        }
        try require(Data(contentsOf: a) == Data(("\u{FEFF}" + edited.replacingOccurrences(of: "\n", with: "\r\n")).utf8), "autosave retains BOM and original CRLF encoding")

        store.open(b)
        guard let bid = store.activeID else { throw Failure(label: "second opened document has identity") }
        try require(aid != bid && store.documents.count == 2 && store.active?.text == other, "open .markdown extension into another tab")
        let background = edited + "后台标签更新\n"
        store.changed(id: aid, text: background, selection: 9, scroll: 180)
        try await waitUntil("background-tab autosave writes correct document") {
            (try? DocumentIO.open(a).text) == background
        }
        try require(store.activeID == bid && Data(contentsOf: b) == Data(other.utf8), "background save preserves active tab and unrelated disk file")
        store.open(a)
        try require(store.activeID == aid && store.documents.count == 2, "duplicate open selects existing tab without duplication")
        store.select(bid)
        try require(store.activeID == bid && store.active?.text == other, "tab selection resolves original document content")

        let note = root.appendingPathComponent("检索 命中😀.md")
        let body = "# 检索样例\n😀前导段\n汛限水位需要复核\n100% 完成\n"
        try Data(body.utf8).write(to: note)
        let indexURL = root.appendingPathComponent("synthetic-index.db")
        try createIndex(at: indexURL, note: note, body: body)
        let indexBefore = try Data(contentsOf: indexURL)
        store.notes.indexPath = indexURL
        store.notes.query = "汛限水位"
        store.notes.schedule(immediately: true)
        try await waitUntil("real asynchronous full-text query completes") {
            store.notes.result.query == "汛限水位" && !store.notes.searching
        }
        try require(store.notes.result.error == nil && store.notes.result.mode == .fts, "three-plus-character query uses production FTS5")
        try require(store.notes.result.files.count == 1 && store.notes.result.files.first?.path == note.path, "search finds the synthetic note with exact path")
        guard let hit = store.notes.result.files.first?.lines.first else { throw Failure(label: "search returns a real matching line") }
        try require(hit.line == 3 && hit.text == "汛限水位需要复核", "search line and snippet match the document")
        store.openNote(path: hit.path, line: hit.line)
        try require(store.active?.path == note.path && store.active?.text == body, "search-result action opens the actual matching document")
        try require(noteLineOffset(body, line: hit.line) == ("# 检索样例\n😀前导段\n" as NSString).length, "search jump offset uses UTF-16 after emoji")
        let tabCount = store.documents.count
        store.openNote(path: hit.path, line: hit.line)
        try require(store.documents.count == tabCount, "reopening a search hit reuses its tab")

        store.notes.query = "水位"
        store.notes.schedule(immediately: true)
        try await waitUntil("short Chinese query completes") { store.notes.result.query == "水位" && !store.notes.searching }
        try require(store.notes.result.mode == .like && store.notes.result.files.first?.lines.first?.line == 3, "two-character query falls back to literal matching")
        store.notes.query = "%"
        store.notes.schedule(immediately: true)
        try await waitUntil("literal symbol query completes") { store.notes.result.query == "%" && !store.notes.searching }
        try require(store.notes.result.files.count == 1 && store.notes.result.files.first?.lines.first?.line == 4, "percent query matches literal symbol rather than wildcard")
        try require(Data(contentsOf: indexURL) == indexBefore, "production search leaves index bytes unchanged")

        store.select(aid)
        if let recent = store.recent.first(where: { $0.path == a.path }) { store.pin(recent) }
        store.persist()
        let restored = EditorStore(directory: state)
        try require(restored.documents.count == store.documents.count && restored.activeID == aid, "production session restores tabs and active document")
        try require(restored.active?.text == background && restored.active?.selection == 9 && restored.active?.scroll == 180, "session restores content and reading position")
        try require(restored.recent.contains(where: { $0.path == a.path && $0.pinned }), "pinned recent document survives session reload")
        restored.close(bid) // Clean document only: this cannot open a confirmation panel.
        try require(!restored.documents.contains(where: { $0.id == bid }) && Data(contentsOf: b) == Data(other.utf8), "closing a clean tab leaves its file intact")
    }

    @MainActor static func waitUntil(_ label: String, _ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { print("PASS \(label)"); return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw Failure(label: label)
    }

    static func createIndex(at url: URL, note: URL, body: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else { throw Failure(label: "create isolated SQLite fixture") }
        defer { sqlite3_close(database) }
        func execute(_ sql: String) throws {
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw Failure(label: "build synthetic FTS5 fixture") }
        }
        try execute("CREATE TABLE doc(id INTEGER PRIMARY KEY, path TEXT, ws TEXT, repo TEXT, rel TEXT, title TEXT, body TEXT, nchar INT, mtime TEXT)")
        try execute("CREATE VIRTUAL TABLE doc_fts USING fts5(title, body, content='doc', content_rowid='id', tokenize='trigram')")
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT INTO doc VALUES(1, ?, 'acceptance', 'synthetic', 'note.md', '检索样例', ?, 40, '2026-01-01')", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw Failure(label: "prepare synthetic index row") }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, note.path, -1, transient)
        sqlite3_bind_text(statement, 2, body, -1, transient)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw Failure(label: "insert synthetic index row") }
        try execute("INSERT INTO doc_fts(doc_fts) VALUES('rebuild')")
    }
}
