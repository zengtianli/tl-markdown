import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let folioMarkdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}
struct MarkdownExport: FileDocument {
    static var readableContentTypes: [UTType] { [.folioMarkdown, .plainText] }
    let data: Data
    init(document: OpenDocument) { data = DocumentIO.encoded(document) }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw DocumentError.encoding }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
