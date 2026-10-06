import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name { static let folioSearchNotes = Notification.Name("FolioSearchNotes") }

struct ContentView: View {
    @ObservedObject var store: EditorStore
    var body: some View {
        HStack(spacing: 0) {
            if store.sidebar { sidebar.frame(width: 238); Divider() }
            VStack(spacing: 0) {
                if !store.documents.isEmpty { tabs; Divider() }
                if !store.banner.isEmpty {
                    HStack { Image(systemName: "info.circle"); Text(store.banner).font(.callout); Spacer(); Button { store.banner = "" } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                        .padding(10).background(Color.accentColor.opacity(0.08))
                }
                if let doc = store.active, !doc.message.isEmpty {
                    HStack {
                        Image(systemName: doc.conflict ? "exclamationmark.triangle" : "info.circle")
                        Text(doc.message).font(.callout)
                        Spacer()
                        if doc.path != nil { Button("重新载入") { store.reload() } }
                        Button("另存为") { store.save(saveAs: true) }
                    }.padding(10).background(Color.orange.opacity(0.1))
                }
                ZStack {
                    EditorSurface(bridge: store.bridge).opacity(store.active == nil ? 0 : 1)
                    if store.active == nil { welcome }
                }
                Divider()
                HStack(spacing: 14) {
                    if let doc = store.active {
                        Image(systemName: doc.conflict ? "exclamationmark.circle" : (doc.dirty ? "circle.fill" : "checkmark.circle"))
                        Text(doc.conflict ? "需要处理文件冲突" : doc.path == nil ? "本地草稿" : doc.dirty ? (doc.message.isEmpty ? "正在保存…" : "保存未完成") : "已保存")
                        Spacer()
                        Text("\(doc.text.count.formatted()) 字符")
                        Text(store.sourceMode ? "Markdown 源码" : "即时渲染")
                    } else { Text("本地文件 · 离线读写"); Spacer() }
                }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 30)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(minWidth: 760, minHeight: 520)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { store.sidebar.toggle() } label: { Image(systemName: "sidebar.left") }.help("显示或隐藏侧栏")
                Button { store.openPanel() } label: { Image(systemName: "folder") }.help("打开文件 ⌘O")
                Button { store.newDocument() } label: { Image(systemName: "square.and.pencil") }.help("新建 ⌘N")
            }
            ToolbarItem(placement: .principal) { Text(store.active?.title ?? ProductIdentity.name).font(.headline).lineLimit(1) }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { store.command("find") } label: { Image(systemName: "magnifyingglass") }.disabled(store.active == nil).help("搜索与替换 ⌘F")
                Button { store.toggleSource() } label: { Label(store.sourceMode ? "即时渲染" : "源码", systemImage: store.sourceMode ? "doc.richtext" : "chevron.left.forwardslash.chevron.right") }.disabled(store.active == nil)
                Button {
                    store.bridge.flush()
                    if let doc = store.active { FullPreview.shared.show(doc, settings: store.settings) }
                } label: { Image(systemName: "doc.text.magnifyingglass") }.help("完整预览：表格、图片、公式和图表；关闭后释放").disabled(store.active == nil)
                Button { store.showSettings = true } label: { Image(systemName: "slider.horizontal.3") }.help("阅读与编辑设置")
            }
        }
        .sheet(isPresented: $store.showSettings) { FolioSettingsView(store: store) }
        .onReceive(store.$documents) { FullPreview.shared.update(documents: $0) }
        .onReceive(NotificationCenter.default.publisher(for: .folioSearchNotes)) { _ in
            store.sidebar = true; store.sidebarTab = 2; store.notes.focusRequest += 1
        }
        .onAppear { store.notes.indexPath = noteIndexURL; store.notes.reloadIndex(); store.indexSettings.useDatabase(noteIndexURL) }
        .onChange(of: store.settings.noteIndexPath) { store.notes.indexPath = noteIndexURL; store.indexSettings.useDatabase(noteIndexURL) }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }; Task { @MainActor in
                        if ["md", "markdown", "txt"].contains(url.pathExtension.lowercased()) { store.open(url) }
                    }
                }
            }; return true
        }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Image(systemName: "doc.richtext").foregroundStyle(Color.accentColor); Text(ProductIdentity.name).font(.title3.weight(.semibold)); Spacer() }.padding(.top, 20)
            Picker("侧栏", selection: $store.sidebarTab) { Text("最近").tag(0); Text("大纲").tag(1); Text("搜索").tag(2) }.pickerStyle(.segmented).labelsHidden()
            if store.sidebarTab == 2 { NotesPanel(store: store, notes: store.notes) } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if store.sidebarTab == 0 {
                        if store.recent.isEmpty { Text("打开过的文档会出现在这里").font(.callout).foregroundStyle(.secondary).padding(.top, 12) }
                        ForEach(store.recent) { item in
                            Button { store.open(URL(fileURLWithPath: item.path)) } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: item.pinned ? "pin.fill" : "doc.text").foregroundStyle(.secondary).padding(.top, 3)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                        Text(URL(fileURLWithPath: item.path).deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    }; Spacer(minLength: 0)
                                }.padding(9).background(store.active?.path == item.path ? Color.accentColor.opacity(0.1) : Color.clear).clipShape(RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain).help(item.path)
                            .contextMenu {
                                Button(item.pinned ? "取消固定" : "固定到顶部") { store.pin(item) }
                                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) }
                                Button("重新定位文件…") { store.relocate(item) }
                                Divider(); Button("从最近记录移除") { store.removeRecent(item) }
                            }
                        }
                    } else {
                        if store.outline.isEmpty { Text("文档中的标题会出现在这里").font(.callout).foregroundStyle(.secondary).padding(.top, 12) }
                        ForEach(store.outline) { item in
                            Button { store.bridge.send("goto", value: item.id) } label: {
                                Text(item.title).font(.system(size: 13, weight: item.level == 1 ? .semibold : .regular)).lineLimit(2).padding(.vertical, 7).padding(.leading, CGFloat(item.level - 1) * 10).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            }
            Spacer(minLength: 0)
            if !store.closedDrafts.isEmpty { Button("恢复关闭的草稿（\(store.closedDrafts.count)）") { store.restoreClosedDraft() }.font(.caption).padding(.bottom, 6) }
            if store.sidebarTab == 0 && !store.recent.isEmpty { Button("清空最近记录") { store.clearRecent() }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).padding(.bottom, 14) }
        }.padding(.horizontal, 14).background(Color(nsColor: .windowBackgroundColor))
    }
    /// Same resolution as `folio`: MDINDEX_DB, then this custom path, then the default.
    private var noteIndexURL: URL { FolioIndexConfig.resolveDatabase(setting: store.settings.noteIndexPath).url }
    var tabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(store.documents) { doc in
                    HStack(spacing: 8) {
                        Button { store.select(doc.id) } label: { HStack(spacing: 6) { if doc.dirty { Circle().frame(width: 5, height: 5) }; Text(doc.title).lineLimit(1) } }.buttonStyle(.plain)
                        Button { store.close(doc.id) } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain).help("关闭标签")
                    }.font(.system(size: 12)).padding(.horizontal, 14).frame(height: 36).background(doc.id == store.activeID ? Color(nsColor: .textBackgroundColor) : Color(nsColor: .windowBackgroundColor)).help(doc.path ?? "未命名草稿")
                }
            }
        }.scrollIndicators(.hidden).background(Color(nsColor: .windowBackgroundColor))
    }
    var welcome: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.richtext").font(.system(size: 56, weight: .ultraLight)).foregroundStyle(Color.accentColor)
            Text("打开文档，继续写作").font(.system(size: 27, weight: .medium, design: .serif))
            Text("拖入一个 Markdown 文件，或从最近文件开始。").foregroundStyle(.secondary)
            HStack(spacing: 12) { Button("打开文件…") { store.openPanel() }.keyboardShortcut("o"); Button("新建文档") { store.newDocument() } }.padding(.top, 10)
            Button("打开示例文档") { store.openExample() }.buttonStyle(.plain).foregroundStyle(Color.accentColor).font(.callout)
            Text("本地保存 · 自动恢复 · 即时渲染").font(.caption).foregroundStyle(.tertiary).padding(.top, 22)
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .textBackgroundColor))
    }
}

