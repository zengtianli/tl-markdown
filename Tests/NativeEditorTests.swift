import Foundation
import AppKit

@main struct NativeEditorTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/native-editor-test-data").appendingPathComponent(UUID().uuidString)
        let store = EditorStore(directory: root)
        let host = store.bridge.makeEditorView()
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
            guard condition() else { throw NSError(domain: "NativeEditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }; checks += 1; print("PASS \(name)")
        }
        store.newDocument(); let first = store.activeID!
        let fixture = "# 标题😀\n\n**粗体** 与 [链接](https://example.com)\n\n- 一项\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n"
        store.changed(id: first, text: fixture, selection: 0, scroll: 0); store.display()
        let view = store.bridge.textView!
        try check(view.string == fixture, "native rendering preserves exact source")
        try check(store.outline.first?.title == "标题😀", "native outline populated")
        view.setSelectedRange(NSRange(location: 0, length: 0)); store.command("bold")
        try check(view.string.hasPrefix("****#"), "native command edits source")
        store.command("undo"); try check(view.string == fixture, "native undo restores source")
        store.command("redo"); try check(view.string.hasPrefix("****#"), "native redo restores edit")
        store.command("undo")
        store.newDocument(); let second = store.activeID!
        let secondView = store.bridge.textView!
        secondView.insertText("另一个😀", replacementRange: NSRange(location: 0, length: 0))
        store.select(first); try check(store.bridge.textView === view, "tab retains its actual text view and undo manager")
        try check(view.string == fixture, "tab state isolated")
        store.select(second); store.command("undo"); try check(secondView.string.isEmpty, "second tab undo isolated")
        secondView.insertText("- 项目", replacementRange: NSRange(location: 0, length: 0)); secondView.insertNewline(nil)
        try check(secondView.string == "- 项目\n- ", "native newline continues Markdown list")
        secondView.insertNewline(nil); try check(secondView.string == "- 项目\n\n", "empty list item exits list")
        secondView.insertText("中文😀", replacementRange: secondView.selectedRange()); store.bridge.flush()
        try check(store.active?.text == secondView.string, "flush synchronizes native source")
        try check(store.active?.selection == (secondView.string as NSString).length, "UTF16 caret survives Unicode")
        store.select(first); view.setSelectedRange(NSRange(location: 12, length: 0)); store.toggleSource(); store.toggleSource()
        try check(view.string == fixture, "mode switching never serializes source")
        store.bridge.send("insert", value: ["id": second, "text": "![图片](<assets/a.png>)"])
        try check(store.documents.first(where: { $0.id == second })?.text.contains("assets/a.png") == true, "background insert targets original document")
        store.select(second)
        secondView.setMarkedText("候选", selectedRange: NSRange(location: 2, length: 0), replacementRange: secondView.selectedRange())
        let markedSource = secondView.string
        store.bridge.send("settings", value: ["fontSize": 20.0])
        try check(secondView.hasMarkedText() && secondView.string == markedSource, "native marked text survives style/settings update")
        var regressions = 0
        func regression(_ good: Bool, _ name: String) { print("\(good ? "PASS" : "FAIL") \(name)"); if good { checks += 1 } else { regressions += 1 } }
        store.select(first); store.select(second)
        regression(secondView.string == markedSource && !secondView.hasMarkedText() && store.active?.text == markedSource, "switching tabs commits and retains native marked text")
        store.select(first); view.setSelectedRange(NSRange(location: 2, length: 4)); store.select(second); store.select(first)
        regression(view.selectedRange() == NSRange(location: 2, length: 4), "switching tabs retains full selection range")
        store.newDocument(); let fenceID = store.activeID!
        let fenceSource = "# Real\n\n````swift\n# Example only\n```\n# Still example\n````\n\n~~~\n# Tilde example\n~~~\n\n## After\n"
        store.changed(id: fenceID, text: fenceSource, selection: 0, scroll: 0); store.display()
        regression(store.outline.map(\.title) == ["Real", "After"], "outline excludes fenced examples and honors matching fence length")
        let markedView = store.bridge.textView!
        markedView.setMarkedText("候选", selectedRange: NSRange(location: 2, length: 0), replacementRange: markedView.selectedRange())
        let sameIDMarked = markedView.string
        store.display()
        regression(markedView.string == sameIDMarked && store.active?.text == sameIDMarked, "same ID display refreshes snapshot after marked text commit")
        if regressions > 0 { throw NSError(domain: "NativeRegression", code: regressions, userInfo: [NSLocalizedDescriptionKey: "Native regressions failed: \(regressions)"]) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("example.png"))
        let imageFile = root.appendingPathComponent("image.md"), imageText = "# 图片\n\n![图片](example.png)\n"
        try Data(imageText.utf8).write(to: imageFile); store.open(imageFile)
        let imageView = store.bridge.textView!
        let imageRange = (imageText as NSString).range(of: "![")
        let paragraph = imageView.textStorage?.attribute(.paragraphStyle, at: imageRange.location, effectiveRange: nil) as? NSParagraphStyle
        try check(imageView.string == imageText && (paragraph?.paragraphSpacing ?? 0) >= 100, "relative image reserves native drawing space without replacing source")
        let imageID = store.activeID!, decodedBefore = store.bridge.imagePreviewDecodeCount
        try check(decodedBefore == 0, "document styling reads image metadata without decoding bitmaps")
        let distantFile = root.appendingPathComponent("distant-images.md")
        let distantText = String(repeating: "普通正文，滚动后才能看到图片。\n\n", count: 300) + String(repeating: "![远处图片](example.png)\n\n", count: 20)
        try Data(distantText.utf8).write(to: distantFile); store.open(distantFile)
        try check(store.bridge.imagePreviewDecodeCount == decodedBefore, "loading twenty offscreen images performs zero bitmap decodes")
        let renderBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 700, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        func drawViewport(_ textView: NSTextView) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: renderBitmap)
            textView.draw(textView.visibleRect)
            NSGraphicsContext.restoreGraphicsState()
        }
        drawViewport(store.bridge.textView!)
        try check(store.bridge.imagePreviewDecodeCount == decodedBefore, "drawing first page does not decode distant images")
        store.select(imageID); drawViewport(store.bridge.textView!)
        try check(store.bridge.imagePreviewDecodeCount == decodedBefore + 1, "drawing a visible image decodes its thumbnail on demand")
        drawViewport(store.bridge.textView!)
        try check(store.bridge.imagePreviewDecodeCount == decodedBefore + 1, "visible thumbnail is reused across repaints")
        let line = "这是一段用于性能测量的 Markdown 正文，保持日常段落长度。 English text **bold**.\n\n"
        var metrics: [[String: Any]] = []
        for bytes in [98_000, 1_000_000] {
            let text = String(repeating: line, count: bytes / line.utf8.count)
            store.newDocument(); let id = store.activeID!
            store.changed(id: id, text: text, selection: 0, scroll: 0)
            let start = ContinuousClock.now; store.display()
            let load = Double(start.duration(to: .now).components.attoseconds) / 1e15 + Double(start.duration(to: .now).components.seconds) * 1000
            let editor = store.bridge.textView!, editStart = ContinuousClock.now
            editor.insertText("输入😀", replacementRange: NSRange(location: 0, length: 0))
            let edit = Double(editStart.duration(to: .now).components.attoseconds) / 1e15 + Double(editStart.duration(to: .now).components.seconds) * 1000
            try await Task.sleep(for: .milliseconds(180))
            try check(store.active?.text.hasPrefix("输入😀") == true, "production edit \(bytes) bytes")
            metrics.append(["bytes": text.utf8.count, "loadCallMS": load, "editCallMS": edit])
        }
        print("METRICS " + String(data: try JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys]), encoding: .utf8)!)
        print("Native editor checks passed: \(checks)")
    }
}
