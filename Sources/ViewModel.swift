import SwiftUI
import UniformTypeIdentifiers

struct OutlineItem: Identifiable { var id: Int; var title: String; var level: Int }
@MainActor final class EditorStore: ObservableObject {
    // Watch exactly the files that are open; paths only change on open/close/save-as/reload.
    @Published var documents: [OpenDocument] = [] { didSet { watcher?.update(Set(documents.compactMap(\.path))) } }
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
    @Published private(set) var graphGenerating = false
    @Published private(set) var lastGraphURL: URL?
    @Published private(set) var graphError: String?
    let disk: SessionDisk
    let indexSettings: NoteIndexSettingsModel
    let bridge = EditorBridge()
    let notes = NoteSearchModel()
    private var saveWork: [String: DispatchWorkItem] = [:]
    private var snapshotWork: DispatchWorkItem?
    private(set) var watcher: ExternalChangeWatcher?
    private var stateReadable = true
    private var fileSignatures: [String: Date] = [:]
    /// The message each open conflict put on its document, so resolving it clears only that text.
    private var conflictNotes: [String: String] = [:]
    /// Documents whose autosave was skipped because of a conflict; saved as soon as it resolves.
    private var blockedAutosave: Set<String> = []
    var active: OpenDocument? { documents.first { $0.id == activeID } }

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TLMarkdown")
        disk = SessionDisk(directory: base)
        indexSettings = NoteIndexSettingsModel(configURL: directory?.appendingPathComponent("index.json") ?? FolioIndexConfig.defaultURL,
            database: directory?.appendingPathComponent("md_index.db") ?? NoteIndex.defaultPath)
        bridge.store = self
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
                    } catch { flagConflict(i, error.localizedDescription) }
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
        // Event-driven: an idle window does no periodic work (formerly a 2 s stat poll).
        watcher = ExternalChangeWatcher { [weak self] in self?.checkExternalChanges() }
        watcher?.update(Set(documents.compactMap(\.path)))
        indexSettings.onUpdated = { [weak self] in self?.notes.reloadIndex() }
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
        if !documents[i].conflict { documents[i].message = "" }; persistSoon(); scheduleAutosave(id)
    }
    private func scheduleAutosave(_ id: String) {
        saveWork[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save(id: id, automatic: true) }
        saveWork[id] = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }
    private func flagConflict(_ i: Int, _ message: String) {
        documents[i].conflict = true; documents[i].message = message; conflictNotes[documents[i].id] = message
    }
    /// The file is back to the bytes this document was based on (e.g. a moved or deleted file was
    /// restored, or an external edit was undone), so saving is safe again.
    private func conflictResolved(_ i: Int) {
        let id = documents[i].id
        documents[i].conflict = false
        // Clear only the conflict's own message; keep notes such as “已恢复上次未保存的草稿”.
        if let note = conflictNotes.removeValue(forKey: id), documents[i].message == note { documents[i].message = "" }
        // Edits the conflict kept from autosaving are saved now rather than at the next keystroke.
        // A restored draft had no autosave pending and still waits to be reviewed, as at launch.
        if blockedAutosave.remove(id) != nil, documents[i].dirty { scheduleAutosave(id) }
    }
    private func forgetConflict(_ id: String) { conflictNotes[id] = nil; blockedAutosave.remove(id) }
    func position(id: String, selection: Int, scroll: Double) {
        guard let i = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[i].selection = selection; documents[i].scroll = scroll
        if let j = recent.firstIndex(where: { $0.path == documents[i].path }) { recent[j].scroll = scroll; recent[j].selection = selection }; persistSoon()
    }
    @discardableResult func save(id: String? = nil, automatic: Bool = false, saveAs: Bool = false) -> Bool {
        guard let targetID = id ?? activeID, let i = documents.firstIndex(where: { $0.id == targetID }) else { return true }
        saveWork[targetID]?.cancel()
        if automatic && (documents[i].path == nil || documents[i].conflict || !documents[i].dirty) {
            if documents[i].conflict && documents[i].dirty && documents[i].path != nil { blockedAutosave.insert(targetID) }
            persist(); return true
        }
        var destination: URL?
        if saveAs || documents[i].path == nil {
            if automatic { return true }
            let panel = NSSavePanel(); panel.nameFieldStringValue = documents[i].title == "未命名" ? "未命名.md" : documents[i].title
            panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
            guard panel.runModal() == .OK, let chosen = panel.url else { return false }; destination = chosen
        }
        do {
            try DocumentIO.save(&documents[i], to: destination)
            forgetConflict(targetID)
            if destination != nil { documents[i].revision += 1; display() }
            touchRecent(documents[i]); persist(); return true
        } catch {
            switch error {
            case DocumentError.conflict, DocumentError.missing: flagConflict(i, error.localizedDescription)
            default: documents[i].message = error.localizedDescription
            }
            if automatic && documents[i].conflict { blockedAutosave.insert(targetID) }
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
            var live = try DocumentIO.open(URL(fileURLWithPath: path)); live.id = documents[i].id; live.revision = documents[i].revision + 1; forgetConflict(live.id)
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
        touchRecent(doc); saveWork[id]?.cancel(); saveWork[id] = nil; forgetConflict(id); documents.removeAll { $0.id == id }; bridge.send("forget", value: id)
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
                let data = try Data(contentsOf: url)
                if data == documents[i].diskData {
                    if documents[i].conflict { conflictResolved(i); persist() }
                    continue
                }
                if documents[i].dirty { flagConflict(i, DocumentError.conflict.localizedDescription) }
                else {
                    var live = try DocumentIO.open(url); live.id = documents[i].id; live.scroll = documents[i].scroll
                    live.selection = documents[i].selection; live.revision = documents[i].revision + 1; live.message = "已载入其他软件的修改"; documents[i] = live
                    if activeID == live.id { display() }
                }; persist()
            } catch {
                // Forget the signature so a file recreated at this path is examined even if it
                // carries the old modification date (e.g. restored from the Trash).
                fileSignatures[path] = nil
                if !documents[i].conflict { flagConflict(i, error.localizedDescription); persist() }
            }
        }
    }
    /// Opens a search hit and places the cursor at the start of that line.
    func openNote(path: String, line: Int) {
        let before = activeID
        open(URL(fileURLWithPath: path))
        guard let doc = active, doc.path == URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path else { return }
        let offset = noteLineOffset(doc.text, line: line)
        if before == activeID { bridge.send("goto", value: offset) }
        else { DispatchQueue.main.async { [weak self] in self?.bridge.send("goto", value: offset) } }
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

    /// The menu and the in-process UI check share this action; only the menu asks for a folder.
    func generateDirectoryGraphPanel() {
        guard !graphGenerating else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.prompt = "生成目录图谱"
        if panel.runModal() == .OK, let root = panel.url { generateDirectoryGraph(at: root) }
    }
    func generateDirectoryGraph(at root: URL, openBrowser: Bool = true) {
        guard !graphGenerating else { return }
        if let error = indexSettings.configurationError {
            graphError = error; banner = error; return
        }
        graphGenerating = true; graphError = nil; lastGraphURL = nil
        let config = indexSettings.config
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try FolioGraphEngine.generate(root: root, config: config) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.graphGenerating = false
                switch result {
                case .success(let output):
                    self.lastGraphURL = output
                    self.banner = "目录图谱已生成：\(output.lastPathComponent)"
                    if openBrowser { NSWorkspace.shared.open(output) }
                case .failure(let error):
                    self.graphError = error.localizedDescription
                    self.banner = "未生成目录图谱：\(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Index settings
/// Cancellation is shared by the low-priority worker and the main-thread button.
private final class IndexCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

@MainActor final class NoteIndexSettingsModel: ObservableObject {
    @Published private(set) var config = FolioIndexConfig()
    @Published private(set) var updating = false
    @Published private(set) var documentCount = 0
    @Published private(set) var updatedAt: Date?
    @Published private(set) var message = ""
    @Published private(set) var configurationError: String?
    let configURL: URL
    private(set) var database: URL
    private var cancellation: IndexCancellation?
    var onUpdated: (() -> Void)?

    init(configURL: URL, database: URL) {
        self.configURL = configURL; self.database = database
        reloadConfiguration()
    }
    func reloadConfiguration() {
        guard !updating else { return }
        configurationError = nil
        if FileManager.default.fileExists(atPath: configURL.path) {
            do { config = try FolioIndexConfig.load(from: configURL) }
            catch { configurationError = "无法读取索引配置：\(error.localizedDescription)" }
        } else { config = FolioIndexConfig() }
        refreshStats()
    }
    func useDatabase(_ url: URL) {
        guard !updating, url != database else { return }
        database = url; refreshStats()
    }
    private func refreshStats() {
        guard FileManager.default.fileExists(atPath: database.path), let stats = try? FolioIndexEngine.stats(database: database) else {
            documentCount = 0; updatedAt = nil; return
        }
        documentCount = stats.count; updatedAt = stats.updatedAt
    }
    @discardableResult func addRoot(_ url: URL) -> Bool {
        guard !updating, configurationError == nil else { return false }
        let path = url.standardizedFileURL.path
        guard !config.roots.contains(path) else { return true }
        var next = config; next.roots.append(path)
        return save(next)
    }
    func chooseRoots() {
        guard !updating else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true; panel.prompt = "加入索引"
        if panel.runModal() == .OK { for url in panel.urls { _ = addRoot(url) } }
    }
    func removeRoot(_ path: String) {
        guard !updating, configurationError == nil else { return }
        var next = config; next.roots.removeAll { $0 == path }; _ = save(next)
    }
    private func save(_ next: FolioIndexConfig) -> Bool {
        do { try next.save(to: configURL); config = next; message = "文件夹已保存；更新索引后生效。"; return true }
        catch { message = "保存索引配置失败：\(error.localizedDescription)"; return false }
    }
    func updateIndex() {
        guard !updating, configurationError == nil else { return }
        guard !config.roots.isEmpty else { message = "请先添加要索引的文件夹。"; return }
        let token = IndexCancellation(), snapshot = config, target = database
        cancellation = token; updating = true; message = "正在后台更新索引…"
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try FolioIndexEngine.rebuild(config: snapshot, database: target, cancelled: { token.isCancelled }) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.updating = false; self.cancellation = nil
                switch result {
                case .success(let stats):
                    self.documentCount = stats.count; self.updatedAt = stats.updatedAt
                    self.message = "索引已更新，共 \(stats.count.formatted()) 篇。"
                    self.onUpdated?()
                case .failure(let error):
                    self.message = token.isCancelled ? "已取消；原索引保持可用。" : "更新失败：\(error.localizedDescription)"
                }
            }
        }
    }
    func cancelUpdate() { cancellation?.cancel(); if updating { message = "正在取消…" } }
}

// MARK: - Note search
/// Searches Folio's index off the main thread. Typing is debounced and a newer query
/// interrupts an older one still scanning; the index opens on first use and stays read-only.
@MainActor final class NoteSearchModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { schedule() } } }
    @Published private(set) var result = NoteSearchResult()
    @Published private(set) var searching = false
    @Published var focusRequest = 0
    @Published private(set) var indexAvailable = false
    private var index: NoteIndex?
    private var generation = 0
    private var pending: DispatchWorkItem?
    var indexPath: URL = NoteIndex.defaultPath { didSet { if indexPath != oldValue { reloadIndex() } } }

    func reloadIndex() {
        index?.interrupt(); index = nil
        indexAvailable = FileManager.default.fileExists(atPath: indexPath.path)
        schedule(immediately: true)
    }

    func schedule(immediately: Bool = false) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.run() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediately ? 0 : 0.2), execute: work)
    }
    private func run() {
        let text = query
        indexAvailable = FileManager.default.fileExists(atPath: indexPath.path)
        if index == nil || index?.path != indexPath { index = NoteIndex(path: indexPath) }
        guard let index else { return }
        generation += 1
        let current = generation
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { result = NoteSearchResult(); searching = false; return }
        index.interrupt(); searching = true
        index.queue.async { [weak self] in
            let found = index.search(text)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, current == self.generation else { return }
                    self.result = found; self.searching = false
                }
            }
        }
    }
}

