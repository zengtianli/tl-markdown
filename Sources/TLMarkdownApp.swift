import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// Explicit recording mode requires its own session and never opens a key window.
/// It hosts the production ContentView and store; it does not simulate product UI.
enum FolioLaunch {
    static var background: Bool {
        let env = ProcessInfo.processInfo.environment
        guard env["FOLIO_BACKGROUND"] == "1", let path = env["TL_MARKDOWN_STATE_DIR"], !path.isEmpty else { return false }
        let requested = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let normal = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TLMarkdown").resolvingSymlinksInPath()
        return requested.path != normal.path && !requested.path.hasPrefix(normal.path + "/")
    }
}

private final class FolioRecordingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: EditorStore?
    var pending: [URL] = []
    private var recordingPanel: NSPanel?
    func applicationWillFinishLaunching(_ notification: Notification) {
        if FolioLaunch.background {
            // A nonactivating NSPanel is not a SwiftUI Window scene. AppKit can
            // otherwise mark this accessory process eligible for TAL recycling.
            // These only opt out of OS reclamation; explicit Quit still flushes.
            ProcessInfo.processInfo.disableAutomaticTermination("Folio isolated recording session")
            ProcessInfo.processInfo.disableSuddenTermination()
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if FolioLaunch.background, let store {
            NSApp.setActivationPolicy(.accessory)
            let panel = FolioRecordingPanel(contentRect: NSRect(x: 120, y: 120, width: 1120, height: 780),
                styleMask: [.titled, .closable, .resizable, .miniaturizable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = ProductIdentity.name
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = false
            panel.contentView = NSHostingView(rootView: ContentView(store: store).preferredColorScheme(.light)
                .tint(Color(red: 0.56, green: 0.29, blue: 0.22)))
            recordingPanel = panel
            pending.forEach { store.open($0) }; pending = []
            if let path = ProcessInfo.processInfo.environment["TL_MARKDOWN_OPEN"] { store.open(URL(fileURLWithPath: path)) }
            panel.orderBack(nil)
            return
        }
        // Load this bundle's artwork explicitly for the running Dock tile.
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
           let url = Bundle.main.url(forResource: name, withExtension: "icns"),
           let icon = NSImage(contentsOf: url) { NSApp.applicationIconImage = icon }
    }
    private var reportedBenchmark = false
    func reportBenchmarkIfRequested() {
        guard ProcessInfo.processInfo.environment["TL_MARKDOWN_BENCHMARK"] == "1", !reportedBenchmark else { return }
        reportedBenchmark = true
        // Diagnostic launch uses the same window/store/editor path, with an isolated state directory.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
            window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            let result: [String: Any] = ["readyEpoch": Date().timeIntervalSince1970, "documentBytes": self.store?.active?.text.utf8.count ?? 0,
                "nativeEditorReady": self.store?.bridge.ready == true]
            if let data = try? JSONSerialization.data(withJSONObject: result), let json = String(data: data, encoding: .utf8) {
                FileHandle.standardOutput.write(Data(("TL_BENCHMARK_READY " + json + "\n").utf8))
            }
            NSApp.terminate(nil)
        }
    }
    // Handle URL-based document events; SwiftUI's delegate does not forward
    // these to the legacy openFiles callback. Keep cold-launch URLs queued.
    func application(_ application: NSApplication, open urls: [URL]) {
        if let store { urls.forEach { store.open($0) } } else { pending.append(contentsOf: urls) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Ordinary launches use one SwiftUI Window scene, which exits when its
        // last window closes. The isolated NSPanel is not that scene: recording
        // overlay teardown must not schedule an exit for the still-visible panel.
        return !FolioLaunch.background
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if FolioLaunch.background {
            let event = NSAppleEventManager.shared().currentAppleEvent
            // Unified logging may redact NSLog's entire message. Keep this
            // diagnostic in the explicitly isolated session instead. Never
            // include the event payload, open paths, or document contents.
            if let directory = ProcessInfo.processInfo.environment["TL_MARKDOWN_STATE_DIR"] {
                let senderPID = event?.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
                let report: [String: Any] = [
                    "timestamp": ISO8601DateFormatter().string(from: Date()),
                    "pid": ProcessInfo.processInfo.processIdentifier,
                    "eventClass": event.map { NSNumber(value: $0.eventClass) } ?? NSNull(),
                    "eventID": event.map { NSNumber(value: $0.eventID) } ?? NSNull(),
                    "senderPID": senderPID.map { NSNumber(value: $0) } ?? NSNull(),
                    "senderBundleID": senderPID.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier } as Any? ?? NSNull(),
                    "callStack": Thread.callStackSymbols,
                ]
                let file = URL(fileURLWithPath: directory).appendingPathComponent("termination.json")
                do {
                    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    try data.write(to: file, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                } catch {
                    // Diagnostic failure must not alter normal quit/flush.
                    NSLog("Folio isolated termination diagnostic could not be written")
                }
            }
        }
        guard let store else { return .terminateNow }
        DispatchQueue.main.async {
            store.bridge.flushBeforeQuit { ok in store.persist(); sender.reply(toApplicationShouldTerminate: ok) }
        }
        return .terminateLater
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if FolioLaunch.background { return false }
        if !flag { sender.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil) }; return true
    }
}

@main struct TLMarkdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store: EditorStore
    init() {
        let root = ProcessInfo.processInfo.environment["TL_MARKDOWN_STATE_DIR"].map { URL(fileURLWithPath: $0) }
        let model = EditorStore(directory: root)
        _store = StateObject(wrappedValue: model)
        if FolioLaunch.background { delegate.store = model }
    }
    var body: some Scene {
        Window(ProductIdentity.name, id: "editor") {
            ContentView(store: store).preferredColorScheme(.light).tint(Color(red: 0.56, green: 0.29, blue: 0.22))
                .onAppear {
                    delegate.store = store; delegate.pending.forEach { store.open($0) }; delegate.pending = []
                    if let path = ProcessInfo.processInfo.environment["TL_MARKDOWN_OPEN"] { store.open(URL(fileURLWithPath: path)) }
                    delegate.reportBenchmarkIfRequested()
                }
        }.defaultSize(width: 1120, height: 780)
        .defaultLaunchBehavior(FolioLaunch.background ? .suppressed : .automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建文档") { store.newDocument() }.keyboardShortcut("n")
                Button("打开…") { store.openPanel() }.keyboardShortcut("o")
                Divider(); Button("保存") { store.bridge.flushBeforeQuit { if $0 { store.save() } } }.keyboardShortcut("s")
                Button("另存为…") { store.bridge.flushBeforeQuit { if $0 { store.save(saveAs: true) } } }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("关闭标签 / 预览") { if !FullPreview.shared.closeIfKey(), let id = store.activeID { store.close(id) } }.keyboardShortcut("w")
                Button("恢复关闭的草稿") { store.restoreClosedDraft() }.disabled(store.closedDrafts.isEmpty)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("撤销") { if !FullPreview.shared.isKey { store.command("undo") } }.keyboardShortcut("z")
                Button("重做") { if !FullPreview.shared.isKey { store.command("redo") } }.keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) { Button("设置…") { store.showSettings = true }.keyboardShortcut(",") }
            CommandGroup(replacing: .help) {
                Button("Folio 使用指南") {
                    if let url = URL(string: "https://app-mac-folio.tianli.cyou/#start") { NSWorkspace.shared.open(url) }
                }
                Button("Folio 产品主页") {
                    if let url = URL(string: "https://app-mac-folio.tianli.cyou/") { NSWorkspace.shared.open(url) }
                }
            }
            CommandMenu("编辑文档") {
                Button("搜索与替换") { if !FullPreview.shared.isKey { store.command("find") } }.keyboardShortcut("f")
                Button("查找下一个") { if !FullPreview.shared.isKey { store.command("findNext") } }.keyboardShortcut("g")
                Divider()
                Button("加粗") { if !FullPreview.shared.isKey { store.command("bold") } }.keyboardShortcut("b")
                Button("斜体") { if !FullPreview.shared.isKey { store.command("italic") } }.keyboardShortcut("i")
                Button("插入链接") { if !FullPreview.shared.isKey { store.command("link") } }.keyboardShortcut("k")
                Button("插入图片…") { if !FullPreview.shared.isKey { store.insertImagePanel() } }
                Button("完整预览（表格、公式、图表）") {
                    store.bridge.flush()
                    if let doc = store.active { FullPreview.shared.show(doc, settings: store.settings) }
                }.keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button("切换源码 / 即时渲染") { store.toggleSource() }.keyboardShortcut("/", modifiers: [.command, .shift])
                Button("放大字号") { store.settings.fontSize = min(26, store.settings.fontSize + 1); store.settingsChanged() }.keyboardShortcut("+")
                Button("缩小字号") { store.settings.fontSize = max(13, store.settings.fontSize - 1); store.settingsChanged() }.keyboardShortcut("-")
            }
        }
    }
}

