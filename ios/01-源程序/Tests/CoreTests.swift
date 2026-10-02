import Foundation
import Darwin

@main enum CoreTests {
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw NSError(domain: "FolioMobileTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("folio-mobile-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("合成 文稿.md")
        let bytes = Data("\u{FEFF}# Synthetic\r\n\r\n测试文稿\r\n".utf8)
        try bytes.write(to: original)
        let state = root.appendingPathComponent("state")
        let workspace = try DocumentWorkspace(directory: state)
        let id = try workspace.open(original)
        try check(workspace.active?.text == "# Synthetic\n\n测试文稿\n", "read BOM/CRLF")
        try workspace.update(id: id, text: "# Edited\n中文\n", selection: 4, scroll: 10)
        try check(Data(contentsOf: original) == bytes, "editing must leave original byte-for-byte intact")
        let recovered = try DocumentWorkspace(directory: state)
        try check(recovered.active?.text == "# Edited\n中文\n" && recovered.active?.dirty == true, "crash recovery draft")
        try recovered.save()
        try check(Data(contentsOf: original) == Data("\u{FEFF}# Edited\r\n中文\r\n".utf8), "save BOM/CRLF unchanged")
        try recovered.update(id: id, text: "my unsaved draft", selection: 0, scroll: 0)
        let external = Data("# External edit\n".utf8)
        try external.write(to: original, options: .atomic)
        do { try recovered.save(); throw NSError(domain: "unexpected-success", code: 1) }
        catch DocumentError.conflict { }
        try check(Data(contentsOf: original) == external, "conflict may never overwrite external edits")
        try check(recovered.active?.text == "my unsaved draft", "conflict keeps draft")
        try recovered.reloadPreservingDraft()
        try check(recovered.active?.text == "# External edit\n", "reload real disk")
        try check(recovered.snapshot.documents.contains { $0.path == nil && $0.text == "my unsaved draft" }, "reload preserves separate draft")
        // Files export succeeds for a frozen snapshot while subsequent edits stay dirty.
        let exportID = try recovered.newDocument(text: "exported snapshot")
        let frozen = recovered.active!
        let destination = root.appendingPathComponent("export.md")
        try DocumentIO.encoded(frozen).write(to: destination)
        try recovered.update(id: exportID, text: "new edit during export", selection: 0, scroll: 0)
        try recovered.finishExport(frozen, destination: destination)
        try check(recovered.active?.savedText == "exported snapshot" && recovered.active?.text == "new edit during export" && recovered.active?.dirty == true, "export preserves editing race")
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: destination.path)
        do { try recovered.save(); throw NSError(domain: "unexpected-success", code: 4) }
        catch DocumentError.readOnly { }
        try check(Data(contentsOf: destination) == Data("exported snapshot".utf8), "read-only save preserves source")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        let invalid = root.appendingPathComponent("invalid.md")
        let invalidBytes = Data([0xff, 0xfe, 0x00]); try invalidBytes.write(to: invalid)
        do { try recovered.open(invalid); throw NSError(domain: "unexpected-success", code: 2) }
        catch DocumentError.encoding { }
        try check(Data(contentsOf: invalid) == invalidBytes, "invalid encoding never mutated")
        let corrupt = root.appendingPathComponent("corrupt"); try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
        let corruptFile = corrupt.appendingPathComponent("session.json"); let bad = Data("broken-json".utf8); try bad.write(to: corruptFile)
        do { _ = try DocumentWorkspace(directory: corrupt); throw NSError(domain: "unexpected-success", code: 3) }
        catch DocumentError.state { }
        try check(Data(contentsOf: corruptFile) == bad, "corrupt recovery source preserved")
        // Two live editors and delayed frames share one workspace/writer.
        let multiFile = root.appendingPathComponent("multi.md"); try Data("initial".utf8).write(to: multiFile)
        let multi = try DocumentWorkspace(directory: root.appendingPathComponent("multi-state"))
        let multiID = try multi.open(multiFile)
        let a = try multi.bindEditor(owner: "A", id: multiID)
        let b = try multi.bindEditor(owner: "B", id: multiID)
        _ = try multi.applyEditor(owner: "A", generation: a.generation, id: multiID, text: "A first", selection: 1, scroll: 0)
        _ = try multi.applyEditor(owner: "A", generation: a.generation, id: multiID, text: "A latest", selection: 2, scroll: 0)
        try check(multi.active?.revision == 2, "accepted text edits increment revision without rejecting rapid same-editor frames")
        do { _ = try multi.applyEditor(owner: "B", generation: b.generation, id: multiID, text: "initial", selection: 0, scroll: 0); throw NSError(domain: "unexpected-success", code: 5) }
        catch DocumentError.state { }
        try check(multi.snapshot.documents.count == 1 && multi.active?.text == "A latest", "B's unchanged stale flush cannot undo A or create fake draft")
        do { _ = try multi.applyEditor(owner: "B", generation: b.generation, id: multiID, text: "B concurrent", selection: 0, scroll: 0); throw NSError(domain: "unexpected-success", code: 6) }
        catch DocumentError.state { }
        try check(multi.active?.text == "A latest" && multi.snapshot.documents.contains { $0.path == nil && $0.text == "B concurrent" }, "concurrent B edit preserved independently")
        let synced = try multi.bindEditor(owner: "B", id: multiID)
        do { _ = try multi.applyEditor(owner: "B", generation: b.generation, id: multiID, text: "B delayed old frame", selection: 0, scroll: 0); throw NSError(domain: "unexpected-success", code: 7) }
        catch DocumentError.state { }
        try check(multi.active?.text == "A latest" && multi.snapshot.documents.contains { $0.text == "B delayed old frame" }, "queued old-generation frame cannot overwrite synchronized document")
        try multi.save(id: multiID)
        try check(Data(contentsOf: multiFile) == Data("A latest".utf8), "A save writes A latest despite B stale flushes")
        _ = try multi.applyEditor(owner: "B", generation: synced.generation, id: multiID, text: "B current version", selection: 0, scroll: 0)
        let multiRecovered = try DocumentWorkspace(directory: multi.disk.directory)
        try check(multiRecovered.active?.text == "B current version" && multiRecovered.snapshot.documents.contains { $0.text == "B concurrent" }, "accepted and rejected concurrent texts survive recovery")
        let registry = EditorFlushRegistry(); var aFlush = 0; var bFlush = 0
        registry.register(scene: "A", token: "oldA") { aFlush += 1 }
        registry.register(scene: "B", token: "B") { bFlush += 1 }
        try await registry.flush(scene: "A")
        try check(aFlush == 1 && bFlush == 0, "A operation must never flush the last-registered B editor")
        registry.register(scene: "A", token: "newA") { aFlush += 10 }
        registry.remove(scene: "A", token: "oldA"); try await registry.flush(scene: "A")
        try check(aFlush == 11 && bFlush == 0, "old view teardown cannot unregister replacement editor")
        // A single-file grant never grants siblings. Core tests model the grant
        // boundary; actual Files provider permission remains a native UI check.
        do { _ = try multi.storeImage(id: multiID, data: Data([1, 2, 3]), extension: "png"); throw NSError(domain: "unexpected-success", code: 8) }
        catch DocumentError.state { }
        try check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("assets").path), "ungranted directory receives no image write")
        let wrongFolder = root.appendingPathComponent("wrong"); try FileManager.default.createDirectory(at: wrongFolder, withIntermediateDirectories: true)
        do { try multi.authorizeAssetFolder(wrongFolder, id: multiID); throw NSError(domain: "unexpected-success", code: 9) }
        catch DocumentError.state { }
        try multi.authorizeAssetFolder(root, id: multiID)
        let image = try multi.storeImage(id: multiID, data: Data([1, 2, 3]), extension: "png")
        try check(try multi.readImage(id: multiID, relative: "assets/" + image.url.lastPathComponent) == Data([1, 2, 3]), "explicit folder grant enables bounded original image adapter")
        let folderRecovered = try DocumentWorkspace(directory: multi.disk.directory)
        try check(try folderRecovered.readImage(id: multiID, relative: "assets/" + image.url.lastPathComponent) == Data([1, 2, 3]), "folder bookmark survives recovery")
        // Deterministic real disk races execute inside the same production FD
        // reader. Checkpoints do not replace any open/read/stat result.
        let outsideFolder = root.deletingLastPathComponent().appendingPathComponent("folio-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outsideFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideFolder) }
        let outsideBytes = Data("PRIVATE OUTSIDE GRANT".utf8)
        let outsideImage = outsideFolder.appendingPathComponent(image.url.lastPathComponent)
        try outsideBytes.write(to: outsideImage)
        let assetsFolder = root.appendingPathComponent("assets")
        let retainedAssets = root.appendingPathComponent("assets-retained")
        var replacedParent = false
        let anchored = try multi.readImage(id: multiID, relative: "assets/" + image.url.lastPathComponent) { point in
            if case .parentOpened = point, !replacedParent {
                try FileManager.default.moveItem(at: assetsFolder, to: retainedAssets)
                try FileManager.default.createSymbolicLink(at: assetsFolder, withDestinationURL: outsideFolder)
                replacedParent = true
            }
        }
        try check(replacedParent && anchored == Data([1, 2, 3]) && anchored != outsideBytes, "parent replaced after directory open cannot redirect leaf read outside grant")
        var parentLinkRefused = false
        do { _ = try multi.readImage(id: multiID, relative: "assets/" + image.url.lastPathComponent) }
        catch { parentLinkRefused = true }
        try check(parentLinkRefused, "already-replaced parent symlink is rejected without reading outside")
        try FileManager.default.removeItem(at: assetsFolder)
        try FileManager.default.moveItem(at: retainedAssets, to: assetsFolder)
        let linkedLeaf = assetsFolder.appendingPathComponent("linked-leaf.png")
        try FileManager.default.createSymbolicLink(at: linkedLeaf, withDestinationURL: outsideImage)
        var leafLinkRefused = false
        do { _ = try multi.readImage(id: multiID, relative: "assets/linked-leaf.png") }
        catch { leafLinkRefused = true }
        try check(leafLinkRefused, "leaf symlink cannot expose bytes outside directory grant")
        let swappedLeaf = assetsFolder.appendingPathComponent("swap-leaf.png")
        let retainedLeaf = assetsFolder.appendingPathComponent("retained-leaf.png")
        try Data([7, 8, 9]).write(to: swappedLeaf)
        var replacedLeaf = false; var replacedLeafRefused = false
        do {
            _ = try multi.readImage(id: multiID, relative: "assets/swap-leaf.png") { point in
                if case .parentOpened = point, !replacedLeaf {
                    try FileManager.default.moveItem(at: swappedLeaf, to: retainedLeaf)
                    try FileManager.default.createSymbolicLink(at: swappedLeaf, withDestinationURL: outsideImage)
                    replacedLeaf = true
                }
            }
        } catch { replacedLeafRefused = true }
        try check(replacedLeaf && replacedLeafRefused && Data(contentsOf: outsideImage) == outsideBytes, "leaf replaced after parent open is rejected without exposing outside bytes")
        let fifo = assetsFolder.appendingPathComponent("not-regular.png")
        try check(mkfifo(fifo.path, mode_t(0o600)) == 0, "synthetic FIFO created")
        do { _ = try multi.readImage(id: multiID, relative: "assets/not-regular.png"); throw NSError(domain: "unexpected-success", code: 13) }
        catch DocumentError.encoding { }
        let growing = assetsFolder.appendingPathComponent("growing.png")
        let stableBytes = Data(repeating: 0x41, count: 128 * 1024)
        try stableBytes.write(to: growing)
        var grewWithinLimit = false
        do {
            _ = try multi.readImage(id: multiID, relative: "assets/growing.png") { point in
                if case .chunkRead = point, !grewWithinLimit {
                    let handle = try FileHandle(forWritingTo: growing); defer { try? handle.close() }
                    try handle.truncate(atOffset: UInt64(stableBytes.count + 16 * 1024)); grewWithinLimit = true
                }
            }
            throw NSError(domain: "unexpected-success", code: 14)
        } catch DocumentError.state { }
        try check(grewWithinLimit, "real file growth below limit must be rejected by FD metadata check")
        try stableBytes.write(to: growing, options: .atomic)
        var grewPastLimit = false
        do {
            _ = try multi.readImage(id: multiID, relative: "assets/growing.png") { point in
                if case .chunkRead = point, !grewPastLimit {
                    let handle = try FileHandle(forWritingTo: growing); defer { try? handle.close() }
                    try handle.truncate(atOffset: UInt64(DocumentIO.imageByteLimit + 1)); grewPastLimit = true
                }
            }
            throw NSError(domain: "unexpected-success", code: 15)
        } catch DocumentError.imageTooLarge { }
        try check(grewPastLimit, "real sparse-file growth past limit is rejected immediately after first bounded chunk")
        let boundary = assetsFolder.appendingPathComponent("at-limit.png")
        try Data().write(to: boundary)
        let boundaryHandle = try FileHandle(forWritingTo: boundary)
        try boundaryHandle.truncate(atOffset: UInt64(DocumentIO.imageByteLimit)); try boundaryHandle.close()
        do { _ = try multi.readImage(id: multiID, relative: "assets/at-limit.png"); throw NSError(domain: "unexpected-success", code: 16) }
        catch DocumentError.imageTooLarge { }
        let grantedFolder = root.appendingPathComponent("selected-folder")
        let movedGrant = root.appendingPathComponent("selected-folder-retained")
        try FileManager.default.createDirectory(at: grantedFolder, withIntermediateDirectories: true)
        let grantedDocument = grantedFolder.appendingPathComponent("doc.md"); try Data("source".utf8).write(to: grantedDocument)
        let grantWorkspace = try DocumentWorkspace(directory: root.appendingPathComponent("selected-folder-state"))
        let grantID = try grantWorkspace.open(grantedDocument); try grantWorkspace.authorizeAssetFolder(grantedFolder, id: grantID)
        try FileManager.default.moveItem(at: grantedFolder, to: movedGrant)
        try FileManager.default.createSymbolicLink(at: grantedFolder, withDestinationURL: outsideFolder)
        do { _ = try grantWorkspace.readImage(id: grantID, relative: image.url.lastPathComponent); throw NSError(domain: "unexpected-success", code: 17) }
        catch DocumentError.state { }
        try check(Data(contentsOf: outsideImage) == outsideBytes, "grant root substitution neither reads nor mutates outside source")
        do { _ = try multi.readImage(id: multiID, relative: "../wrong/outside.png"); throw NSError(domain: "unexpected-success", code: 10) }
        catch DocumentError.missing { }
        try FileManager.default.removeItem(at: root.appendingPathComponent("assets"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("assets"), withDestinationURL: wrongFolder)
        do { _ = try multi.storeImage(id: multiID, data: Data([9]), extension: "png"); throw NSError(domain: "unexpected-success", code: 11) }
        catch DocumentError.state { }
        try check(try FileManager.default.contentsOfDirectory(atPath: wrongFolder.path).isEmpty, "symlink assets cannot write outside authorized source directory")
        // Permission metadata corruption is independent from valid draft recovery.
        let corruptBookmarks = multi.disk.directory.appendingPathComponent("bookmarks.json")
        let badPermissions = Data("damaged-permissions".utf8); try badPermissions.write(to: corruptBookmarks)
        let sessionBefore = try Data(contentsOf: multi.disk.file)
        let permissionRecovered = try DocumentWorkspace(directory: multi.disk.directory)
        try check(permissionRecovered.active?.text == "B current version" && !permissionRecovered.permissionNotice.isEmpty, "bad bookmarks must not hide valid session draft in Rescue")
        try check(Data(contentsOf: multi.disk.file) == sessionBefore && Data(contentsOf: corruptBookmarks) == badPermissions, "permission downgrade never rewrites source records on load")
        try permissionRecovered.update(id: multiID, text: "continue after permission damage", selection: 0, scroll: 0)
        do { try permissionRecovered.save(); throw NSError(domain: "unexpected-success", code: 12) }
        catch DocumentError.state { }
        let rescueExport = root.appendingPathComponent("rescued.md"); let rescued = permissionRecovered.active!
        try DocumentIO.encoded(rescued).write(to: rescueExport)
        try permissionRecovered.finishExport(rescued, destination: rescueExport)
        try check(permissionRecovered.active?.text == "continue after permission damage" && Data(contentsOf: multiFile) == Data("A latest".utf8), "reauthorized save-as retains recovered edits and leaves original alone")
        let backups = try FileManager.default.contentsOfDirectory(at: multi.disk.directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("bookmarks.json.unreadable-") }
        try check(backups.count == 1 && Data(contentsOf: backups[0]) == badPermissions, "explicit replacement preserves unreadable original metadata")
        #if os(macOS)
        let systemAliasRoot = URL(fileURLWithPath: "/tmp/folio-os-alias-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: systemAliasRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: systemAliasRoot) }
        let aliasDoc = systemAliasRoot.appendingPathComponent("alias.md"); try Data("alias source".utf8).write(to: aliasDoc)
        let aliasWorkspace = try DocumentWorkspace(directory: root.appendingPathComponent("alias-state"))
        let aliasID = try aliasWorkspace.open(aliasDoc); try aliasWorkspace.authorizeAssetFolder(systemAliasRoot, id: aliasID)
        let aliasImage = try aliasWorkspace.storeImage(id: aliasID, data: Data([4, 5, 6]), extension: "png")
        try check(try aliasWorkspace.readImage(id: aliasID, relative: "assets/" + aliasImage.url.lastPathComponent) == Data([4, 5, 6]), "legitimate /tmp alias permits secure FD read/write")
        try check(DocumentWorkspace.canonicalSystemURL(URL(fileURLWithPath: "/var")).path == "/private/var", "trusted system /var alias normalized")
        let canonicalVarRoot = DocumentWorkspace.canonicalSystemURL(root)
        if canonicalVarRoot.path.hasPrefix("/private/var/") {
            let varAlias = URL(fileURLWithPath: "/var" + String(canonicalVarRoot.path.dropFirst("/private/var".count)))
            try multi.authorizeAssetFolder(varAlias, id: multiID)
            // The prior synthetic assets symlink is still rejected after OS alias
            // normalization; legitimate system aliases do not relax user links.
            var varUserLinkRefused = false
            do { _ = try multi.readImage(id: multiID, relative: "assets/" + image.url.lastPathComponent) }
            catch { varUserLinkRefused = true }
            try check(varUserLinkRefused, "system /var support does not follow user assets symlink")
        }
        let userAlias = systemAliasRoot.appendingPathComponent("user-alias")
        try FileManager.default.createSymbolicLink(at: userAlias, withDestinationURL: systemAliasRoot)
        do { try aliasWorkspace.authorizeAssetFolder(userAlias, id: aliasID); throw NSError(domain: "unexpected-success", code: 18) }
        catch DocumentError.state { }
        #endif
        print("PASS: shared production encoding, explicit save, crash recovery, conflict, reload draft preservation, invalid input, corrupt state")
        print("PASS: two-editor ownership/generation/revision, per-scene flush, folder grant boundaries, damaged-bookmark draft recovery and safe save-as")
        print("PASS: FD image read parent replacement, leaf/root symlink rejection, FIFO rejection, in-flight growth and strict size cap")
        print("PASS: legitimate root-owned OS aliases with user-symlink refusal intact")
    }
}
