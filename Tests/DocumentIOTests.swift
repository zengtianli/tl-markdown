import Foundation

@main struct DocumentIOTests {
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw NSError(domain: "DocumentIOTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        print("PASS \(message)")
    }
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("中文.md")
        let original = "\u{FEFF}# 标题\r\n\r\n**中文** 😀\r\n未知 <custom>标记</custom>\r\n"
        try Data(original.utf8).write(to: file)
        var doc = try DocumentIO.open(file)
        try check(doc.bom && doc.lineEnding == "\r\n", "BOM / CRLF detection")
        try DocumentIO.save(&doc)
        try check(Data(contentsOf: file) == Data(original.utf8), "unmodified file exact bytes")
        doc.text += "新增段落\n"; try DocumentIO.save(&doc)
        try check(Data(contentsOf: file) == Data((original + "新增段落\r\n").utf8), "edited file retains BOM and CRLF")
        let expected = doc.text; try check(DocumentIO.open(file).text == expected, "save and reopen Chinese / emoji")
        doc.text += "本地修改\n"
        try Data("外部修改".utf8).write(to: file)
        var rejected = false
        do { try DocumentIO.save(&doc) } catch DocumentError.conflict { rejected = true }
        try check(rejected && doc.text.hasSuffix("本地修改\n"), "concurrent edit detected; local text retained")
        try check(String(contentsOf: file, encoding: .utf8) == "外部修改", "conflicting external bytes not overwritten")
        let copy = root.appendingPathComponent("另存为.md"); try DocumentIO.save(&doc, to: copy)
        try check(DocumentIO.open(copy).text == doc.text, "Save As preserves local branch")
        let moved = root.appendingPathComponent("moved.md"); try FileManager.default.moveItem(at: copy, to: moved)
        doc.text += "下一次修改"; rejected = false
        do { try DocumentIO.save(&doc) } catch DocumentError.missing { rejected = true }
        try check(rejected && !FileManager.default.fileExists(atPath: copy.path), "deleted original is not recreated")
        var readOnly = try DocumentIO.open(moved); readOnly.text += "不可写"
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: moved.path)
        rejected = false; do { try DocumentIO.save(&readOnly) } catch DocumentError.readOnly { rejected = true }
        try check(rejected, "read-only file save rejected")
        let disk = SessionDisk(directory: root.appendingPathComponent("state"))
        let recent = RecentFile(path: file.path, pinned: true, scroll: 480, selection: 12)
        doc.scroll = 480; doc.selection = 12
        try disk.write(SessionSnapshot(documents: [doc], activeID: doc.id, recent: [recent]))
        let restored = try disk.read()
        try check(restored.documents.first?.text == doc.text && restored.documents.first?.scroll == 480, "crash snapshot restores draft and position")
        try check(restored.recent.first?.pinned == true && restored.activeID == doc.id, "recent pin and active tab persisted")
        let attr = try FileManager.default.attributesOfItem(atPath: disk.file.path)
        try check((attr[.posixPermissions] as? NSNumber)?.intValue == 0o600, "snapshot permissions are private")
        try Data("not-json".utf8).write(to: disk.file); rejected = false
        do { _ = try disk.read() } catch { rejected = true }
        try check(rejected && String(contentsOf: disk.file, encoding: .utf8) == "not-json", "corrupt snapshot fails without overwriting evidence")
        var imageDoc = try DocumentIO.open(file)
        let image = try DocumentIO.imageDestination(document: imageDoc, folder: "assets", extension: "png")
        try check(image.deletingLastPathComponent().lastPathComponent == "assets", "relative image folder")
        rejected = false; do { _ = try DocumentIO.imageDestination(document: imageDoc, folder: "../outside", extension: "png") } catch { rejected = true }
        try check(rejected, "image folder traversal rejected")
        let symlink = root.appendingPathComponent("link.md"); try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: file)
        imageDoc = try DocumentIO.open(symlink); imageDoc.text += "编辑软链目标"; try DocumentIO.save(&imageDoc)
        try check(DocumentIO.open(file).text == imageDoc.text, "symlink opens and saves the actual target")
        print("All production I/O tests passed. Artifacts: \(root.path)")
    }
}
