import AppKit
import SwiftUI
import WebKit

/// Mount the production EditorSurface, not a separately constructed renderer or preview.
@main struct MainEditorTests {
    @MainActor static func main() async {
        do { try await run() }
        catch { fputs("FAIL \(error.localizedDescription)\n", stderr); exit(1) }
    }
    @MainActor static func run() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("主编辑区.md")
        let source = "# 主编辑验收\n\n| 项目 | 状态 |\n| --- | --- |\n| Folio | 修改前 |\n\n参见 [资料][ref]。\n\n[ref]: https://example.com\n"
        try Data(source.utf8).write(to: file)
        let store = EditorStore(directory: root.appendingPathComponent("state"))
        store.open(file)
        let host = NSHostingView(rootView: EditorSurface(bridge: store.bridge))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        defer { window.contentView = nil }
        func webView(in view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap { webView(in: $0) }.first
        }
        func require(_ good: Bool, _ name: String) throws {
            guard good else { throw NSError(domain: "MainEditorTests", code: 1,
                                            userInfo: [NSLocalizedDescriptionKey: name]) }
            print("PASS \(name)")
        }
        // A native-only surface fails here, even if the optional preview still renders perfectly.
        var web: WKWebView?
        for _ in 0..<50 {
            web = webView(in: host); if web != nil { break }
            try await Task.sleep(for: .milliseconds(20)); host.layoutSubtreeIfNeeded()
        }
        try require(web != nil, "production main EditorSurface mounts its full renderer")
        let renderer = web!
        for _ in 0..<200 {
            if (try? await renderer.evaluateJavaScript("Boolean(window.tl && document.querySelector('.rendered table'))")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let initial = try await renderer.evaluateJavaScript("({table:!!document.querySelector('.rendered table'),link:document.querySelector('.rendered a')?.textContent,visible:document.querySelector('.cm-content').innerText,text:tl.getText()})") as! [String: Any]
        try require(initial["table"] as? Bool == true, "main surface renders a grid without opening a preview")
        try require(initial["link"] as? String == "资料" && !(initial["visible"] as? String ?? "").contains("[ref]:"), "main surface resolves references and hides definitions")
        try require(initial["text"] as? String == source, "main rendering preserves original Markdown")
        _ = try await renderer.evaluateJavaScript("""
            document.querySelector('.rendered td').dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true}));
            const v=tl.getView(), at=v.state.doc.toString().indexOf('修改前');
            v.dispatch({changes:{from:at,to:at+3,insert:'修改后'},selection:{anchor:at+3}});
            document.querySelector('.rendered p').dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true}));
            """)
        let table = try await renderer.evaluateJavaScript("document.querySelector('.rendered table')?.textContent") as? String
        try require(table?.contains("修改后") == true, "main table re-renders after editing and leaving the block")
        let captured = await withCheckedContinuation { continuation in
            store.bridge.flushBeforeQuit { continuation.resume(returning: $0) }
        }
        let expected = source.replacingOccurrences(of: "修改前", with: "修改后")
        try require(captured && store.active?.text == expected, "main editor changes reach the production Swift store")
        try require(store.save(), "main edited document saves through production file IO")
        try require(try String(contentsOf: file, encoding: .utf8) == expected, "saved Markdown matches the rendered edit")
        print("Main editor integration checks passed; isolated state: \(root.path)")
    }
}
