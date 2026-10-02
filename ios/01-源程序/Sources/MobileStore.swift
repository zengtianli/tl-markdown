import SwiftUI

@MainActor final class MobileStore: ObservableObject {
    @Published private(set) var documents: [OpenDocument] = []
    @Published private(set) var activeID: String?
    @Published var notice = ""
    @Published var reading = true
    @Published var sourceMode = false
    let workspace: DocumentWorkspace
    var active: OpenDocument? { documents.first { $0.id == activeID } }
    private let editorFlushes = EditorFlushRegistry()

    /// An explicitly supplied workspace has one owner, including when several
    /// editor instances share it. It never opens the default recovery directory.
    init(workspace: DocumentWorkspace) {
        self.workspace = workspace
        notice = workspace.permissionNotice
        refresh()
    }

    init() {
        let demo = ProcessInfo.processInfo.arguments.contains("-folio-demo")
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(demo ? "FolioMobile-Demo" : "FolioMobile", isDirectory: true)
        do { workspace = try DocumentWorkspace(directory: base) }
        catch {
            // Preserve unreadable recovery records. A separate rescue session never replaces them.
            workspace = try! DocumentWorkspace(directory: base.appendingPathComponent("Rescue-\(UUID().uuidString)"))
            notice = error.localizedDescription
        }
        if !workspace.permissionNotice.isEmpty { notice = workspace.permissionNotice }
        if demo, workspace.snapshot.documents.isEmpty,
           let fixture = Bundle.main.url(forResource: "demo", withExtension: "md"),
           let text = try? String(contentsOf: fixture, encoding: .utf8) {
            try? workspace.newDocument(text: text)
        }
        refresh()
    }
    func refresh() { documents = workspace.snapshot.documents; activeID = workspace.snapshot.activeID }
    func perform(_ body: () throws -> Void) {
        do { try body(); refresh() } catch { refresh(); notice = error.localizedDescription }
    }
    func registerEditor(scene: String, token: String, flush: @escaping () async throws -> Void) { editorFlushes.register(scene: scene, token: token, flush: flush) }
    func unregisterEditor(scene: String, token: String) {
        editorFlushes.remove(scene: scene, token: token)
        workspace.releaseEditor(owner: token)
    }
    func open(_ url: URL, editorID: String) async {
        do { try await flush(editorID: editorID); _ = try workspace.open(url); refresh() }
        catch { notice = error.localizedDescription }
    }
    func select(_ id: String, editorID: String) async {
        do { try await flush(editorID: editorID); try workspace.select(id); refresh() }
        catch { notice = error.localizedDescription }
    }
    func newDocument(editorID: String) async {
        do { try await flush(editorID: editorID); _ = try workspace.newDocument(); reading = false; refresh() }
        catch { notice = error.localizedDescription }
    }
    func changed(_ body: [String: Any], owner: String) throws -> Int {
        guard let id = body["id"] as? String, let text = body["text"] as? String,
              let generation = body["mobileGeneration"] as? String else { throw DocumentError.state("编辑器版本标记缺失；原文未覆盖") }
        let revision = try workspace.applyEditor(owner: owner, generation: generation, id: id, text: text,
                                                 selection: body["selection"] as? Int ?? 0, scroll: body["scroll"] as? Double ?? 0)
        refresh(); return revision
    }
    func flush(editorID: String) async throws { try await editorFlushes.flush(scene: editorID); try workspace.persist() }
    func save(editorID: String) async {
        let intendedID = activeID
        do { try await flush(editorID: editorID); guard let intendedID else { throw DocumentError.missing }; try workspace.save(id: intendedID); refresh(); notice = "已安全保存到原文件" }
        catch { refresh(); notice = error.localizedDescription }
    }
}
