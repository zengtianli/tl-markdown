import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: MobileStore
    @State private var importSheet = false
    @State private var exportSheet = false
    @State private var exported: OpenDocument?
    @State private var exportFile: MarkdownExport?
    @State private var listSheet = false
    @State private var editorID = UUID().uuidString
    @State private var folderSheet = false
    @State private var folderDocumentID: String?
    @Environment(\.scenePhase) private var phase
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !store.notice.isEmpty {
                    HStack(alignment: .top) {
                        Text(store.notice).font(.callout).textSelection(.enabled)
                        Spacer()
                        Button { store.notice = "" } label: { Image(systemName: "xmark.circle") }.accessibilityLabel("关闭提示")
                    }.padding().background(.yellow.opacity(0.12))
                }
                if let document = store.active {
                    MobileEditor(store: store, document: document, reading: store.reading, editorID: editorID)
                        .id(store.reading)
                        .safeAreaInset(edge: .bottom) {
                            HStack {
                                Text(document.dirty ? "修改已存为本地恢复草稿" : "原文件已保存")
                                Spacer()
                                Text("\(document.text.count) 字")
                            }.font(.caption).foregroundStyle(.secondary).padding(10).background(.bar)
                        }
                } else {
                    ContentUnavailableView {
                        Label("Folio · 文页", systemImage: "doc.richtext")
                    } description: { Text("从“文件”打开 Markdown，阅读、编辑并安全保存。") }
                    actions: {
                        Button("打开 Markdown") { importSheet = true }.buttonStyle(.borderedProminent)
                        Button("新建文稿") { Task { await store.newDocument(editorID: editorID) } }
                    }
                }
            }
            .navigationTitle(store.active?.title ?? "Folio · 文页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { listSheet = true } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel("文稿与恢复草稿")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("打开 Markdown", systemImage: "folder") { importSheet = true }
                        Button("新建文稿", systemImage: "square.and.pencil") { Task { await store.newDocument(editorID: editorID) } }
                        if store.active != nil {
                            Button(store.reading ? "编辑文稿" : "阅读文稿", systemImage: store.reading ? "pencil" : "book") {
                                Task { do { try await store.flush(editorID: editorID); store.reading.toggle() } catch { store.notice = error.localizedDescription } }
                            }
                            if !store.reading { Toggle("显示 Markdown 源码", isOn: $store.sourceMode) }
                            Button("保存原文件", systemImage: "square.and.arrow.down") { Task { await store.save(editorID: editorID) } }
                                .disabled(store.active?.path == nil)
                            Button("另存为…", systemImage: "square.and.arrow.up") { prepareExport() }
                            Button("授权图片目录…", systemImage: "folder.badge.plus") { folderDocumentID = store.activeID; folderSheet = true }
                                .disabled(store.active?.path == nil)
                            Button("重新载入并保留当前草稿", systemImage: "arrow.clockwise") {
                                Task { do { try await store.flush(editorID: editorID); store.perform { try store.workspace.reloadPreservingDraft() } } catch { store.notice = error.localizedDescription } }
                            }.disabled(store.active?.path == nil)
                        }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("文稿操作")
                }
            }
        }
        .fileImporter(isPresented: $importSheet, allowedContentTypes: [.folioMarkdown, .plainText], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { Task { await store.open(url, editorID: editorID) } }
            case .failure(let error): store.notice = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $folderSheet, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let folder = urls.first, let id = folderDocumentID {
                    store.perform { try store.workspace.authorizeAssetFolder(folder, id: id); store.notice = "图片目录已授权，可读取相对图片及插入到 assets；正文保存仍使用独立文件授权。" }
                }
            case .failure(let error): store.notice = error.localizedDescription
            }
            folderDocumentID = nil
        }
        .fileExporter(isPresented: $exportSheet, document: exportFile, contentType: .folioMarkdown,
                      defaultFilename: store.active?.title == "未命名" ? "文稿.md" : store.active?.title) { result in
            switch result {
            case .success(let url):
                if let exported { store.perform { try store.workspace.finishExport(exported, destination: url) } }
            case .failure(let error): store.notice = error.localizedDescription
            }
            exported = nil; exportFile = nil
        }
        .sheet(isPresented: $listSheet) {
            NavigationStack {
                List(store.documents) { document in
                    Button { Task { await store.select(document.id, editorID: editorID); listSheet = false } } label: {
                        VStack(alignment: .leading) {
                            Label(document.title, systemImage: document.dirty ? "pencil.circle" : "doc.text")
                            if document.dirty { Text("有本地恢复草稿").font(.caption).foregroundStyle(.secondary) }
                            if !document.message.isEmpty { Text(document.message).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                .navigationTitle("文稿与恢复草稿")
                .toolbar { Button("完成") { listSheet = false } }
            }
        }
        .onAppear { if store.active == nil { LaneSignal.ready("welcome") } }
        .onOpenURL { url in Task { await store.open(url, editorID: editorID) } }
        .onChange(of: phase) { _, value in
            if value != .active { Task { try? await store.flush(editorID: editorID) } }
        }
    }
    private func prepareExport() {
        Task {
            do {
                try await store.flush(editorID: editorID)
                guard let document = store.active else { return }
                exported = document; exportFile = MarkdownExport(document: document); exportSheet = true
            } catch { store.notice = error.localizedDescription }
        }
    }
}
