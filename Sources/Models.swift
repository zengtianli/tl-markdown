import Foundation

struct RecentFile: Codable, Identifiable {
    var path: String
    var opened: Date = Date()
    var pinned = false
    var scroll: Double = 0
    var selection = 0
    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}
struct EditorSettings: Codable {
    var fontFamily: String? = "system"
    var fontSize: Double = 17
    var contentWidth: Double = 820
    var restoreSession = true
    var imageFolder = "assets"
}
struct OpenDocument: Codable, Identifiable {
    var id = UUID().uuidString
    var path: String?
    var text = ""
    var savedText = ""
    var diskData: Data?
    var lineEnding = "\n"
    var bom = false
    var scroll: Double = 0
    var selection = 0
    var revision = 0
    var conflict = false
    var message = ""
    var title: String { path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "未命名" }
    var dirty: Bool { text != savedText || (path == nil && !text.isEmpty) }
}
struct SessionSnapshot: Codable {
    var documents: [OpenDocument] = []
    var activeID: String?
    var recent: [RecentFile] = []
    var settings = EditorSettings()
    var closedDrafts: [OpenDocument]? = []
}
enum DocumentError: LocalizedError {
    case conflict, missing, encoding, readOnly, imageFolder, state(String)
    var errorDescription: String? {
        switch self {
        case .conflict: return "文件已被其他软件修改。你的修改已保留，请选择重新载入或另存为。"
        case .missing: return "原文件已移动或删除。你的修改已保留，请另存为。"
        case .encoding: return "文件不是 UTF-8 文本，暂不支持直接编辑；原文件未改动。"
        case .readOnly: return "文件为只读或不可写。你的修改已保留，请另存为。"
        case .imageFolder: return "图片目录必须是文档旁的相对目录，不能包含 .. 或绝对路径。"
        case .state(let detail): return "恢复记录无法读取：\(detail)；原记录已保留。"
        }
    }
}

/// App and tests use this exact implementation; no alternate test-only save path.
struct DocumentIO {
    static func open(_ url: URL) throws -> OpenDocument {
        let real = url.standardizedFileURL.resolvingSymlinksInPath()
        let data = try Data(contentsOf: real)
        guard var text = String(data: data, encoding: .utf8), !text.contains("\0") else { throw DocumentError.encoding }
        let bom = data.starts(with: [0xEF, 0xBB, 0xBF])
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let ending = text.contains("\r\n") ? "\r\n" : (text.contains("\r") ? "\r" : "\n")
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return OpenDocument(path: real.path, text: text, savedText: text, diskData: data, lineEnding: ending, bom: bom)
    }
    static func encoded(_ document: OpenDocument) -> Data {
        Data(((document.bom ? "\u{FEFF}" : "") + document.text.replacingOccurrences(of: "\n", with: document.lineEnding)).utf8)
    }
    static func save(_ document: inout OpenDocument, to destination: URL? = nil) throws {
        guard let url = destination ?? document.path.map({ URL(fileURLWithPath: $0) }) else { throw DocumentError.missing }
        let real = url.standardizedFileURL.resolvingSymlinksInPath()
        let fm = FileManager.default
        let same = real.path == document.path
        if same {
            guard fm.fileExists(atPath: real.path) else { throw DocumentError.missing }
            guard try Data(contentsOf: real) == document.diskData else { throw DocumentError.conflict }
            if document.text == document.savedText { return }
        }
        if fm.fileExists(atPath: real.path) {
            let attributes = try fm.attributesOfItem(atPath: real.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
            guard fm.isWritableFile(atPath: real.path), permissions & 0o222 != 0 else { throw DocumentError.readOnly }
        }
        let data = encoded(document)
        let baseline = document.diskData
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: real, options: [], error: &coordinationError) { target in
            do {
                if same, try Data(contentsOf: target) != baseline { throw DocumentError.conflict }
                try data.write(to: target, options: .atomic)
            } catch { writeError = error }
        }
        if let error = coordinationError { throw error }
        if let error = writeError { throw error }
        document.path = real.path; document.diskData = data; document.savedText = document.text
        document.conflict = false; document.message = ""
    }
    static func imageDestination(document: OpenDocument, folder: String, extension ext: String) throws -> URL {
        guard let path = document.path else { throw DocumentError.missing }
        guard !folder.isEmpty, !folder.hasPrefix("/"), !folder.split(separator: "/").contains("..") else { throw DocumentError.imageFolder }
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("image-\(UUID().uuidString.prefix(12)).\(ext)")
    }
}
final class SessionDisk {
    let directory: URL
    let file: URL
    init(directory: URL) { self.directory = directory; file = directory.appendingPathComponent("session.json") }
    func read() throws -> SessionSnapshot {
        guard FileManager.default.fileExists(atPath: file.path) else { return SessionSnapshot() }
        do { return try JSONDecoder().decode(SessionSnapshot.self, from: Data(contentsOf: file)) }
        catch { throw DocumentError.state(error.localizedDescription) }
    }
    func write(_ snapshot: SessionSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

/// User-facing name comes from project.yaml through the built Info.plist.
enum ProductIdentity {
    static var name: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ProcessInfo.processInfo.processName }
}
