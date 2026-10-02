import Foundation
import Darwin

/// Mobile permission adapter. Markdown encoding, conflict detection, atomic saving and
/// recovery serialization remain the original Folio Models.swift implementations.
enum ScopedDocumentAccess {
    static func withAccess<T>(_ url: URL, _ body: (URL) throws -> T) rethrows -> T {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }
    static func read(_ url: URL) throws -> OpenDocument {
        try withAccess(url) { scoped in
            var result: Result<OpenDocument, Error>?
            var error: NSError?
            NSFileCoordinator().coordinate(readingItemAt: scoped, options: [], error: &error) { target in
                result = Result {
                    let bytes = try target.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard bytes <= 5_000_000 else {
                        throw DocumentError.state("文档超过移动端 5 MB 编辑上限；原文未改动")
                    }
                    return try DocumentIO.open(target)
                }
            }
            if let error { throw error }
            guard let result else { throw DocumentError.missing }
            return try result.get()
        }
    }
}

/// Shared store operations flush the initiating scene's editor only. Token checks
/// prevent a discarded view from unregistering its replacement.
@MainActor final class EditorFlushRegistry {
    private var entries: [String: (token: String, flush: () async throws -> Void)] = [:]
    func register(scene: String, token: String, flush: @escaping () async throws -> Void) { entries[scene] = (token, flush) }
    func remove(scene: String, token: String) {
        if entries[scene]?.token == token { entries.removeValue(forKey: scene) }
    }
    func flush(scene: String) async throws { try await entries[scene]?.flush() }
}

final class DocumentWorkspace {
    let disk: SessionDisk
    private(set) var snapshot: SessionSnapshot
    private var bookmarks: [String: Data]
    private var folderBookmarks: [String: Data] = [:]
    private var liveURLs: [String: URL] = [:]
    private var liveFolders: [String: URL] = [:]
    private var damagedPermissionFiles: [URL] = []
    private(set) var permissionNotice = ""
    struct EditorLease { let generation: String, documentID: String; var revision: Int; var text: String }
    private var editorLeases: [String: EditorLease] = [:]
    private var rejectedText: [String: String] = [:]
    private var bookmarkFile: URL { disk.directory.appendingPathComponent("bookmarks.json") }
    private var folderFile: URL { disk.directory.appendingPathComponent("asset-folders.json") }

