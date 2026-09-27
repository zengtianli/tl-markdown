import Foundation
import AppKit

private struct RecoveryFailure: Error { let message: String }

@main struct RecoveryAcceptance {
    @MainActor static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw RecoveryFailure(message: message) }
        print("PASS \(message)")
    }

    // Load through production DocumentIO without touching the system's recent-documents list.
    @MainActor static func attach(_ url: URL, to store: EditorStore) throws -> String {
        let document = try DocumentIO.open(url)
        store.documents.append(document)
        store.activeID = document.id
        return document.id
    }

    @MainActor static func run(_ root: URL) async throws {
        let fm = FileManager.default
        let source = root.appendingPathComponent("conflict.md")
        let local = "本地未保存的修改😀\n"
        let external = "来自外部编辑器的修改\n"
        try Data("原始文件\n".utf8).write(to: source)
        let state = root.appendingPathComponent("conflict-state")
        let store = EditorStore(directory: state)
        let id = try attach(source, to: store)
        store.changed(id: id, text: local, selection: 4, scroll: 20)
        try Data(external.utf8).write(to: source)
        store.checkExternalChanges()
        try await Task.sleep(for: .milliseconds(950))
        try require(store.active?.conflict == true && store.active?.text == local,
                    "external conflict preserves dirty local content")
        let diskAfterAutosave = try Data(contentsOf: source)
        try require(diskAfterAutosave == Data(external.utf8), "scheduled autosave does not overwrite external changes")
        let snapshot = try store.disk.read()
        try require(snapshot.documents.contains { $0.id == id && $0.text == local && $0.conflict },
                    "blocked autosave persists recoverable conflict draft")

        store.reload()
        try require(store.active?.text == external && store.active?.conflict == false,
                    "reload adopts external file and clears conflict")
        try require(store.documents.contains { $0.path == nil && $0.text == local && $0.dirty },
                    "reload preserves local content in a separate unsaved draft")
        store.persist()
        let restarted = EditorStore(directory: state)
        try require(restarted.documents.contains { $0.path == nil && $0.text == local && $0.dirty },
                    "fresh store restores reload backup from persisted session")
        try require(restarted.documents.first { $0.id == id }?.text == external,
                    "fresh store reloads saved document from real disk")

        // The persisted closed-draft queue is the same one produced by the close dialog.
        // Its modal decision requires user input and is intentionally not exercised here.
        let closedState = root.appendingPathComponent("closed-state")
        var closed = try DocumentIO.open(source)
        closed.text = "已关闭但保留的草稿\n"
        let closedID = closed.id
        try SessionDisk(directory: closedState).write(SessionSnapshot(closedDrafts: [closed]))
        let closedStore = EditorStore(directory: closedState)
        _ = try attach(source, to: closedStore)
        closedStore.restoreClosedDraft()
        try require(closedStore.active?.id == closedID && closedStore.active?.text == closed.text,
                    "persisted closed draft restores original content")
        try require(closedStore.active?.path == nil && closedStore.active?.dirty == true && closedStore.closedDrafts.isEmpty,
                    "restoring draft detaches duplicate open path and consumes recovery queue")
        let closedRestart = EditorStore(directory: closedState)
        try require(closedRestart.documents.contains { $0.id == closedID && $0.text == closed.text },
                    "restored closed draft survives another store restart")
        let cleanID = closedStore.documents.first { $0.path != nil }!.id
        closedStore.close(cleanID)
        try require(!closedStore.documents.contains { $0.id == cleanID } && fm.fileExists(atPath: source.path),
                    "noninteractive clean close leaves file and recovered dirty draft intact")

        let readOnlyURL = root.appendingPathComponent("read-only.md")
        let original = Data("只读原文\n".utf8)
        try original.write(to: readOnlyURL)
        let readOnlyStore = EditorStore(directory: root.appendingPathComponent("read-only-state"))
        let readOnlyID = try attach(readOnlyURL, to: readOnlyStore)
        readOnlyStore.changed(id: readOnlyID, text: "保存失败仍需保留\n", selection: 0, scroll: 0)
        try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: readOnlyURL.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: readOnlyURL.path) }
        let saved = readOnlyStore.save(id: readOnlyID, automatic: true)
        let readOnlyDisk = try Data(contentsOf: readOnlyURL)
        try require(!saved && readOnlyDisk == original, "read-only save fails without changing original bytes")
        try require(readOnlyStore.active?.dirty == true && readOnlyStore.active?.message.contains("只读") == true,
                    "read-only save failure keeps draft and actionable error")
        let readOnlyRestart = EditorStore(directory: readOnlyStore.disk.directory)
        try require(readOnlyRestart.active?.text == "保存失败仍需保留\n" && readOnlyRestart.active?.dirty == true,
                    "failed save draft is recoverable from persisted session")

        let corruptState = root.appendingPathComponent("corrupt-state")
        try fm.createDirectory(at: corruptState, withIntermediateDirectories: true)
        let corruptBytes = Data("{broken recovery data".utf8)
        try corruptBytes.write(to: corruptState.appendingPathComponent("session.json"))
        let corruptStore = EditorStore(directory: corruptState)
        let backups = try fm.contentsOfDirectory(at: corruptState, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("session-unreadable-") }
        try require(backups.count == 1, "corrupt session is retained as a recovery backup")
        let backupBytes = try Data(contentsOf: backups[0])
        try require(backupBytes == corruptBytes && corruptStore.banner.contains("已保留原记录"),
                    "corrupt session bytes remain intact and user receives recovery message")
        corruptStore.newDocument()
        corruptStore.changed(id: corruptStore.activeID!, text: "损坏会话后的新草稿\n", selection: 2, scroll: 0)
        corruptStore.persist()
        let afterCorruptRestart = EditorStore(directory: corruptState)
        try require(afterCorruptRestart.active?.text == "损坏会话后的新草稿\n",
                    "new drafts persist and restore after corrupt session recovery")

        let blockedState = root.appendingPathComponent("blocked-state")
        try Data("not a directory".utf8).write(to: blockedState)
        let failedStore = EditorStore(directory: blockedState)
        failedStore.newDocument()
        failedStore.changed(id: failedStore.activeID!, text: "持久化失败时的内存草稿", selection: 0, scroll: 0)
        failedStore.persist()
        try require(failedStore.active?.text == "持久化失败时的内存草稿" && failedStore.banner.contains("未能写入磁盘"),
                    "session write failure preserves memory content and reports failure")
    }

    @MainActor static func main() async {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        do {
            guard CommandLine.arguments.count == 2 else { throw RecoveryFailure(message: "missing isolated work directory") }
            try await run(URL(fileURLWithPath: CommandLine.arguments[1]))
            print("PASS recovery acceptance: production store and document I/O; synthetic isolated files; no GUI input")
        } catch let failure as RecoveryFailure {
            fputs("FAIL recovery: \(failure.message)\n", stderr)
            exit(1)
        } catch {
            // No private absolute paths or file contents enter publicly retained evidence.
            fputs("FAIL recovery: unexpected fixture or production I/O error\n", stderr)
            exit(1)
        }
    }
}