// MARK: - External change watching
/// Event-driven replacement for the former 2 s poll. A kqueue vnode source watches each open file
/// and another watches its folder: editors that save atomically replace the file (the watched
/// inode reports delete/rename), and a moved or deleted file may reappear later, which only the
/// folder sees. Bursts are coalesced and handed to `checkExternalChanges`, which compares the
/// actual bytes, so Folio's own saves and unrelated sibling writes cost one stat and change nothing.
/// Volumes that cannot deliver vnode events (network shares) and folders that are missing or cannot
/// be opened fall back to the poll; every poll tick retries events, so a restored folder goes back
/// to event watching and the poll stops.
@MainActor final class ExternalChangeWatcher {
    /// A kqueue source bound to the inode that was at a path when it was opened.
    private struct Watch {
        let source: DispatchSourceFileSystemObject
        let device: dev_t, inode: ino_t
        /// False once that inode was renamed, deleted or replaced at the path, including through
        /// a renamed or deleted parent folder, which the inode itself never reports.
        func current(at path: String) -> Bool {
            var info = stat()
            return stat(path, &info) == 0 && info.st_dev == device && info.st_ino == inode
        }
    }
    private var files: [String: Watch] = [:]
    private var folders: [String: Watch] = [:]
    private var paths: Set<String> = []
    private var polled: Set<String> = []
    private var poll: Timer?
    private var pending: DispatchWorkItem?
    private var activation: NSObjectProtocol?
    private let onChange: () -> Void
    /// Test introspection: which paths have a live file source, which fall back to polling,
    /// whether the poll timer runs, and how many event sources (file descriptors) are open.
    var watchedFiles: Set<String> { Set(files.keys) }
    var polledFiles: Set<String> { polled }
    var polling: Bool { poll != nil }
    var sourceCount: Int { files.count + folders.count }

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        // Safety net for anything kqueue cannot report (e.g. a grandparent folder renamed).
        activation = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
    }
    // A resumed source stays registered with the kernel, keeping its descriptor open and its
    // handler firing, until it is cancelled; the run loop likewise keeps the poll timer alive.
    deinit {
        if let activation { NotificationCenter.default.removeObserver(activation) }
        pending?.cancel(); poll?.invalidate()
        for watch in files.values { watch.source.cancel() }
        for watch in folders.values { watch.source.cancel() }
    }

    func update(_ newPaths: Set<String>) {
        guard newPaths != paths else { return }
        paths = newPaths; rearm()
    }
    private static func folder(of path: String) -> String { (path as NSString).deletingLastPathComponent }
    private func rearm() {
        // Release sources of closed paths and of inodes that no longer live at their path.
        for (path, watch) in files where !paths.contains(path) || !watch.current(at: path) { watch.source.cancel(); files[path] = nil }
        let neededFolders = Set(paths.map(Self.folder(of:)))
        for (folder, watch) in folders where !neededFolders.contains(folder) || !watch.current(at: folder) { watch.source.cancel(); folders[folder] = nil }
        polled = []
        for path in paths {
            let folder = Self.folder(of: path)
            if folders[folder] == nil, Self.eventsSupported(folder) { folders[folder] = watch(folder, folder: true) }
            guard folders[folder] != nil else { polled.insert(path); continue }
            // Absent while the file is moved away or deleted; the folder source reports its return.
            if files[path] == nil { files[path] = watch(path, folder: false) }
        }
        if polled.isEmpty { poll?.invalidate(); poll = nil }
        else if poll == nil {
            poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { guard let self else { return }; self.rearm(); self.onChange() }
            }
            poll?.tolerance = 0.5
        }
    }
    private static func eventsSupported(_ folder: String) -> Bool {
        (try? URL(fileURLWithPath: folder).resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) ?? false
    }
    private func watch(_ path: String, folder: Bool) -> Watch? {
        let fd = open(path, O_EVTONLY | (folder ? O_DIRECTORY : 0))
        guard fd >= 0 else { return nil }
        var info = stat()
        guard fstat(fd, &info) == 0 else { close(fd); return nil }
        let events: DispatchSource.FileSystemEvent = folder ? [.write, .delete, .rename, .revoke]
            : [.write, .extend, .attrib, .delete, .rename, .revoke]
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: events, queue: .main)
        source.setEventHandler { [weak self, weak source] in
            MainActor.assumeIsolated {
                guard let self, let source else { return }
                if !source.data.isDisjoint(with: [.delete, .rename, .revoke]) {
                    // This inode no longer lives at the path: drop it and reopen by path below.
                    source.cancel()
                    if folder { if (self.folders[path]?.source as AnyObject?) === (source as AnyObject) { self.folders[path] = nil } }
                    else if (self.files[path]?.source as AnyObject?) === (source as AnyObject) { self.files[path] = nil }
                }
                self.schedule()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return Watch(source: source, device: info.st_dev, inode: info.st_ino)
    }
    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { guard let self else { return }; self.pending = nil; self.rearm(); self.onChange() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }
}
