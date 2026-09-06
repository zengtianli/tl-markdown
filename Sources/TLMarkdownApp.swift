import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: EditorStore?
    var pending: [URL] = []
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        if let store { urls.forEach { store.open($0) } } else { pending.append(contentsOf: urls) }
        NSApp.reply(toOpenOrPrint: .success)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.bridge.ready, let web = store.bridge.webView else { self.store?.persist(); return .terminateNow }
        // WebKit callback is the barrier; a timer cannot guarantee the final edit reached Swift.
        web.evaluateJavaScript("window.tl.receive({action:'flush'})") { _, _ in
            store.persist(); sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil) }; return true
    }
}

@main struct TLMarkdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store: EditorStore
    init() {
        let root = ProcessInfo.processInfo.environment["TL_MARKDOWN_STATE_DIR"].map { URL(fileURLWithPath: $0) }
        _store = StateObject(wrappedValue: EditorStore(directory: root))
    }
    var body: some Scene {
        Window("TL Markdown", id: "editor") {
            ContentView(store: store).preferredColorScheme(.light).tint(Color(red: 0.56, green: 0.29, blue: 0.22))
                .onAppear {
                    delegate.store = store; delegate.pending.forEach { store.open($0) }; delegate.pending = []
                    if let path = ProcessInfo.processInfo.environment["TL_MARKDOWN_OPEN"] { store.open(URL(fileURLWithPath: path)) }
                }
        }.defaultSize(width: 1120, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建文档") { store.newDocument() }.keyboardShortcut("n")
                Button("打开…") { store.openPanel() }.keyboardShortcut("o")
                Divider(); Button("保存") { store.save() }.keyboardShortcut("s")
                Button("另存为…") { store.save(saveAs: true) }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("关闭标签") { if let id = store.activeID { store.close(id) } }.keyboardShortcut("w")
                Button("恢复关闭的草稿") { store.restoreClosedDraft() }.disabled(store.closedDrafts.isEmpty)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("撤销") { store.command("undo") }.keyboardShortcut("z")
                Button("重做") { store.command("redo") }.keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) { Button("设置…") { store.showSettings = true }.keyboardShortcut(",") }
            CommandMenu("编辑文档") {
                Button("搜索与替换") { store.command("find") }.keyboardShortcut("f")
                Button("查找下一个") { store.command("findNext") }.keyboardShortcut("g")
                Divider()
                Button("加粗") { store.command("bold") }.keyboardShortcut("b")
                Button("斜体") { store.command("italic") }.keyboardShortcut("i")
                Button("插入链接") { store.command("link") }.keyboardShortcut("k")
                Button("插入图片…") { store.insertImagePanel() }
                Divider()
                Button("切换源码 / 即时渲染") { store.toggleSource() }.keyboardShortcut("/", modifiers: [.command, .shift])
                Button("放大字号") { store.settings.fontSize = min(26, store.settings.fontSize + 1); store.settingsChanged() }.keyboardShortcut("+")
                Button("缩小字号") { store.settings.fontSize = max(13, store.settings.fontSize - 1); store.settingsChanged() }.keyboardShortcut("-")
            }
        }
    }
}