/// Optional compatibility renderer. Never allocated by editor startup or ordinary document loading.
/// Read-only live rendering of the same document. Closing tears down WebKit and its handlers.
@MainActor final class FullPreview: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKURLSchemeHandler, NSWindowDelegate {
    static let shared = FullPreview()
    private var window: NSWindow?
    private var web: WKWebView?
    private var document: OpenDocument?
    private var settings = EditorSettings()
    private var renderReady = false
    private var refreshWork: DispatchWorkItem?
    func update(documents: [OpenDocument]) {
        guard let id = document?.id, let latest = documents.first(where: { $0.id == id }),
              latest.text != document?.text || latest.path != document?.path else { return }
        document = latest
        window?.title = "\(latest.title) · 实时预览"
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.renderReady, let doc = self.document else { return }
            self.send("refresh", value: ["id": doc.id, "text": doc.text])
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
    var isKey: Bool { window?.isKeyWindow == true }
    @discardableResult func closeIfKey() -> Bool {
        guard isKey else { return false }; window?.close(); return true
    }

    func show(_ document: OpenDocument, settings: EditorSettings) {
        window?.close()
        self.document = document; self.settings = settings
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: "editor")
        configuration.userContentController.addUserScript(WKUserScript(source: "window.TL_PREVIEW_ONLY=true;", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.setURLSchemeHandler(self, forURLScheme: "mdasset")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        let preview = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        preview.title = "\(document.title) · 实时预览"
        preview.isReleasedWhenClosed = false; preview.delegate = self; preview.contentView = view
        web = view; window = preview
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Editor/index.html") {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        preview.center(); preview.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        refreshWork?.cancel(); refreshWork = nil; renderReady = false
        web?.stopLoading()
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        web?.navigationDelegate = nil
        window?.contentView = nil
        web = nil; window = nil; document = nil
    }

    private func send(_ action: String, value: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["action": action, "value": value]), let json = String(data: data, encoding: .utf8) else { return }
        web?.evaluateJavaScript("window.tl.receive(\(json))", completionHandler: nil)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready", let doc = document {
            renderReady = true
            send("load", value: ["id": doc.id, "text": doc.text, "revision": doc.revision, "selection": 0, "scroll": 0, "source": false,
                "fontSize": settings.fontSize, "contentWidth": settings.contentWidth, "fontFamily": settings.fontFamily ?? "system"])
        } else if type == "copy", let text = body["text"] as? String {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        } else if type == "link", let href = body["href"] as? String {
            if href.hasPrefix("#") { send("anchor", value: String(href.dropFirst())) }
            else if let url = URL(string: href), ["http", "https", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.navigationType != .linkActivated && action.request.url?.isFileURL == true ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let relative = components.queryItems?.first(where: { $0.name == "path" })?.value, let path = document?.path else {
            task.didFailWithError(DocumentError.missing); return
        }
        let file = relative.hasPrefix("/") ? URL(fileURLWithPath: relative) : URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent(relative)
        guard ["png", "jpg", "jpeg", "gif", "webp", "svg", "tiff", "tif", "heic", "avif", "bmp"].contains(file.pathExtension.lowercased()) else { task.didFailWithError(DocumentError.encoding); return }
        do {
            let data = try Data(contentsOf: file)
            task.didReceive(URLResponse(url: url, mimeType: UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream", expectedContentLength: data.count, textEncodingName: nil))
            task.didReceive(data); task.didFinish()
        } catch { task.didFailWithError(error) }
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