struct FolioSettingsView: View {
    @ObservedObject var store: EditorStore
    @ObservedObject private var indexSettings: NoteIndexSettingsModel
    init(store: EditorStore) {
        self.store = store; self.indexSettings = store.indexSettings
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("阅读与编辑").font(.title2.bold()); Spacer(); Button("完成") { store.showSettings = false }.keyboardShortcut(.defaultAction) }
            Picker("正文字体", selection: Binding(get: { store.settings.fontFamily ?? "system" }, set: { store.settings.fontFamily = $0; store.settingsChanged() })) {
                Text("系统字体").tag(SessionEdits.fontFamilies[0]); Text("宋体").tag(SessionEdits.fontFamilies[1]); Text("等宽字体").tag(SessionEdits.fontFamilies[2])
            }
            LabeledContent("正文字号 · \(Int(store.settings.fontSize))") { Slider(value: $store.settings.fontSize, in: SessionEdits.fontSizes, step: 1) }
            LabeledContent("正文宽度 · \(Int(store.settings.contentWidth))") { Slider(value: $store.settings.contentWidth, in: SessionEdits.contentWidths, step: SessionEdits.contentWidthStep) }
            Toggle("启动时恢复上次打开的文件", isOn: $store.settings.restoreSession)
            LabeledContent("图片目录") { TextField("assets", text: $store.settings.imageFolder).frame(width: 200) }
            Text("图片保存在文档旁的相对目录。未保存的文档会先提示保存。恢复草稿始终保留在本机。").font(.caption).foregroundStyle(.secondary)
            Divider()
            IndexFoldersView(model: indexSettings)
            LabeledContent("自定义索引文件") {
                TextField((NoteIndex.defaultPath.path as NSString).abbreviatingWithTildeInPath, text: Binding(get: { store.settings.noteIndexPath ?? "" }, set: { store.settings.noteIndexPath = $0.isEmpty ? nil : $0; store.settingsChanged() })).frame(width: 260)
            }.disabled(indexSettings.updating)
            Text("留空使用 Folio 的本机索引。搜索只读索引；更新索引不会修改原文，也不会上传内容。").font(.caption).foregroundStyle(.secondary)
            Divider(); Button("清空最近文件记录") { store.clearRecent() }
        }.padding(28).frame(width: 580)
            .onAppear { indexSettings.reloadConfiguration() }
            // Returning to Folio shows folders another writer (`folio roots`) changed meanwhile.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in indexSettings.reloadConfiguration() }
            .onChange(of: store.settings.fontSize) { store.settingsChanged() }
            .onChange(of: store.settings.contentWidth) { store.settingsChanged() }
            .onChange(of: store.settings.restoreSession) { store.settingsChanged() }
            .onChange(of: store.settings.imageFolder) { store.settingsChanged() }
    }
}

