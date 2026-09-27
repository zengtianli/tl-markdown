import AppKit
import Foundation
import SQLite3
import WebKit

final class PrivacySchemeTask: NSObject, WKURLSchemeTask {
    let request: URLRequest
    var response: URLResponse?
    var received = Data()
    var finished = false
    var failure: Error?
    init(url: URL) { request = URLRequest(url: url) }
    func didReceive(_ response: URLResponse) { self.response = response }
    func didReceive(_ data: Data) { received.append(data) }
    func didFinish() { finished = true }
    func didFailWithError(_ error: Error) { failure = error }
}

/// Feed the production navigation delegate an inert request, without requesting any network URL.
@MainActor final class PrivacyNavigation: WKNavigationAction {
    private let target: URLRequest
    init(url: URL) { target = URLRequest(url: url); super.init() }
    override var request: URLRequest { target }
    override var navigationType: WKNavigationType { .other }
}

@main enum PrivacyAcceptance {
    struct Failure: Error { let label: String }
    static func require(_ condition: @autoclosure () throws -> Bool, _ label: String) throws {
        guard try condition() else { throw Failure(label: label) }
        print("PASS \(label)")
    }
    @MainActor static func main() {
        do {
            try run()
            print("Privacy acceptance passed; synthetic runtime boundaries, no packet capture or external traffic.")
        } catch let error as Failure {
            fputs("FAIL \(error.label)\n", stderr); exit(1)
        } catch {
            fputs("FAIL privacy fixture or production operation (\((error as NSError).domain))\n", stderr); exit(1)
        }
    }
    @MainActor static func run() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        guard CommandLine.arguments.count == 2 else { throw Failure(label: "isolated fixture directory required") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL.resolvingSymlinksInPath()
        let fm = FileManager.default
        let first = SessionDisk(directory: root.appendingPathComponent("first-state"))
        let second = SessionDisk(directory: root.appendingPathComponent("second-state"))
        var document = OpenDocument()
        document.text = "合成隐私检查草稿 alpha"
        try first.write(SessionSnapshot(documents: [document], activeID: document.id))
        func permissions(_ url: URL) throws -> Int {
            (try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
        }
        try require(permissions(first.directory) == 0o700, "new session directory allows only its owner")
        try require(permissions(first.file) == 0o600, "session snapshot allows only its owner")
        let before = try Data(contentsOf: first.file)
        try require(second.read().documents.isEmpty, "different state directory cannot see first session")
        var other = OpenDocument(); other.text = "合成隐私检查草稿 beta"
        try second.write(SessionSnapshot(documents: [other], activeID: other.id))
        try require(Data(contentsOf: first.file) == before && second.read().documents.first?.text == other.text, "writing another session leaves first snapshot unchanged")
        document.text += "更新"
        try first.write(SessionSnapshot(documents: [document], activeID: document.id))
        try require(permissions(first.file) == 0o600 && first.read().documents.first?.text == document.text, "atomic session rewrite retains private permissions")

        let docDirectory = root.appendingPathComponent("documents")
        let outside = root.appendingPathComponent("outside")
        try fm.createDirectory(at: docDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        let sentinel = outside.appendingPathComponent("sentinel.txt")
        let sentinelBytes = Data("synthetic boundary marker".utf8)
        try sentinelBytes.write(to: sentinel)
        let file = docDirectory.appendingPathComponent("synthetic.md")
        try Data("# Privacy fixture\n".utf8).write(to: file)
        let live = try DocumentIO.open(file)
        for folder in ["", "../outside", "assets/../../outside", outside.path] {
            var rejected = false
            do { _ = try DocumentIO.imageDestination(document: live, folder: folder, extension: "png") }
            catch DocumentError.imageFolder { rejected = true }
            try require(rejected, "invalid image destination is rejected")
        }
        try require(fm.contentsOfDirectory(atPath: outside.path) == ["sentinel.txt"] && Data(contentsOf: sentinel) == sentinelBytes, "invalid destinations neither write nor alter outside files")
        let image = try DocumentIO.imageDestination(document: live, folder: "assets", extension: "png")
        try require(image.deletingLastPathComponent() == docDirectory.appendingPathComponent("assets", isDirectory: true), "valid image destination stays in requested adjacent folder")
        // A complete 1x1 PNG fixture, never a user image.
        let imageBytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6hWQAAAAASUVORK5CYII=")!
        try imageBytes.write(to: image)

        let index = root.appendingPathComponent("synthetic-index.db")
        try createIndex(index)
        let databaseBefore = try Data(contentsOf: index)
        let modifiedBefore = try fm.attributesOfItem(atPath: index.path)[.modificationDate] as? Date
        try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: index.path)
        let search = NoteIndex(path: index)
        try require(search.search("隐私验收").files.count == 1, "production search reads an explicitly read-only synthetic index")
        try require(Data(contentsOf: index) == databaseBefore, "full-text search leaves every database byte unchanged")
        try require((fm.attributesOfItem(atPath: index.path)[.modificationDate] as? Date) == modifiedBefore, "search leaves database modification time unchanged")
        try require(!fm.fileExists(atPath: index.path + "-wal") && !fm.fileExists(atPath: index.path + "-journal"), "search creates no write-ahead log or rollback journal")

        let store = EditorStore(directory: root.appendingPathComponent("bridge-state"))
        // Supply the production bridge a synthetic document directly, avoiding system recents.
        store.documents = [live]; store.activeID = live.id
        let bridge = RichEditorBridge(); bridge.store = store
        let web = bridge.makeWebView()
        defer { web.stopLoading(); web.configuration.userContentController.removeScriptMessageHandler(forName: "editor") }
        try require(!web.configuration.websiteDataStore.isPersistent, "production WebKit editor uses an ephemeral data store")
        for scheme in ["https", "http"] {
            let navigation = PrivacyNavigation(url: URL(string: "\(scheme)://example.invalid/privacy-fixture")!)
            var policy: WKNavigationActionPolicy?
            bridge.webView(web, decidePolicyFor: navigation) { policy = $0 }
            try require(policy == .cancel, "production delegate rejects remote programmatic navigation")
        }
        var localPolicy: WKNavigationActionPolicy?
        bridge.webView(web, decidePolicyFor: PrivacyNavigation(url: file)) { localPolicy = $0 }
        try require(localPolicy == .allow, "production delegate retains local-file navigation")
        func task(id: String, path: String) -> PrivacySchemeTask {
            var components = URLComponents(); components.scheme = "mdasset"; components.host = "fixture"
            components.queryItems = [URLQueryItem(name: "id", value: id), URLQueryItem(name: "path", value: path)]
            return PrivacySchemeTask(url: components.url!)
        }
        let approved = task(id: live.id, path: "assets/" + image.lastPathComponent)
        bridge.webView(web, start: approved)
        try require(approved.finished && approved.failure == nil && approved.received == imageBytes, "mdasset returns exact approved image bytes")
        let forbidden = task(id: live.id, path: "../outside/sentinel.txt")
        bridge.webView(web, start: forbidden)
        try require(forbidden.failure != nil && !forbidden.finished && forbidden.received.isEmpty && forbidden.response == nil, "mdasset refuses non-image file content before returning bytes")
        let unknown = task(id: "unknown-document", path: "assets/" + image.lastPathComponent)
        bridge.webView(web, start: unknown)
        try require(unknown.failure != nil && unknown.received.isEmpty, "mdasset refuses unknown document identity")
        try require(Data(contentsOf: sentinel) == sentinelBytes, "bridge asset checks leave external fixture unchanged")
    }

    static func createIndex(_ url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else { throw Failure(label: "open synthetic index") }
        defer { sqlite3_close(database) }
        let sql = """
        CREATE TABLE doc(id INTEGER PRIMARY KEY, path TEXT, ws TEXT, repo TEXT, rel TEXT, title TEXT, body TEXT, nchar INT, mtime TEXT);
        CREATE VIRTUAL TABLE doc_fts USING fts5(title, body, content='doc', content_rowid='id', tokenize='trigram');
        INSERT INTO doc VALUES(1, 'synthetic.md', 'fixture', 'fixture', 'synthetic.md', '隐私验收', '隐私验收合成文本', 10, '2026-01-01');
        INSERT INTO doc_fts(doc_fts) VALUES('rebuild');
        """
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw Failure(label: "create synthetic FTS5 fixture") }
    }
}
