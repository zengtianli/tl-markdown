import SwiftUI
import WebKit
import UniformTypeIdentifiers

@MainActor final class DocumentWebView: WKWebView {
    var openDroppedFiles: (([URL]) -> Bool)?
    private func files(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if files(sender).contains(where: { ["md", "markdown", "txt"].contains($0.pathExtension.lowercased()) }) { return .copy }
        return super.draggingEntered(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let documents = files(sender).filter { ["md", "markdown", "txt"].contains($0.pathExtension.lowercased()) }
        if !documents.isEmpty, openDroppedFiles?(documents) == true { return true }
        return super.performDragOperation(sender)
    }
}

/// Native shell, embedded editor only. No local server or runtime package manager.
@MainActor final class EditorBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKURLSchemeHandler {
    weak var store: EditorStore?
    var webView: WKWebView?
    var ready = false
    func makeWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(self, name: "editor")
        config.setURLSchemeHandler(self, forURLScheme: "mdasset")
        let view = DocumentWebView(frame: .zero, configuration: config)
        view.openDroppedFiles = { [weak self] urls in urls.forEach { self?.store?.open($0) }; return true }
        view.navigationDelegate = self; view.setValue(false, forKey: "drawsBackground")
        self.webView = view
        guard let resource = Bundle.main.resourceURL?.appendingPathComponent("Editor/index.html"), FileManager.default.fileExists(atPath: resource.path) else {
            store?.banner = "编辑器资源缺失，请重新构建应用。"; return view
        }
        view.loadFileURL(resource, allowingReadAccessTo: resource.deletingLastPathComponent())
        return view
    }
    func send(_ action: String, value: Any = NSNull()) {
        guard ready, let data = try? JSONSerialization.data(withJSONObject: ["action": action, "value": value]), let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.tl.receive(\(json))") { [weak self] _, error in
            if let error { self?.store?.banner = "编辑器操作失败：\(error.localizedDescription)" }
        }
    }
    func load(_ document: OpenDocument, settings: EditorSettings, source: Bool) {
        send("load", value: ["id": document.id, "text": document.text, "revision": document.revision,
                            "selection": document.selection, "scroll": document.scroll, "source": source,
                            "fontSize": settings.fontSize, "contentWidth": settings.contentWidth, "fontFamily": settings.fontFamily ?? "system"])
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let type = body["type"] as? String, let store else { return }
        let id = body["id"] as? String ?? ""
        switch type {
        case "ready": ready = true; store.display()
        case "change": store.changed(id: id, text: body["text"] as? String ?? "", selection: body["selection"] as? Int ?? 0, scroll: body["scroll"] as? Double ?? 0)
        case "position": store.position(id: id, selection: body["selection"] as? Int ?? 0, scroll: body["scroll"] as? Double ?? 0)
        case "outline":
            if id == store.activeID { store.outline = (body["items"] as? [[String: Any]] ?? []).compactMap { item in
                guard let position = item["position"] as? Int, let title = item["title"] as? String, let level = item["level"] as? Int else { return nil }
                return OutlineItem(id: position, title: title, level: level)
            } }
        case "mode": store.sourceMode = body["source"] as? Bool ?? false
        case "copy": NSPasteboard.general.clearContents(); NSPasteboard.general.setString(body["text"] as? String ?? "", forType: .string)
        case "image":
            guard let encoded = body["data"] as? String, let data = Data(base64Encoded: encoded), data.count < 40_000_000 else { store.banner = "图片过大或无法读取（上限 40 MB）"; return }
            let mime = body["mime"] as? String ?? "image/png"
            let ext = UTType(mimeType: mime)?.preferredFilenameExtension ?? "png"
            store.insertImage(data: data, ext: ext, documentID: id)
        case "link":
            guard let href = body["href"] as? String else { return }
            if href.hasPrefix("#") { send("anchor", value: String(href.dropFirst())); return }
            if let url = URL(string: href), ["https", "http", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
            else if let path = store.documents.first(where: { $0.id == id })?.path, let url = URL(string: href, relativeTo: URL(fileURLWithPath: path))?.absoluteURL,
                    ["md", "markdown"].contains(url.pathExtension.lowercased()) { store.open(url) }
        case "error": store.banner = body["message"] as? String ?? "编辑器发生错误"
        default: break
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated {
            if let url = navigationAction.request.url, ["http", "https", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        } else { decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel) }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { ready = false; store?.persist(); webView.reload(); store?.banner = "编辑器已恢复，最近的修改已保留。" }
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = parts.queryItems?.first(where: { $0.name == "id" })?.value,
              let relative = parts.queryItems?.first(where: { $0.name == "path" })?.value,
              let path = store?.documents.first(where: { $0.id == id })?.path else {
            urlSchemeTask.didFailWithError(DocumentError.missing); return
        }
        let file: URL
        if relative.hasPrefix("/") { file = URL(fileURLWithPath: relative) }
        else { file = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent(relative) }
        let allowed = ["png", "jpg", "jpeg", "gif", "webp", "svg", "tiff", "tif", "heic", "avif", "bmp"]
        guard allowed.contains(file.pathExtension.lowercased()) else { urlSchemeTask.didFailWithError(DocumentError.encoding); return }
        do {
            let data = try Data(contentsOf: file)
            let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
            urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
        } catch { urlSchemeTask.didFailWithError(error) }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
struct EditorSurface: NSViewRepresentable {
    let bridge: EditorBridge
    func makeNSView(context: Context) -> WKWebView { bridge.makeWebView() }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
