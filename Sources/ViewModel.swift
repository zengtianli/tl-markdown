import SwiftUI
import UniformTypeIdentifiers

struct OutlineItem: Identifiable { var id: Int; var title: String; var level: Int }
@MainActor final class EditorStore: ObservableObject {
    @Published var documents: [OpenDocument] = []
    @Published var activeID: String?
    @Published var recent: [RecentFile] = []
    @Published var settings = EditorSettings()
    @Published var outline: [OutlineItem] = []
    @Published var sourceMode = false
    @Published var sidebar = true
    @Published var sidebarTab = 0
    @Published var banner = ""
    @Published var showSettings = false
    @Published var closedDrafts: [OpenDocument] = []
    let disk: SessionDisk
    let bridge = EditorBridge()
    private var saveWork: [String: DispatchWorkItem] = [:]
    private var snapshotWork: DispatchWorkItem?
    private var watchTimer: Timer?
    private var stateReadable = true
    private var fileSignatures: [String: Date] = [:]
    var active: OpenDocument? { documents.first { $0.id == activeID } }

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TLMarkdown")
        disk = SessionDisk(directory: base); bridge.store = self
        do {
            let old = try disk.read(); settings = old.settings; recent = old.recent; closedDrafts = old.closedDrafts ?? []
            documents = old.documents.filter { settings.restoreSession || $0.dirty }
            for i in documents.indices {
                if documents[i].dirty {
                    documents[i].message = "已恢复上次未保存的草稿"; banner = "已恢复未保存内容。请检查后保存。"
                    if let path = documents[i].path { documents[i].conflict = (try? Data(contentsOf: URL(fileURLWithPath: path))) != documents[i].diskData }
                } else if let path = documents[i].path {
                    do {
                        var live = try DocumentIO.open(URL(fileURLWithPath: path))
                        live.id = documents[i].id; live.scroll = documents[i].scroll; live.selection = documents[i].selection; documents[i] = live
                    } catch { documents[i].message = error.localizedDescription; documents[i].conflict = true }
                }
            }
            activeID = documents.contains { $0.id == old.activeID } ? old.activeID : documents.first?.id
        } catch {
            banner = error.localizedDescription
            // Keep the corrupt record intact, then permit new drafts to be recovered normally.
            do {
                let preserved = disk.directory.appendingPathComponent("session-unreadable-\(UUID().uuidString).json")
                try FileManager.default.moveItem(at: disk.file, to: preserved)
                banner += " 已保留原记录，可继续编辑。"
            } catch { stateReadable = false; banner += " 新草稿无法持久化，请先另存为。" }
        }
        watchTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.checkExternalChanges() } }
    }
    func persist() {
        guard stateReadable else { return }
        do { try disk.write(SessionSnapshot(documents: documents, activeID: activeID, recent: recent, settings: settings, closedDrafts: closedDrafts)) }
        catch { banner = "恢复草稿未能写入磁盘：\(error.localizedDescription)" }
    }
    func persistSoon() {
        snapshotWork?.cancel(); let work = DispatchWorkItem { [weak self] in self?.persist() }
        snapshotWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
    func newDocument() { let doc = OpenDocument(); documents.append(doc); activeID = doc.id; outline = []; persist(); display() }
    func openExample() {
        guard let original = Bundle.main.resourceURL?.appendingPathComponent("欢迎使用.md") else { return }
        let destination = disk.directory.appendingPathComponent("欢迎使用.md")
        do {
            try FileManager.default.createDirectory(at: disk.directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.copyItem(at: original, to: destination) }
            open(destination)
        } catch { banner = error.localizedDescription }
    }
    func openPanel() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText, .init(filenameExtension: "markdown") ?? .plainText, .plainText]
        if panel.runModal() == .OK { panel.urls.forEach { open($0) } }
    }
    func open(_ url: URL) {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if let existing = documents.first(where: { $0.path == path }) { select(existing.id); return }
        do {
            var doc = try DocumentIO.open(url)
            if let item = recent.first(where: { $0.path == doc.path }) { doc.scroll = item.scroll; doc.selection = item.selection }
            documents.append(doc); activeID = doc.id; touchRecent(doc); persist(); display()
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch { banner = "打开失败：\(error.localizedDescription)" }
    }
    func select(_ id: String) { activeID = id; if let doc = active { touchRecent(doc) }; persistSoon(); display() }
    func display() {
        guard let doc = active else { bridge.send("empty"); outline = []; return }
        outline = []; bridge.load(doc, settings: settings, source: sourceMode)
    }
    func touchRecent(_ doc: OpenDocument) {
        guard let path = doc.path else { return }
        let old = recent.first { $0.path == path }; recent.removeAll { $0.path == path }
        recent.insert(RecentFile(path: path, pinned: old?.pinned ?? false, scroll: doc.scroll, selection: doc.selection), at: 0)
        let pinned = recent.filter(\.pinned); recent = pinned + Array(recent.filter { !$0.pinned }.prefix(max(0, 100 - pinned.count)))
    }
    func pin(_ item: RecentFile) {
        if let index = recent.firstIndex(where: { $0.path == item.path }) { recent[index].pinned.toggle() }
        recent.sort { $0.pinned != $1.pinned ? $0.pinned : $0.opened > $1.opened }; persist()
    }
    func removeRecent(_ item: RecentFile) { recent.removeAll { $0.path == item.path }; persist() }
    func clearRecent() { recent = []; NSDocumentController.shared.clearRecentDocuments(nil); persist() }
    func relocate(_ item: RecentFile) {
        let panel = NSOpenPanel(); panel.message = "重新定位 \(item.name)"
        if panel.runModal() == .OK, let url = panel.url { removeRecent(item); open(url) }
    }
    func changed(id: String, text: String, selection: Int, scroll: Double) {
        guard let i = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[i].text = text; documents[i].selection = selection; documents[i].scroll = scroll
        if !documents[i].conflict { documents[i].message = "" }; persistSoon(); saveWork[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save(id: id, automatic: true) }
        saveWork[id] = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }
    func position(id: String, selection: Int, scroll: Double) {
        guard let i = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[i].selection = selection; documents[i].scroll = scroll
        if let j = recent.firstIndex(where: { $0.path == documents[i].path }) { recent[j].scroll = scroll; recent[j].selection = selection }; persistSoon()
    }
    @discardableResult func save(id: String? = nil, automatic: Bool = false, saveAs: Bool = false) -> Bool {
        guard let targetID = id ?? activeID, let i = documents.firstIndex(where: { $0.id == targetID }) else { return true }
        saveWork[targetID]?.cancel()
        if automatic && (documents[i].path == nil || documents[i].conflict || !documents[i].dirty) { persist(); return true }
        var destination: URL?
        if saveAs || documents[i].path == nil {
            if automatic { return true }
            let panel = NSSavePanel(); panel.nameFieldStringValue = documents[i].title == "未命名" ? "未命名.md" : documents[i].title
            panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
            guard panel.runModal() == .OK, let chosen = panel.url else { return false }; destination = chosen
        }
        do {
            try DocumentIO.save(&documents[i], to: destination)
            if destination != nil { documents[i].revision += 1; display() }
            touchRecent(documents[i]); persist(); return true
        } catch {
            documents[i].message = error.localizedDescription
            if case DocumentError.conflict = error { documents[i].conflict = true }
            if case DocumentError.missing = error { documents[i].conflict = true }
            persist(); return false
        }
    }
    func reload() {
        guard let i = documents.firstIndex(where: { $0.id == activeID }), let path = documents[i].path else { return }
        if documents[i].dirty {
            var copy = documents[i]; copy.id = UUID().uuidString; copy.path = nil; copy.savedText = ""; copy.diskData = nil
            copy.conflict = false; copy.message = "重新载入前的修改副本"; documents.append(copy)
        }
        do {
            var live = try DocumentIO.open(URL(fileURLWithPath: path)); live.id = documents[i].id; live.revision = documents[i].revision + 1
            live.scroll = documents[i].scroll; live.selection = documents[i].selection; documents[i] = live; persist(); display()
        } catch { banner = error.localizedDescription }
    }
    func close(_ id: String) {
        guard let doc = documents.first(where: { $0.id == id }) else { return }
        if doc.dirty {
            let alert = NSAlert(); alert.messageText = "保存“\(doc.title)”的修改？"; alert.informativeText = "选择保留草稿后可在下次启动恢复。"
            alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "保留草稿并关闭")
            let choice = alert.runModal()
            if choice == .alertSecondButtonReturn { return }
            if choice == .alertThirdButtonReturn { closedDrafts.append(doc) }
            else if !save(id: id) { return }
        }
        touchRecent(doc); saveWork[id]?.cancel(); saveWork[id] = nil; documents.removeAll { $0.id == id }; bridge.send("forget", value: id)
        if activeID == id { activeID = documents.last?.id }; persist(); display()
    }
    func restoreClosedDraft() {
        guard var doc = closedDrafts.popLast() else { return }
        if documents.contains(where: { $0.path == doc.path && doc.path != nil }) { doc.path = nil; doc.savedText = ""; doc.diskData = nil }
        if let path = doc.path { doc.conflict = (try? Data(contentsOf: URL(fileURLWithPath: path))) != doc.diskData }
        doc.message = "已恢复关闭的草稿"; documents.append(doc); activeID = doc.id; persist(); display()
    }
    func checkExternalChanges() {
        for i in documents.indices {
            guard let path = documents[i].path else { continue }; let url = URL(fileURLWithPath: path)
            do {
                let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                if date == fileSignatures[path] { continue }; fileSignatures[path] = date
                let data = try Data(contentsOf: url); if data == documents[i].diskData { continue }
                if documents[i].dirty { documents[i].conflict = true; documents[i].message = DocumentError.conflict.localizedDescription }
                else {
                    var live = try DocumentIO.open(url); live.id = documents[i].id; live.scroll = documents[i].scroll
                    live.selection = documents[i].selection; live.revision = documents[i].revision + 1; live.message = "已载入其他软件的修改"; documents[i] = live
                    if activeID == live.id { display() }
                }; persist()
            } catch { if !documents[i].conflict { documents[i].conflict = true; documents[i].message = error.localizedDescription; persist() } }
        }
    }
    func settingsChanged() { persist(); bridge.send("settings", value: ["fontSize": settings.fontSize, "contentWidth": settings.contentWidth, "fontFamily": settings.fontFamily ?? "system"]) }
    func toggleSource() { sourceMode.toggle(); bridge.send("mode", value: sourceMode) }
    func command(_ command: String) { bridge.send("command", value: command) }
    func insertImage(data: Data, ext: String, documentID: String) {
        guard let i = documents.firstIndex(where: { $0.id == documentID }) else { return }
        if documents[i].path == nil && !save(id: documentID) { return }
        do {
            let url = try DocumentIO.imageDestination(document: documents[i], folder: settings.imageFolder, extension: ext)
            try data.write(to: url, options: .atomic)
            bridge.send("insert", value: ["id": documentID, "text": "![图片](<\(settings.imageFolder)/\(url.lastPathComponent)>)"])
        } catch { banner = "插入图片失败：\(error.localizedDescription)" }
    }
    func insertImagePanel() {
        guard let id = activeID else { return }; let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .heic]
        if panel.runModal() == .OK, let url = panel.url {
            do { insertImage(data: try Data(contentsOf: url), ext: url.pathExtension, documentID: id) } catch { banner = error.localizedDescription }
        }
    }
}
