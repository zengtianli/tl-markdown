import XCTest
import WebKit
import UIKit
@testable import Folio

/// SDK integration, without XCUIApplication, input events, or Files picker claims.
/// The hosted app supplies its real Editor resources; all documents/state are synthetic.
@MainActor final class HostedIntegrationTests: XCTestCase {
    struct EditorInstance {
        let view: WKWebView
        let coordinator: MobileEditor.Coordinator
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("folio-hosted-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func wait(_ label: String, timeout: TimeInterval = 20, until predicate: () -> Bool) async throws {
        let limit = Date().addingTimeInterval(timeout)
        while !predicate() {
            guard Date() < limit else { throw NSError(domain: "FolioHostedTimeout", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
    private func editor(_ store: MobileStore, scene: String, reading: Bool = false) async throws -> EditorInstance {
        let document = try XCTUnwrap(store.active)
        let adapter = MobileEditor(store: store, document: document, reading: reading, editorID: scene)
        let coordinator = adapter.makeCoordinator()
        let view = adapter.makeWebView(coordinator: coordinator)
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let instance = EditorInstance(view: view, coordinator: coordinator)
        try await wait("real bundled Editor ready") { coordinator.ready }
        // Do not race the asynchronous production load action with the first edit.
        let wanted = document.text
        try await waitForText(instance, expected: wanted)
        return instance
    }
    private func waitForText(_ editor: EditorInstance, expected: String) async throws {
        let limit = Date().addingTimeInterval(20)
        while true {
            let text = try await editor.view.evaluateJavaScript("window.tl.getText()") as? String
            if text == expected { return }
            guard Date() < limit else { throw NSError(domain: "FolioHostedTimeout", code: 2, userInfo: [NSLocalizedDescriptionKey: "Editor did not load expected text"]) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
    private func waitForJavaScript(_ editor: EditorInstance, script: String) async throws {
        let limit = Date().addingTimeInterval(20)
        while true {
            if try await editor.view.evaluateJavaScript(script) as? Bool == true { return }
            guard Date() < limit else { throw NSError(domain: "FolioHostedTimeout", code: 3, userInfo: [NSLocalizedDescriptionKey: "Rendered Editor condition was not met"]) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
    private func insert(_ text: String, into editor: EditorInstance, id: String) async throws {
        let bytes = try JSONSerialization.data(withJSONObject: ["action": "insert", "value": ["id": id, "text": text]])
        let json = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        // Invoke the original Editor API, not a copied change-message or bridge.
        _ = try await editor.view.evaluateJavaScript("window.tl.receive(\(json))")
        try await editor.coordinator.flush()
    }
    private func close(_ editor: EditorInstance) {
        let coordinator = editor.coordinator
        coordinator.store.unregisterEditor(scene: coordinator.editorID, token: coordinator.owner)
        editor.view.configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        editor.view.stopLoading()
    }

    func testSDKOpenEditSafeSaveAndRecovery() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("合成 文稿.md")
        let original = Data("\u{FEFF}# Synthetic\r\n\r\n中文正文\r\n".utf8)
        try original.write(to: file)
        let state = root.appendingPathComponent("state")
        let store = MobileStore(workspace: try DocumentWorkspace(directory: state))
        await store.open(file, editorID: "A")
        let id = try XCTUnwrap(store.active?.id)
        let reader = try await self.editor(store, scene: "reader", reading: true)
        defer { close(reader) }
        try await waitForJavaScript(reader, script: "window.TL_PREVIEW_ONLY === true && Array.from(document.querySelectorAll('h1')).some(h => h.textContent.trim() === 'Synthetic')")
        close(reader)
        let editor = try await self.editor(store, scene: "A"); defer { close(editor) }
        XCTAssertEqual(store.active?.text, "# Synthetic\n\n中文正文\n")
        XCTAssertEqual(try Data(contentsOf: file), original)
        try await insert("SDK_EDIT", into: editor, id: id)
        try await wait("real WebKit edit reaches shared owner") { store.active?.text.contains("SDK_EDIT") == true }
        XCTAssertEqual(try Data(contentsOf: file), original, "editing must not autosave the original")
        let draft = try XCTUnwrap(store.active)
        let recovered = try DocumentWorkspace(directory: state)
        XCTAssertEqual(recovered.active?.text, draft.text)
        XCTAssertTrue(try XCTUnwrap(recovered.active).dirty)
        await store.save(editorID: "A")
        XCTAssertEqual(store.notice, "已安全保存到原文件")
        XCTAssertEqual(try Data(contentsOf: file), DocumentIO.encoded(draft), "production encoding preserves BOM/newlines")
        XCTAssertFalse(try XCTUnwrap(store.active).dirty)
        let reopened = MobileStore(workspace: try DocumentWorkspace(directory: state))
        await reopened.open(file, editorID: "reopened")
        XCTAssertEqual(reopened.active?.text, draft.text)
        XCTAssertEqual(reopened.active?.path, file.standardizedFileURL.resolvingSymlinksInPath().path)
        XCTAssertFalse(try XCTUnwrap(reopened.active).dirty, "saved document must reopen without a recovery-only draft")
        // External changes must survive a subsequent production save attempt.
        try await insert("UNSAVED", into: editor, id: id)
        let external = Data("# External replacement\n".utf8)
        try external.write(to: file, options: .atomic)
        await store.save(editorID: "A")
        XCTAssertEqual(try Data(contentsOf: file), external)
        XCTAssertTrue(try XCTUnwrap(store.active).dirty)
        XCTAssertTrue(try XCTUnwrap(store.active).conflict)
        let conflictedDraft = try XCTUnwrap(store.active)
        store.perform { try store.workspace.reloadPreservingDraft() }
        XCTAssertEqual(store.active?.text, "# External replacement\n")
        XCTAssertFalse(try XCTUnwrap(store.active).dirty)
        let preserved = try XCTUnwrap(store.documents.first { $0.id != id && $0.path == nil })
        XCTAssertEqual(preserved.text, conflictedDraft.text)
        XCTAssertTrue(preserved.dirty)
        XCTAssertEqual(try Data(contentsOf: file), external)
        let restored = MobileStore(workspace: try DocumentWorkspace(directory: state))
        XCTAssertEqual(restored.active?.text, "# External replacement\n")
        XCTAssertEqual(restored.documents.first { $0.id == preserved.id }?.text, conflictedDraft.text)
    }

    func testTwoRealEditorsRejectStaleWritesAndPreserveConcurrentDraft() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("shared.md")
        try Data("# Shared\n".utf8).write(to: file)
        let state = root.appendingPathComponent("state")
        let store = MobileStore(workspace: try DocumentWorkspace(directory: state))
        await store.open(file, editorID: "A")
        let id = try XCTUnwrap(store.active?.id)
        let a = try await self.editor(store, scene: "A"); defer { close(a) }
        let b = try await self.editor(store, scene: "B"); defer { close(b) }
        try await insert("A_LATEST", into: a, id: id)
        let acceptedA = try XCTUnwrap(store.active?.text)
        // B still contains the old document. Saving A must flush only A.
        await store.save(editorID: "A")
        XCTAssertEqual(store.active?.text, acceptedA)
        let saved = try Data(contentsOf: file)
        do {
            try await b.coordinator.flush()
            XCTFail("stale B must be rejected by the production revision check")
        } catch DocumentError.state(let message) {
            XCTAssertTrue(message.contains("版本已过期"), "expected stale-editor rejection, got: \(message)")
        } catch {
            XCTFail("unexpected stale-B failure: \(error)")
        }
        XCTAssertEqual(store.active?.text, acceptedA, "unchanged stale B cannot undo A")
        XCTAssertEqual(store.documents.count, 1, "stale unchanged text is not a new draft")
        // A real concurrent B edit is refused and retained as a separate draft.
        do {
            try await insert("B_CONCURRENT", into: b, id: id)
            XCTFail("concurrent stale B must be rejected and retained as a draft")
        } catch DocumentError.state(let message) {
            XCTAssertTrue(message.contains("版本已过期"), "expected concurrent-editor rejection, got: \(message)")
        } catch {
            XCTFail("unexpected concurrent-B failure: \(error)")
        }
        try await wait("concurrent B draft is retained") { store.documents.contains { $0.path == nil && $0.text.contains("B_CONCURRENT") } }
        XCTAssertEqual(store.active?.text, acceptedA)
        XCTAssertEqual(try Data(contentsOf: file), saved)
        let recovered = try DocumentWorkspace(directory: state)
        XCTAssertEqual(recovered.active?.text, acceptedA)
        XCTAssertTrue(recovered.snapshot.documents.contains { $0.path == nil && $0.text.contains("B_CONCURRENT") })
        // Re-display binds B to the owner's current revision through production code.
        b.coordinator.display(try XCTUnwrap(store.active), source: false)
        try await waitForText(b, expected: acceptedA)
        try await insert("B_CURRENT", into: b, id: id)
        XCTAssertTrue(try XCTUnwrap(store.active?.text).contains("B_CURRENT"))
    }

    func testSDKFolderHandlerAndDamagedPermissionRecovery() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("images.md")
        try Data("# Local images\n".utf8).write(to: file)
        let state = root.appendingPathComponent("state")
        let store = MobileStore(workspace: try DocumentWorkspace(directory: state))
        await store.open(file, editorID: "image")
        let id = try XCTUnwrap(store.active?.id)
        let editor = try await self.editor(store, scene: "image"); defer { close(editor) }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let png = try XCTUnwrap(renderer.image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }.pngData())
        XCTAssertThrowsError(try store.workspace.storeImage(id: id, data: png, extension: "png"))
        let wrong = root.appendingPathComponent("wrong", isDirectory: true)
        try FileManager.default.createDirectory(at: wrong, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.workspace.authorizeAssetFolder(wrong, id: id))
        try store.workspace.authorizeAssetFolder(root, id: id)
        let image = try store.workspace.storeImage(id: id, data: png, extension: "png")
        let relative = "assets/" + image.url.lastPathComponent
        XCTAssertEqual(try store.workspace.readImage(id: id, relative: relative), png)
        var components = URLComponents()
        components.scheme = "mdasset"
        components.host = "image"
        components.queryItems = [URLQueryItem(name: "id", value: id), URLQueryItem(name: "path", value: relative)]
        let url = try XCTUnwrap(components.url).absoluteString
        let json = try JSONSerialization.data(withJSONObject: [url])
        let literal = try XCTUnwrap(String(data: json, encoding: .utf8))
        let loaded = try await editor.view.callAsyncJavaScript("""
            return await new Promise(resolve => {
                const image = new Image();
                setTimeout(() => resolve(false), 10000);
                image.onload = () => resolve(image.naturalWidth > 0 && image.naturalHeight > 0);
                image.onerror = () => resolve(false);
                image.src = URLS[0];
            });
            """.replacingOccurrences(of: "URLS", with: literal), arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(loaded as? Bool, true, "real WKURLSchemeHandler returns a decodable private image")
        try await insert("RECOVER_ME", into: editor, id: id)
        let draft = try XCTUnwrap(store.active?.text)
        // End the original editor before another workspace becomes a writer.
        close(editor)
        let session = try Data(contentsOf: store.workspace.disk.file)
        let bad = Data("broken-permission-json".utf8)
        let permissionFile = state.appendingPathComponent("bookmarks.json")
        try bad.write(to: permissionFile, options: .atomic)
        let recovered = try DocumentWorkspace(directory: state)
        XCTAssertEqual(recovered.active?.text, draft)
        XCTAssertFalse(recovered.permissionNotice.isEmpty)
        XCTAssertEqual(try Data(contentsOf: recovered.disk.file), session)
        XCTAssertEqual(try Data(contentsOf: permissionFile), bad)
        XCTAssertThrowsError(try recovered.save())
        let export = root.appendingPathComponent("recovered.md")
        let document = try XCTUnwrap(recovered.active)
        try MarkdownExport(document: document).data.write(to: export)
        try recovered.finishExport(document, destination: export)
        XCTAssertEqual(try Data(contentsOf: export), DocumentIO.encoded(document))
    }
}