    init(directory: URL) throws {
        disk = SessionDisk(directory: directory)
        snapshot = try disk.read()
        let file = directory.appendingPathComponent("bookmarks.json")
        if FileManager.default.fileExists(atPath: file.path) {
            do { bookmarks = try JSONDecoder().decode([String: Data].self, from: Data(contentsOf: file)) }
            catch {
                bookmarks = [:]; damagedPermissionFiles.append(file)
                permissionNotice = "文件授权记录损坏；有效草稿已恢复，可继续编辑或另存为。保存原件请重新从 Files 打开同一文件。"
            }
        } else { bookmarks = [:] }
        if FileManager.default.fileExists(atPath: folderFile.path) {
            do { folderBookmarks = try JSONDecoder().decode([String: Data].self, from: Data(contentsOf: folderFile)) }
            catch {
                damagedPermissionFiles.append(folderFile)
                permissionNotice += " 图片目录授权记录损坏，请重新选择文稿所在目录。"
            }
        }
    }
    var active: OpenDocument? { snapshot.documents.first { $0.id == snapshot.activeID } }
    func persist() throws { try disk.write(snapshot) }
    private func persistBookmarks() throws {
        try FileManager.default.createDirectory(at: disk.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // A later explicit reauthorization may replace metadata, but never destroys
        // the unreadable original record or the independently valid session.
        for file in damagedPermissionFiles {
            let backup = disk.directory.appendingPathComponent(file.lastPathComponent + ".unreadable-" + UUID().uuidString)
            try Data(contentsOf: file).write(to: backup, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        damagedPermissionFiles.removeAll()
        try JSONEncoder().encode(bookmarks).write(to: bookmarkFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: bookmarkFile.path)
        try JSONEncoder().encode(folderBookmarks).write(to: folderFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: folderFile.path)
    }
    private func remember(_ url: URL, id: String) throws {
        bookmarks[id] = try ScopedDocumentAccess.withAccess(url) {
            try $0.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        liveURLs[id] = url
        try persistBookmarks()
    }
    func url(for id: String) throws -> URL {
        if let url = liveURLs[id] { return url }
        guard let data = bookmarks[id] else { throw DocumentError.state("原文件需重新授权；草稿保留，可另存为或从 Files 重新打开同一文件。") }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
        liveURLs[id] = url
        if stale { try remember(url, id: id) }
        return url
    }
    @discardableResult func open(_ url: URL) throws -> String {
        let document = try ScopedDocumentAccess.read(url)
        if let old = snapshot.documents.first(where: { $0.path == document.path }) {
            try remember(url, id: old.id)
            snapshot.activeID = old.id
            try persist()
            return old.id // Never overwrite an existing unsaved draft when reopening Files.
        }
        try remember(url, id: document.id)
        snapshot.documents.append(document)
        snapshot.activeID = document.id
        try persist()
        return document.id
    }
    @discardableResult func newDocument(text: String = "") throws -> String {
        let document = OpenDocument(text: text)
        snapshot.documents.append(document); snapshot.activeID = document.id
        try persist(); return document.id
    }
    func select(_ id: String) throws {
        guard snapshot.documents.contains(where: { $0.id == id }) else { throw DocumentError.missing }
        snapshot.activeID = id; try persist()
    }
    func update(id: String, text: String, selection: Int, scroll: Double) throws {
        guard let index = snapshot.documents.firstIndex(where: { $0.id == id }) else { throw DocumentError.missing }
        if snapshot.documents[index].text != text { snapshot.documents[index].revision += 1 }
        snapshot.documents[index].text = text
        snapshot.documents[index].selection = max(0, selection)
        snapshot.documents[index].scroll = max(0, scroll)
        // One atomic local recovery write for every received editor change. No timer,
        // source autosave, polling, server or private document in the app bundle.
        try persist()
    }
    func bindEditor(owner: String, id: String) throws -> EditorLease {
        guard let doc = snapshot.documents.first(where: { $0.id == id }) else { throw DocumentError.missing }
        let lease = EditorLease(generation: UUID().uuidString, documentID: id, revision: doc.revision, text: doc.text)
        editorLeases[owner] = lease; return lease
    }
    func releaseEditor(owner: String) { editorLeases.removeValue(forKey: owner); rejectedText.removeValue(forKey: owner) }
    func applyEditor(owner: String, generation: String, id: String, text: String, selection: Int, scroll: Double) throws -> Int {
        guard var lease = editorLeases[owner], let index = snapshot.documents.firstIndex(where: { $0.id == id }) else { throw DocumentError.missing }
        let current = snapshot.documents[index]
        guard lease.generation == generation, lease.documentID == id, lease.revision == current.revision else {
            if text != current.text, text != lease.text, rejectedText[owner] != text {
                var draft = current; draft.id = UUID().uuidString; draft.path = nil; draft.diskData = nil
                draft.savedText = ""; draft.text = text; draft.selection = max(0, selection); draft.scroll = max(0, scroll)
                draft.revision = 0; draft.conflict = false; draft.message = "另一窗口的并发编辑已保留为独立恢复草稿"
                snapshot.documents.append(draft); rejectedText[owner] = text; try persist()
            }
            throw DocumentError.state("此编辑器的版本已过期，未覆盖新文稿；如有并发修改，已保留在文稿列表的独立恢复草稿。")
        }
        try update(id: id, text: text, selection: selection, scroll: scroll)
        lease.revision = snapshot.documents[index].revision; lease.text = text; editorLeases[owner] = lease
        return lease.revision
    }
    func authorizeAssetFolder(_ folder: URL, id: String) throws {
        guard let doc = snapshot.documents.first(where: { $0.id == id }), let path = doc.path else { throw DocumentError.state("未命名草稿请先另存为，再选择所在目录。") }
        try ScopedDocumentAccess.withAccess(folder) { root in
            let canonical = Self.canonicalSystemURL(root)
            let facts = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard facts.isDirectory == true, facts.isSymbolicLink != true,
                  canonical.path == Self.canonicalSystemURL(root.resolvingSymlinksInPath()).path,
                  canonical.path == Self.canonicalSystemURL(URL(fileURLWithPath: path).deletingLastPathComponent()).path else {
                throw DocumentError.state("请选择当前文稿所在的目录；不会使用其他目录读写附件。")
            }
            folderBookmarks[id] = try root.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            liveFolders[id] = root; try persistBookmarks()
        }
    }
    private func withAssetFolder<T>(id: String, _ body: (URL, OpenDocument) throws -> T) throws -> T {
        guard let doc = snapshot.documents.first(where: { $0.id == id }), let path = doc.path else { throw DocumentError.missing }
        let folder: URL
        if let live = liveFolders[id] { folder = live }
        else {
            guard let bookmark = folderBookmarks[id] else { throw DocumentError.state("图片目录未授权；正文仍可编辑保存。请在菜单选择“授权图片目录…”。") }
            var stale = false
            folder = try URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale { throw DocumentError.state("图片目录授权已失效，请重新选择目录；正文草稿保留。") }
            liveFolders[id] = folder
        }
        return try ScopedDocumentAccess.withAccess(folder) { root in
            let canonical = Self.canonicalSystemURL(root)
            // DocumentIO stored the physical path when the file was opened. Do
            // not resolve that baseline again: a replaced selected folder must
            // not redefine the original grant by making both paths follow a link.
            guard canonical.path == Self.canonicalSystemURL(root.resolvingSymlinksInPath()).path,
                  canonical.path == Self.canonicalSystemURL(URL(fileURLWithPath: path).deletingLastPathComponent()).path else { throw DocumentError.state("文稿位置已变，请重新授权图片目录。") }
            return try body(canonical, doc)
        }
    }
    enum ImageReadCheckpoint { case parentOpened, chunkRead }
    /// Optional checkpoints observe the actual production FD path. They allow
    /// deterministic real filesystem races without an alternate reader in tests.
    func readImage(id: String, relative: String, checkpoint: ((ImageReadCheckpoint) throws -> Void)? = nil) throws -> Data {
        let parts = relative.split(separator: "/").map(String.init)
        guard !relative.hasPrefix("/"), !relative.contains("\0"), relative.utf8.count <= 4096,
              !parts.isEmpty, parts.count <= 128, !parts.contains(".."),
              DocumentIO.isImageFile(URL(fileURLWithPath: parts.last!)) else { throw DocumentError.missing }
        return try withAssetFolder(id: id) { root, _ in
            var parentFD = try Self.openDirectoryWithoutLinks(root)
            defer { if parentFD >= 0 { Darwin.close(parentFD) } }
            for part in parts.dropLast() {
                let next = openat(parentFD, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                let failure = errno; Darwin.close(parentFD); parentFD = next
                guard next >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure)) }
            }
            try checkpoint?(.parentOpened)
            // Nonblocking prevents a FIFO substituted for an image from hanging
            // before fstat can reject it. No leaf or parent symlink is followed.
            let fileFD = openat(parentFD, parts.last!, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard fileFD >= 0 else { throw Self.posixError() }
            defer { Darwin.close(fileFD) }
            var before = stat()
            guard fstat(fileFD, &before) == 0 else { throw Self.posixError() }
            guard (before.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { throw DocumentError.encoding }
            guard before.st_size >= 0, before.st_size < Int64(DocumentIO.imageByteLimit) else { throw DocumentError.imageTooLarge }
            var bytes = Data(); bytes.reserveCapacity(Int(before.st_size))
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while bytes.count < DocumentIO.imageByteLimit {
                let wanted = min(buffer.count, DocumentIO.imageByteLimit - bytes.count)
                let received = buffer.withUnsafeMutableBytes { Darwin.read(fileFD, $0.baseAddress!, wanted) }
                if received < 0 && errno == EINTR { continue }
                guard received >= 0 else { throw Self.posixError() }
                if received == 0 { break }
                bytes.append(contentsOf: buffer.prefix(received))
                try checkpoint?(.chunkRead)
                try Self.verifyImageUnchanged(fileFD, before: before)
            }
            guard bytes.count < DocumentIO.imageByteLimit else { throw DocumentError.imageTooLarge }
            try Self.verifyImageUnchanged(fileFD, before: before)
            guard Int64(bytes.count) == before.st_size else { throw DocumentError.state("图片在读取时发生变化，未显示不完整内容。") }
            return bytes
        }
    }
    private static func verifyImageUnchanged(_ descriptor: Int32, before: stat) throws {
        var after = stat()
        guard fstat(descriptor, &after) == 0 else { throw posixError() }
        guard after.st_size >= 0, after.st_size < Int64(DocumentIO.imageByteLimit) else { throw DocumentError.imageTooLarge }
        guard before.st_dev == after.st_dev, before.st_ino == after.st_ino, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else {
            throw DocumentError.state("图片在读取时发生变化，未显示不完整内容。")
        }
    }
    func storeImage(id: String, data: Data, extension ext: String) throws -> (url: URL, markdown: String) {
        try withAssetFolder(id: id) { root, doc in
            guard !ext.isEmpty, ext.utf8.count <= 12, ext.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }),
                  DocumentIO.isImageFile(URL(fileURLWithPath: "image." + ext)) else { throw DocumentError.imageType }
            // Keep the original Foundation image limit, naming and Markdown algorithm.
            // Only the permission adapter publishes its result to the selected folder.
            let staging = disk.directory.appendingPathComponent("image-staging", isDirectory: true)
            if FileManager.default.fileExists(atPath: staging.path) { try FileManager.default.removeItem(at: staging) }
            defer { try? FileManager.default.removeItem(at: staging) }
            var privateDocument = doc; privateDocument.path = staging.appendingPathComponent("staging.md").path
            let staged = try DocumentIO.storeImage(data, extension: ext, document: privateDocument, folder: "assets")
            let rootFD = try Self.openDirectoryWithoutLinks(root)
            defer { Darwin.close(rootFD) }
            if mkdirat(rootFD, "assets", mode_t(0o700)) != 0 && errno != EEXIST { throw Self.posixError() }
            let assetsFD = openat(rootFD, "assets", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard assetsFD >= 0 else { throw DocumentError.state("assets 必须是授权目录内的真实目录，不能是符号链接。") }
            defer { Darwin.close(assetsFD) }
            let name = staged.url.lastPathComponent
            let fileFD = openat(assetsFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
            guard fileFD >= 0 else { throw Self.posixError() }
            var complete = false
            defer { Darwin.close(fileFD); if !complete { unlinkat(assetsFD, name, 0) } }
            try data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let written = Darwin.write(fileFD, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                    if written < 0 && errno == EINTR { continue }
                    guard written > 0 else { throw Self.posixError() }
                    offset += written
                }
            }
            guard fsync(fileFD) == 0 else { throw Self.posixError() }
            complete = true
            return (root.appendingPathComponent("assets").appendingPathComponent(name), staged.markdown)
        }
    }
    private static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    /// Foundation can strip /private when standardizing valid temporary URLs.
    /// Match PhotoDesk's narrow rule: only exact, root-owned OS aliases with their
    /// expected targets are normalized; no selected/user symlink is resolved.
    static func canonicalSystemURL(_ url: URL) -> URL {
        guard url.isFileURL else { return url }
        let normalized = url.standardizedFileURL
        for (alias, target) in [("/var", "/private/var"), ("/tmp", "/private/tmp"), ("/etc", "/private/etc")] {
            guard normalized.path == alias || normalized.path.hasPrefix(alias + "/") else { continue }
            var info = stat()
            guard lstat(alias, &info) == 0, info.st_uid == 0,
                  (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK),
                  let link = try? FileManager.default.destinationOfSymbolicLink(atPath: alias),
                  link == target || link == String(target.dropFirst()) else { return normalized }
            return URL(fileURLWithPath: target + String(normalized.path.dropFirst(alias.count)))
        }
        return normalized
    }
    private static func openDirectoryWithoutLinks(_ url: URL) throws -> Int32 {
        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError() }
        for part in canonicalSystemURL(url).path.split(separator: "/") {
            let next = openat(descriptor, String(part), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            let failure = errno; Darwin.close(descriptor)
            guard next >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure)) }
            descriptor = next
        }
        return descriptor
    }
    func save(id requestedID: String? = nil) throws {
        guard let id = requestedID ?? snapshot.activeID, let index = snapshot.documents.firstIndex(where: { $0.id == id }) else { throw DocumentError.missing }
        let destination = try url(for: id)
        var document = snapshot.documents[index]
        document.path = destination.standardizedFileURL.resolvingSymlinksInPath().path
        do {
            try ScopedDocumentAccess.withAccess(destination) { _ in try DocumentIO.save(&document) }
            snapshot.documents[index] = document
            try persist()
        } catch {
            snapshot.documents[index].message = error.localizedDescription
            if case DocumentError.conflict = error { snapshot.documents[index].conflict = true }
            try? persist()
            throw error
        }
    }
    /// Export uses a frozen snapshot: editing during the Files sheet must remain dirty.
    func finishExport(_ exported: OpenDocument, destination: URL) throws {
        let saved = try ScopedDocumentAccess.read(destination)
        guard saved.diskData == DocumentIO.encoded(exported),
              let index = snapshot.documents.firstIndex(where: { $0.id == exported.id }) else { throw DocumentError.conflict }
        try remember(destination, id: exported.id)
        snapshot.documents[index].path = saved.path
        snapshot.documents[index].diskData = saved.diskData
        snapshot.documents[index].savedText = exported.text
        snapshot.documents[index].conflict = false
        snapshot.documents[index].message = ""
        try persist()
    }
    func reloadPreservingDraft() throws {
        guard let old = active, let index = snapshot.documents.firstIndex(where: { $0.id == old.id }) else { throw DocumentError.missing }
        var diskDocument = try ScopedDocumentAccess.read(url(for: old.id))
        if old.dirty {
            var draft = old; draft.id = UUID().uuidString; draft.path = nil
            draft.diskData = nil; draft.savedText = ""; draft.conflict = false
            draft.message = "重新载入前保留的草稿"
            snapshot.documents.append(draft)
        }
        diskDocument.id = old.id; diskDocument.revision = old.revision + 1
        snapshot.documents[index] = diskDocument
        try persist()
    }
}
