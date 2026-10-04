import SwiftUI
import WebKit
import UniformTypeIdentifiers
import UIKit
import CryptoKit

/// UIKit/Vision adapter for the exact bundled Mac Editor. No Markdown renderer here.
struct MobileEditor: UIViewRepresentable {
    enum PrivacyRuleSource: Equatable { case stored, compiled }
    @ObservedObject var store: MobileStore
    let document: OpenDocument
    let reading: Bool
    let editorID: String
    func makeCoordinator() -> Coordinator { Coordinator(store: store, reading: reading, editorID: editorID) }
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(coordinator: context.coordinator)
    }
    /// The representable and hosted integration tests use this exact factory:
    /// there is only one WebKit configuration, bridge, and resource loader.
    func makeWebView(coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(coordinator, name: "editor")
        configuration.userContentController.addUserScript(WKUserScript(source: """
            const folioHandler = window.webkit.messageHandlers.editor;
            const folioPost = folioHandler.postMessage.bind(folioHandler);
            folioHandler.postMessage = body => folioPost({...body, mobileGeneration: window.__folioEditorGeneration || ''});
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.addUserScript(WKUserScript(
            source: "window.TL_PREVIEW_ONLY = \(reading ? "true" : "false");",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.setURLSchemeHandler(coordinator, forURLScheme: "mdasset")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = coordinator
        view.isOpaque = false
        #if os(iOS)
        view.scrollView.keyboardDismissMode = .interactive
        #endif
        coordinator.view = view
        store.registerEditor(scene: editorID, token: coordinator.owner) { [weak coordinator] in try await coordinator?.flush() }
        // User documents must not trigger remote tracking images. Local assets and
        // bundled lazy-load renderer modules still use the original Editor unchanged.
        let rules = "[{\"trigger\":{\"url-filter\":\"^https?://\",\"resource-type\":[\"image\"]},\"action\":{\"type\":\"block\"}}]"
        // WebKit persists compiled rules. The exact rule bytes name this cache;
        // a privacy-policy change can never reuse the previous compiled policy.
        let identifier = "FolioMobileLocalImages." + SHA256.hash(data: Data(rules.utf8)).map { String(format: "%02x", $0) }.joined()
        let ruleStore = WKContentRuleListStore.default()
        func load(_ list: WKContentRuleList?, _ error: Error?, source: PrivacyRuleSource) {
            guard error == nil, let list, list.identifier == identifier,
                  let resource = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Editor") else {
                store.notice = "本地编辑器或隐私过滤资源无法载入；原文未改动。"; return
            }
            coordinator.privacyRuleSource = source
            configuration.userContentController.add(list)
            view.loadFileURL(resource, allowingReadAccessTo: resource.deletingLastPathComponent())
        }
        ruleStore.lookUpContentRuleList(forIdentifier: identifier) { list, error in
            if error == nil, let list {
                load(list, nil, source: .stored)
            } else {
                ruleStore.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules) { list, error in
                    load(list, error, source: .compiled)
                }
            }
        }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.display(document, source: store.sourceMode)
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        // Retain the old view until its own pending text has been checked; a new
        // view's flush registration must never be removed by this teardown.
        Task { @MainActor in
            do { try await coordinator.flush() } catch { coordinator.store.notice = error.localizedDescription }
            coordinator.store.unregisterEditor(scene: coordinator.editorID, token: coordinator.owner)
            view.configuration.userContentController.removeScriptMessageHandler(forName: "editor")
            view.stopLoading()
        }
    }
    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKURLSchemeHandler {
        let store: MobileStore
        let reading: Bool
        let editorID: String
        let owner = UUID().uuidString
        weak var view: WKWebView?
        var ready = false
        fileprivate(set) var privacyRuleSource: PrivacyRuleSource?
        private var loadedID: String?
        private var loadedRevision: Int?
        private var sourceMode = false
        private var generation = ""
        init(store: MobileStore, reading: Bool, editorID: String) { self.store = store; self.reading = reading; self.editorID = editorID }
        func send(_ action: String, _ value: Any = NSNull()) {
            guard ready, let bytes = try? JSONSerialization.data(withJSONObject: ["action": action, "value": value]),
                  let json = String(data: bytes, encoding: .utf8) else { return }
            let prefix = action == "load" ? "window.__folioEditorGeneration='\(generation)';" : ""
            view?.evaluateJavaScript(prefix + "window.tl.receive(\(json))") { [weak self] _, error in
                if let error { self?.store.notice = "编辑器操作失败：\(error.localizedDescription)" }
            }
        }
        func display(_ document: OpenDocument, source: Bool) {
            guard ready else { return }
            if document.id != loadedID || document.revision != loadedRevision {
                guard let lease = try? store.workspace.bindEditor(owner: owner, id: document.id) else { return }
                generation = lease.generation
                loadedID = document.id; loadedRevision = document.revision; sourceMode = source
                send("load", ["id": document.id, "text": document.text, "revision": document.revision,
                              "selection": document.selection, "scroll": document.scroll, "source": reading ? false : source,
                              "fontSize": 17, "contentWidth": 820, "fontFamily": "system"])
            } else if source != sourceMode {
                sourceMode = source; send("mode", reading ? false : source)
            }
        }
        func flush() async throws {
            guard ready, let view else { return }
            let result = try await view.evaluateJavaScript("(() => {window.tl.receive({action:'flush'}); const s=window.tl.inspect(); return {id:s.id,text:window.tl.getText(),selection:s.selection,scroll:s.scroll,mobileGeneration:window.__folioEditorGeneration||''};})()")
            if let body = result as? [String: Any] {
                do { loadedRevision = try store.changed(body, owner: owner) }
                catch { loadedRevision = nil; store.refresh(); throw error }
            }
        }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                ready = true
                if let document = store.active { display(document, source: store.sourceMode) }
                // Signal actual rendered Editor data, not only the surrounding shell.
                view?.evaluateJavaScript("requestAnimationFrame(() => window.webkit.messageHandlers.editor.postMessage({type:'mobile-rendered'}))")
            case "mobile-rendered": LaneSignal.ready(store.active == nil ? "welcome" : "markdown")
            case "change": if !reading {
                do { loadedRevision = try store.changed(body, owner: owner) }
                catch { loadedRevision = nil; store.notice = error.localizedDescription; store.refresh() }
            }
            case "error": store.notice = body["message"] as? String ?? "编辑器发生错误"
            case "link":
                guard let href = body["href"] as? String else { return }
                if href.hasPrefix("#") { send("anchor", String(href.dropFirst())) }
                else if let url = URL(string: href), ["https", "http", "mailto"].contains(url.scheme ?? "") {
                    UIApplication.shared.open(url)
                } else { store.notice = "其他文稿请从“文件”打开，以取得独立文件授权。" }
            case "image":
                guard !reading, let id = body["id"] as? String,
                      let encoded = body["data"] as? String, let data = Data(base64Encoded: encoded),
                      store.documents.contains(where: { $0.id == id }) else { return }
                guard id == loadedID, body["mobileGeneration"] as? String == generation else {
                    store.notice = "图片操作的编辑器版本已变化，请在当前文稿重新插入；没有写入附件。"; return
                }
                do {
                    let ext = UTType(mimeType: body["mime"] as? String ?? "image/png")?.preferredFilenameExtension ?? "png"
                    let result = try store.workspace.storeImage(id: id, data: data, extension: ext)
                    send("insert", ["id": id, "text": result.markdown])
                } catch { store.notice = error.localizedDescription }
            default: break
            }
        }
        func webViewWebContentProcessDidTerminate(_ view: WKWebView) {
            try? store.workspace.persist()
            ready = false; loadedID = nil; loadedRevision = nil
            view.reload(); store.notice = "编辑器已恢复；最近收到的修改保留在本地草稿中。"
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let editor = Bundle.main.resourceURL?.appendingPathComponent("Editor", isDirectory: true).standardizedFileURL.path ?? ""
            let url = action.request.url
            let inside = url?.isFileURL == true && (url?.standardizedFileURL.path.hasPrefix(editor + "/") ?? false)
            decisionHandler(inside && action.navigationType != .linkActivated ? .allow : .cancel)
        }
        func webView(_ view: WKWebView, start task: WKURLSchemeTask) {
            do {
                guard let request = task.request.url, let parts = URLComponents(url: request, resolvingAgainstBaseURL: false),
                      let id = parts.queryItems?.first(where: { $0.name == "id" })?.value,
                      let relative = parts.queryItems?.first(where: { $0.name == "path" })?.value,
                      !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else { throw DocumentError.missing }
                let data = try store.workspace.readImage(id: id, relative: relative)
                let asset = URL(fileURLWithPath: relative)
                let mime = UTType(filenameExtension: asset.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                task.didReceive(URLResponse(url: request, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
                task.didReceive(data); task.didFinish()
            } catch { store.notice = error.localizedDescription; task.didFailWithError(error) }
        }
        func webView(_ view: WKWebView, stop task: WKURLSchemeTask) {}
    }
}
