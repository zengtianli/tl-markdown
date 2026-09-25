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
        try await lazyComponents(store: store, renderer: renderer, root: root, require: require)
        print("Main editor integration checks passed; isolated state: \(root.path)")
    }

    /// KaTeX and highlight.js load on demand inside the production WKWebView (file:// page under the
    /// editor's CSP), including a document switch while they are still loading, the bundled WOFF2
    /// fonts, and no error banner. The document above has neither formulas nor code.
    @MainActor static func lazyComponents(store: EditorStore, renderer: WKWebView, root: URL, require: (Bool, String) throws -> Void) async throws {
        func js(_ source: String) async throws -> Any? { try await renderer.evaluateJavaScript(source) }
        func wait(_ condition: String, tries: Int = 200) async -> Bool {
            for _ in 0..<tries {
                if (try? await js(condition)) as? Bool == true { return true }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return false
        }
        let loaded = try await js("JSON.stringify({k:!!window.TLKatex,h:!!window.TLHljs})") as? String
        try require(loaded == "{\"k\":false,\"h\":false}", "a document without formulas or code loads neither component (\(loaded ?? "nil"))")
        let plainID = store.activeID!
        let formulas = root.appendingPathComponent("公式与代码.md"), code = root.appendingPathComponent("仅代码.md")
        try Data("# 公式\n\n行内 $E=mc^2$ 与块级：\n\n$$\\int_0^1 x^2\\,dx=\\frac13$$\n\n```swift\nlet x = 1\nfunc f() {}\n```\n".utf8).write(to: formulas)
        try Data("# 仅代码\n\n```js\nconst y = 2; function g(){ return y }\n```\n".utf8).write(to: code)
        // Switch away while the components are loading, then back.
        store.open(formulas); let formulaID = store.activeID!
        store.select(plainID)
        try await Task.sleep(for: .milliseconds(30))
        store.select(formulaID)
        let rendered = await wait("document.querySelectorAll('.rendered .katex').length>=2&&!document.querySelector('.math-pending,.rendered[data-pending]')&&!!document.querySelector('.rendered pre code .hljs-keyword')")
        let state = try await js("JSON.stringify({katex:document.querySelectorAll('.rendered .katex').length,pending:document.querySelectorAll('.math-pending,.rendered[data-pending]').length,keywords:document.querySelectorAll('.hljs-keyword').length})") as? String
        try require(rendered, "formulas and code render after on-demand loading, across a document switch (\(state ?? "nil"))")
        let fonts = await wait("[...document.fonts].some(f=>f.family.replace(/\"/g,'').startsWith('KaTeX')&&f.status==='loaded')", tries: 100)
        try require(fonts, "KaTeX fonts load from the bundled WOFF2 files")
        let family = try await js("getComputedStyle(document.querySelector('.katex')).fontFamily") as? String
        try require(family?.contains("KaTeX") == true, "the on-demand KaTeX stylesheet applies (\(family ?? "nil"))")
        store.open(code)
        try require(await wait("!!document.querySelector('.rendered pre code .hljs-keyword')"), "code in the next document is highlighted with the loaded component")
        try require(store.banner.isEmpty, "no editor error banner (\(store.banner))")
    }
}