private struct IndexFoldersView: View {
    @ObservedObject var model: NoteIndexSettingsModel
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("索引文件夹").font(.headline)
                Spacer()
                Button("添加文件夹…") { model.chooseRoots() }.disabled(model.updating || model.configurationError != nil)
            }
            if model.config.roots.isEmpty {
                Text("还没有选择文件夹。添加后点击「更新索引」，即可搜索其中的 Markdown 文档。")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(model.config.roots, id: \.self) { path in
                            HStack(spacing: 8) {
                                Image(systemName: "folder").foregroundStyle(.secondary)
                                Text((path as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle).help(path)
                                Spacer(minLength: 0)
                                Button { model.removeRoot(path) } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.plain).help("移除此索引文件夹").disabled(model.updating || model.configurationError != nil)
                            }.font(.callout).padding(.vertical, 3)
                        }
                    }
                }.frame(height: min(112, CGFloat(model.config.roots.count) * 30))
            }
            HStack {
                if model.updating {
                    ProgressView().controlSize(.small)
                    Button("取消更新") { model.cancelUpdate() }
                } else {
                    Button("更新索引") { model.updateIndex() }
                        .disabled(model.config.roots.isEmpty || model.configurationError != nil)
                }
                Spacer()
                Text("\(model.documentCount.formatted()) 篇").foregroundStyle(.secondary)
            }
            if let updated = model.updatedAt {
                Text("上次更新：\(updated.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            } else { Text("尚未更新索引").font(.caption).foregroundStyle(.secondary) }
            if let error = model.configurationError { Text(error).font(.caption).foregroundStyle(.orange) }
            if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

/// Separate view so typing re-renders only the search column, not the editor window.
struct NotesPanel: View {
    @ObservedObject var store: EditorStore
    @ObservedObject var notes: NoteSearchModel
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索全部笔记", text: $notes.query).textFieldStyle(.plain).focused($focused)
                    .onSubmit { if let file = notes.result.files.first { store.openNote(path: file.path, line: file.lines.first?.line ?? 1) } }
                if notes.searching { ProgressView().controlSize(.mini) }
                else if !notes.query.isEmpty { Button { notes.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.tertiary) }
            }.font(.system(size: 13)).padding(8).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.08)))
            Group {
                if !notes.indexAvailable {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("还没有笔记索引").font(.callout.weight(.medium))
                        Text("在设置中选择文件夹并更新索引，即可搜索本机 Markdown 文档。")
                        Button("选择索引文件夹…") { store.showSettings = true }
                    }.foregroundStyle(.secondary).padding(.vertical, 6)
                }
                else if let error = notes.result.error { Text(error + "。可在设置里检查索引文件。").foregroundStyle(.orange) }
                else if notes.result.mode != .idle {
                    Text("\(notes.result.files.count)\(notes.result.truncated ? "+" : "") 篇 · \(notes.result.mode.rawValue) · \(String(format: "%.2f", notes.result.elapsed)) 秒")
                        .foregroundStyle(.secondary).help(notes.result.mode == .like ? "少于 3 个字时逐字匹配，结果更全但更慢" : "3 个字及以上走全文索引")
                } else { Text("输入关键词，回车打开第一条；点任一行跳到那一行。⌘⇧F 随时回到这里。").foregroundStyle(.secondary) }
            }.font(.system(size: 10)).lineSpacing(2)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(notes.result.files) { file in
                        VStack(alignment: .leading, spacing: 3) {
                            Button { store.openNote(path: file.path, line: file.lines.first?.line ?? 1) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.title.isEmpty ? file.name : file.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    Text(URL(fileURLWithPath: file.path).deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                        .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).help(file.path)
                            ForEach(file.lines) { hit in
                                Button { store.openNote(path: hit.path, line: hit.line) } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text("\(hit.line)").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary).frame(minWidth: 22, alignment: .trailing)
                                        Text(hit.text).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                .contextMenu {
                                    Button("拷贝 路径:行号") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("\(hit.path):\(hit.line)", forType: .string) }
                                    Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: hit.path)]) }
                                }
                            }
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(store.active?.path == file.path ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).clipped()
        .onAppear { notes.reloadIndex(); focused = true }.onChange(of: notes.focusRequest) { focused = true }
    }
}
