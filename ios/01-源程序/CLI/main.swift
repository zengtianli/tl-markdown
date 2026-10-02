import Foundation
import Darwin

let help = """
folio-mobile --state <isolated-directory> inspect|import <file>|new <text>|write <text>|save|export <new-file>|reload
Development CLI: same DocumentWorkspace and original Folio DocumentIO/SessionDisk.
Never point --state at a running app's state. inspect is read-only; mutations are explicit.
Exit: 0 success, 1 operation failed, 2 invalid usage. Output: JSON.
"""
var args = Array(CommandLine.arguments.dropFirst())
if args == ["--help"] || args.isEmpty { print(help); exit(0) }
guard args.count >= 3, args.removeFirst() == "--state" else { fputs(help + "\n", stderr); exit(2) }
let state = URL(fileURLWithPath: args.removeFirst(), isDirectory: true)
let command = args.removeFirst()
let arities = ["inspect": 0, "import": 1, "new": 1, "write": 1, "save": 0, "export": 1, "reload": 0]
guard arities[command] == args.count else { fputs(help + "\n", stderr); exit(2) }
do {
    let workspace = try DocumentWorkspace(directory: state)
    switch command {
    case "inspect": break
    case "import": try workspace.open(URL(fileURLWithPath: args[0]))
    case "new": try workspace.newDocument(text: args[0])
    case "write":
        guard args.count == 1, let doc = workspace.active else { throw DocumentError.missing }
        try workspace.update(id: doc.id, text: args[0], selection: 0, scroll: 0)
    case "save": try workspace.save()
    case "reload": try workspace.reloadPreservingDraft()
    case "export":
        guard args.count == 1, let doc = workspace.active else { throw DocumentError.missing }
        let target = URL(fileURLWithPath: args[0])
        guard !FileManager.default.fileExists(atPath: target.path) else { throw CocoaError(.fileWriteFileExists) }
        // Creation is exclusive: the CLI never overwrites an existing export destination.
        let descriptor = Darwin.open(target.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
        guard descriptor >= 0 else { throw CocoaError(.fileWriteFileExists) }
        Darwin.close(descriptor)
        var output = doc
        output.path = target.standardizedFileURL.resolvingSymlinksInPath().path
        output.diskData = Data(); output.savedText = ""
        try DocumentIO.save(&output)
        try workspace.finishExport(doc, destination: target)
    default: fputs(help + "\n", stderr); exit(2)
    }
    let result: [String: Any] = ["ok": true, "command": command, "documents": workspace.snapshot.documents.count,
                               "active": workspace.active.map { ["id": $0.id, "title": $0.title, "dirty": $0.dirty] as [String: Any] } ?? [:]]
    print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
} catch {
    let result: [String: Any] = ["ok": false, "error": error.localizedDescription]
    print(String(decoding: try! JSONSerialization.data(withJSONObject: result), as: UTF8.self)); exit(1)
}
