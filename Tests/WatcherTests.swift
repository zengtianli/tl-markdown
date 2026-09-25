import Foundation
import AppKit

/// External-change watching through the production EditorStore, without any explicit
/// checkExternalChanges() call: every change below must arrive through file-system events.
/// Each wait is capped well under the former 2 s poll interval.
@main struct WatcherTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        setvbuf(stdout, nil, _IOLBF, 0)
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("笔记 a.md"), moved = folder.appendingPathComponent("moved.md")
        try Data("# A\n原文\n".utf8).write(to: file)
        let store = EditorStore(directory: root.appendingPathComponent("state"))
        func check(_ ok: @autoclosure () -> Bool, _ name: String) throws {
            if !ok() { throw NSError(domain: "WatcherTests", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }; print("PASS \(name)")
        }
        func expect(_ name: String, within ms: Int = 1200, _ condition: () -> Bool) async throws {
            for _ in 0..<(ms / 50) { if condition() { break }; try await Task.sleep(for: .milliseconds(50)) }
            try check(condition(), name)
        }
        func openDescriptors() -> Int { (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? -1 }
        func write(_ text: String, atomic: Bool = false) throws { try Data(text.utf8).write(to: file, options: atomic ? .atomic : []) }
        store.open(file); let id = store.activeID!
        var doc: OpenDocument? { store.documents.first { $0.id == id } }
        let path = file.standardizedFileURL.resolvingSymlinksInPath().path
        try check(store.watcher?.watchedFiles == [path] && store.watcher?.polledFiles.isEmpty == true, "open local file is watched by an event source, not polled")

        try write("就地写入\n")
        try await expect("in-place external write reloads") { doc?.text == "就地写入\n" }
        try write("原子保存\n", atomic: true)
        try await expect("atomic save (file replaced by rename) reloads") { doc?.text == "原子保存\n" }
        try write("原子保存后就地写入\n")
        try await expect("the replacement file is watched again after an atomic save") { doc?.text == "原子保存后就地写入\n" }

        try FileManager.default.moveItem(at: file, to: moved)
        try await expect("moving the file away marks the document missing") { doc?.conflict == true }
        try FileManager.default.moveItem(at: moved, to: file)
        try await expect("moving it back clears the missing state without reloading") { doc?.conflict == false && doc?.message == "" && doc?.text == "原子保存后就地写入\n" }
        try write("移回后就地写入\n")
        try await expect("the moved-back file is watched again") { doc?.text == "移回后就地写入\n" }

        try FileManager.default.removeItem(at: file)
        try await expect("deleting the file marks the document missing") { doc?.conflict == true }
        try write("删除后重建\n")
        try await expect("a file recreated after deletion is reloaded") { doc?.text == "删除后重建\n" && doc?.conflict == false }
        try write("重建后就地写入\n")
        try await expect("the recreated file is watched again") { doc?.text == "重建后就地写入\n" }

        store.changed(id: id, text: "本地自动保存\n", selection: 3, scroll: 0)
        try await expect("Folio's own autosave reaches disk") { (try? String(contentsOf: file, encoding: .utf8)) == "本地自动保存\n" }
        try await Task.sleep(for: .milliseconds(400))
        try check(doc?.conflict == false && doc?.message == "" && doc?.text == "本地自动保存\n", "Folio's own atomic save is not reported as an external change")
        try write("自保存后外部修改\n")
        try await expect("external edits are still seen after Folio's own save") { doc?.text == "自保存后外部修改\n" }

        store.changed(id: id, text: "未保存的本地修改\n", selection: 3, scroll: 0)
        try write("磁盘上的冲突版本\n")
        try await expect("an external edit to a dirty document is flagged as a conflict") { doc?.conflict == true }
        try await Task.sleep(for: .milliseconds(900))
        try check(doc?.text == "未保存的本地修改\n" && (try? String(contentsOf: file, encoding: .utf8)) == "磁盘上的冲突版本\n", "the local draft and the disk version are both kept")
        store.reload()
        try check(doc?.text == "磁盘上的冲突版本\n" && store.documents.contains { $0.path == nil && $0.text == "未保存的本地修改\n" }, "reload keeps the local draft as a separate document")

        store.close(id)
        try await expect("closing the document releases its file source") { store.watcher?.watchedFiles.isEmpty == true }

        // Parent folder renamed away and back: polling only while it is gone, then events again.
        let outer = root.appendingPathComponent("外层 folder"), inner = outer
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        let nested = inner.appendingPathComponent("嵌套.md")
        try Data("嵌套原文\n".utf8).write(to: nested)
        // Resolved after the file exists: Foundation only strips /private for existing paths.
        let nestedPath = nested.standardizedFileURL.resolvingSymlinksInPath().path
        store.open(nested); let nid = store.activeID!
        var ndoc: OpenDocument? { store.documents.first { $0.id == nid } }
        guard let watcher = store.watcher else { throw NSError(domain: "WatcherTests", code: 2) }
        try check(watcher.watchedFiles == [nestedPath] && !watcher.polling, "nested document starts on events")
        try await Task.sleep(for: .milliseconds(200))  // cancelled sources close their descriptors on the main queue
        let descriptors = openDescriptors()
        let away = root.appendingPathComponent("外层 moved")
        try FileManager.default.moveItem(at: outer, to: away)
        try await expect("renaming the parent folder marks the document missing") { ndoc?.conflict == true }
        try check(watcher.polledFiles == [nestedPath] && watcher.polling, "a missing folder falls back to polling")
        try check(watcher.watchedFiles.isEmpty, "the moved-away inode's file source is released")
        try FileManager.default.moveItem(at: away, to: outer)
        try await expect("restoring the folder returns to event watching and stops the poll", within: 3000) {
            watcher.watchedFiles == [nestedPath] && watcher.polledFiles.isEmpty && !watcher.polling && ndoc?.conflict == false
        }
        try check(ndoc?.message == "" && ndoc?.text == "嵌套原文\n", "restored folder clears the missing state without reloading")
        try Data("恢复后就地写入\n".utf8).write(to: nested)
        try await expect("in-place writes after the restore arrive through events (poll is off)") { ndoc?.text == "恢复后就地写入\n" }
        try check(openDescriptors() == descriptors, "no descriptors left behind by the folder round trip (\(descriptors) → \(openDescriptors()))")

        // Parent folder deleted, then recreated with a new file: the new inodes are watched.
        try FileManager.default.removeItem(at: outer)
        try await expect("deleting the parent folder marks the document missing") { ndoc?.conflict == true && watcher.polling }
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try Data("重建的文件夹\n".utf8).write(to: nested)
        try await expect("a recreated folder and file are reloaded and watched by events", within: 3000) {
            ndoc?.text == "重建的文件夹\n" && ndoc?.conflict == false && !watcher.polling && watcher.watchedFiles == [nestedPath]
        }
        try Data("重建后就地写入\n".utf8).write(to: nested)
        try await expect("the file source follows the new inode") { ndoc?.text == "重建后就地写入\n" }
        try check(openDescriptors() == descriptors, "old folder and file sources are released (\(descriptors) → \(openDescriptors()))")

        // A renamed grandparent is invisible to kqueue; activating the app re-checks the paths.
        let grand = root.appendingPathComponent("祖父"), parent = grand.appendingPathComponent("父")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let deep = parent.appendingPathComponent("深层.md")
        try Data("深层\n".utf8).write(to: deep)
        let deepPath = deep.standardizedFileURL.resolvingSymlinksInPath().path
        store.open(deep); let gid = store.activeID!
        var gdoc: OpenDocument? { store.documents.first { $0.id == gid } }
        let grandAway = root.appendingPathComponent("祖父 moved")
        try FileManager.default.moveItem(at: grand, to: grandAway)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try await expect("after a grandparent rename, activation marks the document missing and polls") {
            gdoc?.conflict == true && watcher.polledFiles.contains(deepPath) && !watcher.watchedFiles.contains(deepPath)
        }
        try FileManager.default.moveItem(at: grandAway, to: grand)
        try await expect("restoring the grandparent returns to events", within: 3000) {
            gdoc?.conflict == false && watcher.watchedFiles.contains(deepPath) && !watcher.polling
        }
        store.close(gid)
        try await Task.sleep(for: .milliseconds(200))
        try check(openDescriptors() == descriptors, "closing the deep document releases its sources (\(descriptors) → \(openDescriptors()))")
        store.select(nid)

        // Conflict resolved by undoing the external edit: blocked edits autosave without a keystroke.
        store.changed(id: nid, text: "冲突期间的本地修改\n", selection: 0, scroll: 0)
        try Data("外部冲突\n".utf8).write(to: nested)
        try await expect("dirty document + external edit is a conflict") { ndoc?.conflict == true }
        try await Task.sleep(for: .milliseconds(900))
        try check((try? String(contentsOf: nested, encoding: .utf8)) == "外部冲突\n", "autosave is held back during the conflict")
        try Data("重建后就地写入\n".utf8).write(to: nested)
        try await expect("undoing the external edit resolves the conflict and saves the held edit", within: 2000) {
            ndoc?.conflict == false && (try? String(contentsOf: nested, encoding: .utf8)) == "冲突期间的本地修改\n"
        }
        try check(ndoc?.message == "" && ndoc?.dirty == false, "the conflict message is cleared once saved")

        // A restored draft keeps its note when a conflict resolves, and still waits for review.
        let draftState = root.appendingPathComponent("draft-state"), draftFile = folder.appendingPathComponent("草稿.md")
        try Data("草稿基线\n".utf8).write(to: draftFile)
        do {
            let first = EditorStore(directory: draftState)
            first.open(draftFile); let did = first.activeID!
            first.changed(id: did, text: "未保存的草稿\n", selection: 0, scroll: 0)
            try Data("另一个软件改过\n".utf8).write(to: draftFile)
            try await expect("first session sees the conflict") { first.documents.first?.conflict == true }
            first.persist()
        }
        let second = EditorStore(directory: draftState)
        var rdoc: OpenDocument? { second.documents.first }
        try check(rdoc?.conflict == true && rdoc?.message == "已恢复上次未保存的草稿", "restored draft is flagged as conflicting")
        try Data("草稿基线\n".utf8).write(to: draftFile)
        try await expect("reverting the file resolves the restored draft's conflict") { rdoc?.conflict == false }
        try await Task.sleep(for: .milliseconds(900))
        try check(rdoc?.message == "已恢复上次未保存的草稿" && rdoc?.text == "未保存的草稿\n", "only conflict messages are cleared; the restored-draft note stays")
        try check((try? String(contentsOf: draftFile, encoding: .utf8)) == "草稿基线\n", "a restored draft is not autosaved before it is reviewed (same as at launch)")

        // Watchers and stores release every descriptor when they go away.
        store.close(nid)  // (the restored draft stays open: closing a dirty document asks the user)
        try await Task.sleep(for: .milliseconds(300))
        let before = openDescriptors()
        for n in 0..<60 {
            let watcher = ExternalChangeWatcher {}
            watcher.update([file.path, draftFile.path, folder.appendingPathComponent("missing \(n).md").path])
            if n == 0 { try check(watcher.sourceCount == 3, "a watcher holds one source per existing file plus the folder") }
        }
        for _ in 0..<20 {
            let transient = EditorStore(directory: root.appendingPathComponent("transient"))
            transient.open(file); transient.open(draftFile)
        }
        try await Task.sleep(for: .milliseconds(300))
        try check(openDescriptors() == before, "80 watchers created and released leak no descriptors (\(before) → \(openDescriptors()))")
        print("Watcher checks passed: \(root.path)")
    }
}
