import Foundation
import AppKit

@main struct StoreTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let a = root.appendingPathComponent("a.md"), b = root.appendingPathComponent("b.md")
        try Data("# A\n\n原文\n".utf8).write(to: a); try Data("# B\n".utf8).write(to: b)
        let store = EditorStore(directory: root.appendingPathComponent("state"))
        func check(_ ok: @autoclosure () -> Bool, _ name: String) throws {
            if !ok() { throw NSError(domain:"StoreTests",code:1,userInfo:[NSLocalizedDescriptionKey:name]) };print("PASS \(name)")
        }
        store.open(a); let aid = store.activeID!
        store.changed(id: aid, text: "# A\n\n自动保存中文😀\n", selection: 10, scroll: 120)
        try await Task.sleep(for: .milliseconds(1000))
        let saved = try DocumentIO.open(a)
        try check(saved.text.contains("自动保存中文😀"), "actual store autosave writes original file")
        store.open(b); let bid = store.activeID!
        store.changed(id: aid, text:"# A\n后台标签修改\n", selection: 4, scroll: 30)
        try await Task.sleep(for: .milliseconds(1000))
        try check(store.activeID == bid, "background document save does not switch active tab")
        let background = try DocumentIO.open(a), untouched = try DocumentIO.open(b)
        try check(background.text.contains("后台标签") && untouched.text == "# B\n", "autosave targets document ID, not active tab")
        try Data("# A\n外部更新\n".utf8).write(to: a); store.checkExternalChanges()
        try check(store.documents.first(where:{$0.id==aid})?.text.contains("外部更新") == true, "clean document reloads external edits")
        store.select(aid);store.changed(id:aid,text:"本地冲突版本",selection:3,scroll:20)
        try Data("磁盘冲突版本".utf8).write(to:a);store.checkExternalChanges()
        try await Task.sleep(for: .milliseconds(1000))
        try check(store.active?.conflict == true && store.active?.text == "本地冲突版本", "watcher preserves conflicting local draft")
        let external = try DocumentIO.open(a);try check(external.text == "磁盘冲突版本", "automatic save stays blocked after conflict")
        store.reload()
        try check(store.active?.text == "磁盘冲突版本", "reload selects disk version")
        try check(store.documents.contains(where:{$0.path == nil && $0.text == "本地冲突版本"}), "reload keeps local version in recoverable separate draft")
        store.pin(store.recent.first!);store.settings.fontSize = 21;store.persist()
        let restored = EditorStore(directory:root.appendingPathComponent("state"))
        try check(restored.documents.count == store.documents.count && restored.settings.fontSize == 21, "real store restores tabs, drafts and settings")
        try check(restored.recent.contains(where:{$0.pinned}), "real store restores pinned recent entry")
        restored.clearRecent();try check(restored.recent.isEmpty && FileManager.default.fileExists(atPath:a.path), "clearing history leaves documents intact")
        // Settings "更新索引" rebuilds from index.json as it is on disk: a folder added by
        // `folio roots add` after Settings read the file is indexed, not dropped.
        let settingsModel = store.indexSettings, notes = root.appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try Data("# 笔记\n\n水库\n".utf8).write(to: notes.appendingPathComponent("n.md"))
        try check(settingsModel.config.roots.isEmpty, "settings start without index folders")
        _ = try FolioIndexConfig.addRoots([notes.path], at: settingsModel.configURL)
        settingsModel.updateIndex()
        var waited = 0
        while settingsModel.updating && waited < 200 { try await Task.sleep(for: .milliseconds(50)); waited += 1 }
        try check(settingsModel.config.roots.count == 1 && settingsModel.documentCount == 1, "settings update index re-reads folders changed by folio roots: " + settingsModel.message)
        _ = try FolioIndexConfig.removeRoots([notes.path], at: settingsModel.configURL)
        try Data("{bad".utf8).write(to: settingsModel.configURL)
        settingsModel.updateIndex()
        try check(!settingsModel.updating && settingsModel.configurationError != nil && settingsModel.documentCount == 1, "unreadable index.json stops the update and keeps the index")
        // `folio settings` / `folio recent` while a window is open: the window holds the session lock, so the
        // command hands it the edit (SessionRequests.send is the call the command makes) and the window
        // applies it to its own state, saves at once and answers. Nothing is written behind the window.
        let state = root.appendingPathComponent("state")
        try check(store.ownsSession && !restored.ownsSession, "the first window on a state folder owns its session record")
        try check(SessionLock.acquire(in: state) == nil, "a command cannot take the session lock while the window runs")
        store.open(a); store.open(b)
        var edit = SessionEdit(); edit.fontSize = 15; edit.contentWidth = 1000; edit.fontFamily = "mono"; edit.pin = [b.path]
        let sent = edit
        let outcome = try await Task.detached { try SessionRequests.send(sent, state: state, timeout: 5) }.value
        try check(outcome.settingsChanged == ["font_family", "font_size", "content_width"] && outcome.recentChanged.count == 1, "the window answers a command's edit with what changed")
        try check(store.settings.fontSize == 15 && store.settings.contentWidth == 1000 && store.settings.fontFamily == "mono", "the window's own settings follow the command")
        try check(store.recent.first?.pinned == true && store.recent.first?.name == "b.md", "the window's recent list follows the command, pinned first")
        let onDisk = try store.disk.read()
        try check(onDisk.settings.fontSize == 15 && onDisk.recent.first?.pinned == true && onDisk.documents.count == store.documents.count, "the window saved the edit at once, with its tabs")
        var bad = SessionEdit(); bad.fontSize = 99
        let refusedEdit = bad
        let refusal = await Task.detached { Result { try SessionRequests.send(refusedEdit, state: state, timeout: 5) } }.value
        if case .success = refusal { try check(false, "an out-of-range value is refused by the window") }
        try check(store.settings.fontSize == 15, "a refused edit leaves the window's settings alone")
        var step = SessionEdit(); step.fontSizeStep = -1; step.clearRecent = true
        let stepped = step
        let cleared = try await Task.detached { try SessionRequests.send(stepped, state: state, timeout: 5) }.value
        try check(cleared.settings.fontSize == 14 && cleared.cleared > 0 && store.recent.isEmpty && store.settings.fontSize == 14, "font step and clearing the recent list go through the window")
        // A request its sender gave up on long ago is discarded, not applied when the window next looks.
        var late = SessionEdit(); late.fontSize = 26
        let stale = SessionRequests.directory(state).appendingPathComponent("STALE.request.json")
        try JSONEncoder().encode(late).write(to: stale)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-120)], ofItemAtPath: stale.path)
        store.answerRequests()
        try check(store.settings.fontSize == 14 && !FileManager.default.fileExists(atPath: stale.path), "an abandoned request is dropped without being applied")
        try check(((try? FileManager.default.contentsOfDirectory(atPath: SessionRequests.directory(state).path)) ?? []).isEmpty, "answered requests leave nothing behind")
        // `folio tabs close|restore|reload` while a window is open: the tab bar's own actions, with the close
        // dialog's answer brought by the command. Nothing here shows a dialog.
        func tabEdit(_ action: String, _ target: String? = nil, _ decision: String? = nil) -> SessionEdit {
            var edit = SessionEdit(); edit.tab = SessionTabEdit(action: action, target: target, path: target, decision: decision); return edit
        }
        func ask(_ edit: SessionEdit) async -> Result<SessionEditOutcome, Error> {
            await Task.detached { Result { try SessionRequests.send(edit, state: state, timeout: 5) } }.value
        }
        func denial(_ result: Result<SessionEditOutcome, Error>) -> SessionEditError? {
            if case .failure(let error) = result { return error as? SessionEditError }
            return nil
        }
        let tabsBefore = store.documents.count
        let c = root.appendingPathComponent("c.md"); try Data("# C\n".utf8).write(to: c)
        store.open(c); let cid = store.activeID!
        let closedClean = try await ask(tabEdit("close", c.path)).get()
        try check(closedClean.tab?.action == "close" && closedClean.tab?.id == cid && closedClean.tab?.saved == false && closedClean.tab?.keptDraft == false
                  && store.documents.count == tabsBefore && !store.documents.contains { $0.id == cid } && store.recent.first?.name == "c.md",
                  "a command closes a clean tab through the window and the file joins the recent list")
        store.open(c); let cid2 = store.activeID!
        store.changed(id: cid2, text: "# C\n窗口里没保存\n", selection: 0, scroll: 0)
        if case .unsaved? = denial(await ask(tabEdit("close", c.path))) {} else { try check(false, "closing a tab with unsaved edits needs an answer") }
        try check(store.documents.contains { $0.id == cid2 } && store.active?.text == "# C\n窗口里没保存\n", "an unanswered close leaves the tab and its edits")
        if case .invalid? = denial(await ask(tabEdit("close", c.path, "discard"))) {} else { try check(false, "only save and keep-draft answer the close question") }
        let savedClose = try await ask(tabEdit("close", cid2, "save")).get()
        let cOnDisk = try DocumentIO.open(c).text
        try check(savedClose.tab?.saved == true && cOnDisk == "# C\n窗口里没保存\n" && !store.documents.contains { $0.id == cid2 },
                  "close with save writes the file through the window's own save, then closes")
        store.newDocument(); let untitled = store.activeID!
        store.changed(id: untitled, text: "未命名草稿", selection: 0, scroll: 0)
        if case .refused? = denial(await ask(tabEdit("close", untitled, "save"))) {} else { try check(false, "an untitled draft cannot be saved without a name") }
        let draftsBefore = store.closedDrafts.count
        let kept = try await ask(tabEdit("close", untitled, "keep-draft")).get()
        try check(kept.tab?.keptDraft == true && store.closedDrafts.count == draftsBefore + 1 && kept.tab?.closedDrafts == draftsBefore + 1 && !store.documents.contains { $0.id == untitled },
                  "close keeping the draft moves the tab to the closed drafts")
        let back = try await ask(tabEdit("restore")).get()
        let draftsOnDisk = try store.disk.read().closedDrafts?.count
        try check(back.tab?.id == untitled && store.activeID == untitled && store.active?.text == "未命名草稿" && store.closedDrafts.count == draftsBefore
                  && draftsOnDisk == draftsBefore, "restore brings the closed draft back as the current tab and saves")
        store.open(c); let cid3 = store.activeID!
        store.changed(id: cid3, text: "# C\n又一次没保存\n", selection: 0, scroll: 0)
        try Data("# C\n别的软件写的\n".utf8).write(to: c)
        let reloaded = try await ask(tabEdit("reload", c.path)).get()
        try check(reloaded.tab?.draftCopy != nil && store.documents.first { $0.id == cid3 }?.text == "# C\n别的软件写的\n"
                  && store.documents.contains { $0.id == reloaded.tab?.draftCopy && $0.path == nil && $0.text == "# C\n又一次没保存\n" },
                  "reload takes the file from disk and keeps the unsaved edits as a separate draft")
        if case .notFound? = denial(await ask(tabEdit("close", root.appendingPathComponent("never-opened.md").path))) {} else { try check(false, "a tab that is not open is reported as not found") }
        if case .refused? = denial(await ask(tabEdit("reload", untitled))) {} else { try check(false, "an untitled draft has no file to reload") }
        try check(((try? FileManager.default.contentsOfDirectory(atPath: SessionRequests.directory(state).path)) ?? []).isEmpty, "answered tab requests leave nothing behind")

        // `folio config import|sync` while a window is open: the window runs the command itself and then takes
        // the settings the shared layer wrote into session.json, so its next save cannot put the old ones back.
        let wired = root.appendingPathComponent("wired-state")
        var ran: [[String]] = []
        var wiredStore: EditorStore?
        wiredStore = EditorStore(directory: wired, lifecycle: { words in
            ran.append(words)
            // What the shared layer does on an import: rewrites the settings inside session.json, behind the store.
            let file = wired.appendingPathComponent("session.json")
            if var object = (try? JSONSerialization.jsonObject(with: Data(contentsOf: file))) as? [String: Any], var settings = object["settings"] as? [String: Any] {
                settings["fontSize"] = 20; object["settings"] = settings
                try? JSONSerialization.data(withJSONObject: object).write(to: file, options: .atomic)
            }
            return SessionRequests.CommandReply(exit: 3, out: "printed\n", err: "warned\n")
        })
        guard let wiredStore else { return }
        wiredStore.newDocument(); let wiredDraft = wiredStore.activeID!
        wiredStore.changed(id: wiredDraft, text: "窗口里的草稿", selection: 0, scroll: 0)
        wiredStore.settings.fontSize = 17; wiredStore.settingsChanged()
        let answered = try await Task.detached { try SessionRequests.command(["config", "import", "/x.json", "--yes"], state: wired, timeout: 5) }.value
        try check(answered.exit == 3 && answered.out == "printed\n" && answered.err == "warned\n" && ran == [["config", "import", "/x.json", "--yes"]],
                  "the window runs a handed-over configuration command and returns what it printed")
        try check(wiredStore.settings.fontSize == 20, "the window takes the settings the command wrote into session.json")
        wiredStore.changed(id: wiredDraft, text: "窗口里的草稿，继续写", selection: 3, scroll: 0); wiredStore.persist()
        let afterSave = try wiredStore.disk.read()
        try check(afterSave.settings.fontSize == 20 && afterSave.documents.first?.text == "窗口里的草稿，继续写", "the window's next save keeps the imported setting and its own draft")
        // A window without the「配置与更新」wiring (recording, tests) says so; one from before these commands answers
        // the empty edit it can read, which the command recognises.
        let plain = await Task.detached { Result { try SessionRequests.command(["config", "sync", "on", "--yes"], state: state, timeout: 5) } }.value
        if case .failure(SessionEditError.refused) = plain {} else { try check(false, "a window without the lifecycle wiring refuses the command") }
        let nobody = root.appendingPathComponent("nobody-state")
        let began = Date()
        let unanswered = await Task.detached { Result { try SessionRequests.command(["config", "sync", "on", "--yes"], state: nobody, timeout: 30, pickup: 0.3) } }.value
        if case .failure(SessionEditError.noReply) = unanswered {} else { try check(false, "a command nobody takes is withdrawn") }
        try check(Date().timeIntervalSince(began) < 5 && ((try? FileManager.default.contentsOfDirectory(atPath: SessionRequests.directory(nobody).path)) ?? []).isEmpty,
                  "an unclaimed command is withdrawn at the pickup limit, long before the answer timeout")
        let oldReply = SessionRequests.Reply(outcome: SessionEditOutcome(), error: nil)
        let relic = root.appendingPathComponent("relic-state")
        let relicTask = Task.detached { Result { try SessionRequests.command(["config", "sync", "on", "--yes"], state: relic, timeout: 5) } }
        var relicID: String?
        for _ in 0..<200 where relicID == nil {
            relicID = SessionRequests.take(in: relic).first?.id
            if relicID == nil { try await Task.sleep(for: .milliseconds(10)) }
        }
        if let relicID { SessionRequests.answer(relicID, oldReply, state: relic) }
        if case .failure(SessionEditError.outdated) = await relicTask.value {} else { try check(false, "an older window's answer is recognised as outdated") }
        print("PASS a window without the wiring, an unclaimed command and an older window are each told apart")
        // Without a window the command takes the lock itself; a window starting meanwhile waits for it.
        let free = root.appendingPathComponent("free-state")
        let held = SessionLock.acquire(in: free)
        try check(held != nil && SessionLock.acquire(in: free) == nil, "the session lock admits one holder")
        print("Store integration checks passed: \(root.path)")
    }
}
