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
        print("Store integration checks passed: \(root.path)")
    }
}
