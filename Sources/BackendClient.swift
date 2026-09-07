import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO
import WebKit

private struct NativeImageOverlay {
    var range: NSRange
    var url: URL
    var size: NSSize
}

/// The source string always remains Markdown. Styling never replaces source characters.
@MainActor final class MarkdownTextView: NSTextView {
    weak var bridge: EditorBridge?
    var documentID = ""
    let documentUndo = UndoManager()
    fileprivate var imageOverlays: [NativeImageOverlay] = []
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !imageOverlays.isEmpty, let manager = layoutManager, let container = textContainer else { return }
        let viewport = visibleRect
        let textRect = viewport.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
        let visibleGlyphs = manager.glyphRange(forBoundingRect: textRect, in: container)
        let characters = manager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        // Include the preceding image: its paragraph's reserved space may fill the viewport
        // even when its source line is just above it. Never force layout of distant images.
        let preceding = imageOverlays.lastIndex { $0.range.location < characters.location }
        var visible: [(NativeImageOverlay, NSRect)] = []
        for (index, item) in imageOverlays.enumerated() where (index == preceding || NSIntersectionRange(item.range, characters).length > 0) && item.range.location < (string as NSString).length {
            let glyphs = manager.glyphRange(forCharacterRange: item.range, actualCharacterRange: nil)
            let line = manager.boundingRect(forGlyphRange: glyphs, in: container)
            let rect = NSRect(x: textContainerOrigin.x + line.minX, y: textContainerOrigin.y + line.maxY + 8, width: item.size.width, height: item.size.height)
            if viewport.intersects(rect) { visible.append((item, rect)) }
        }
        bridge?.retainVisibleImages(Set(visible.map { $0.0.url.path }))
        for (item, rect) in visible where dirtyRect.intersects(rect) {
            bridge?.thumbnail(at: item.url)?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
    override var undoManager: UndoManager? { documentUndo }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point), ns = string as NSString
        if index < ns.length {
            let line = ns.lineRange(for: NSRange(location: index, length: 0)), raw = ns.substring(with: line)
            let regex = try! NSRegularExpression(pattern: "^\\s*[-+*] (\\[[ xX]\\]) ")
            if let match = regex.firstMatch(in: raw, range: NSRange(location: 0, length: (raw as NSString).length)) {
                let marker = NSRange(location: line.location + match.range(at: 1).location, length: match.range(at: 1).length)
                if NSLocationInRange(index, marker) {
                    let value = ns.substring(with: marker).lowercased() == "[x]" ? " " : "x"
                    insertText(value, replacementRange: NSRange(location: marker.location + 1, length: 1)); return
                }
            }
        }
        super.mouseDown(with: event)
    }
    override func paste(_ sender: Any?) {
        if let data = NSPasteboard.general.data(forType: .png) {
            bridge?.acceptImage(data, ext: "png", id: documentID); return
        }
        if let data = NSPasteboard.general.data(forType: .tiff),
           let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) {
            bridge?.acceptImage(png, ext: "png", id: documentID); return
        }
        // A Markdown editor pastes text, never RTF or HTML attributes.
        pasteAsPlainText(sender)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty { return .copy }
        return super.draggingEntered(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        for url in urls {
            if ["md", "markdown", "txt"].contains(url.pathExtension.lowercased()) { bridge?.store?.open(url) }
            else if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image), let data = try? Data(contentsOf: url) {
                bridge?.acceptImage(data, ext: url.pathExtension, id: documentID)
            }
        }
        if !urls.isEmpty { return true }
        return super.performDragOperation(sender)
    }
    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText(), selectedRange().length == 0 else { super.insertNewline(sender); return }
        let source = string as NSString, selection = selectedRange(), line = source.lineRange(for: selection)
        let prefix = source.substring(with: NSRange(location: line.location, length: selection.location - line.location))
        let regex = try! NSRegularExpression(pattern: "^(\\s*)([-+*]|[0-9]+[.)]) (?:\\[[ xX]\\] )?")
        guard let match = regex.firstMatch(in: prefix, range: NSRange(location: 0, length: (prefix as NSString).length)) else { super.insertNewline(sender); return }
        let ns = prefix as NSString, marker = ns.substring(with: match.range)
        if ns.length == match.range.length {
            insertText("\n", replacementRange: NSRange(location: line.location, length: marker.utf16.count)); return
        }
        var next = marker.replacingOccurrences(of: "[x]", with: "[ ]").replacingOccurrences(of: "[X]", with: "[ ]")
        let number = ns.substring(with: match.range(at: 2))
        if let n = Int(number.dropLast()), let last = number.last {
            next = ns.substring(with: match.range(at: 1)) + String(n + 1) + String(last) + " "
        }
        insertText("\n" + next, replacementRange: selection)
    }
}

@MainActor private final class NativeSession {
    let view: MarkdownTextView
    let scroll: NSScrollView
    var revision: Int
    var programmatic = false
    var needsFullStyle = true
    var needsLineStyle = false
    var styledLine = NSRange(location: NSNotFound, length: 0)
    var codeRanges: [NSRange] = []
    init(id: String, revision: Int, bridge: EditorBridge) {
        self.revision = revision
        let storage = NSTextStorage(), manager = NSLayoutManager(), container = NSTextContainer(containerSize: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        manager.allowsNonContiguousLayout = true
        container.widthTracksTextView = true
        view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 500), textContainer: container)
        view.bridge = bridge; view.documentID = id; view.delegate = bridge
        view.usesFontPanel = false
        view.isRichText = false; view.importsGraphics = false; view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false; view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 28, height: 24)
        view.usesFindBar = true; view.isIncrementalSearchingEnabled = true
        view.registerForDraggedTypes([.fileURL, .png, .tiff])
        scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        scroll.documentView = view; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = true; scroll.backgroundColor = .textBackgroundColor
        scroll.autoresizingMask = [.width, .height]
        scroll.contentView.postsBoundsChangedNotifications = true
    }
}

@MainActor final class EditorBridge: NSObject, NSTextViewDelegate {
    private var rich: RichEditorBridge?
    weak var store: EditorStore?
    private(set) var ready = false
    private var host: NSView?
    private var sessions: [String: NativeSession] = [:]
    private var currentID = ""
    private var sourceMode = false
    private var settings = EditorSettings()
    private var styleWork: DispatchWorkItem?
    private var observing = false
    private let imageCache = NSCache<NSString, NSImage>()
    private var imageCacheKeys: Set<String> = []
    private(set) var imagePreviewDecodeCount = 0
    private var imageSizes: [String: NSSize] = [:]
    private var active: NativeSession? { sessions[currentID] }
    var textView: MarkdownTextView? { active?.view }

    func makeEditorView(live: Bool = false) -> NSView {
        if live {
            if let rich { return rich.makeWebView() }
            let renderer = RichEditorBridge(); renderer.store = store; rich = renderer
            ready = true
            return renderer.makeWebView()
        }
        if let host { return host }
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 500)); host = container
        ready = true
        if !observing {
            NotificationCenter.default.addObserver(self, selector: #selector(scrolled(_:)), name: NSView.boundsDidChangeNotification, object: nil)
            observing = true
        }
        store?.display()
        return container
    }
    func load(_ incoming: OpenDocument, settings: EditorSettings, source: Bool) {
        if let rich { rich.load(incoming, settings: settings, source: source); return }
        var document = incoming
        let sameRevision = currentID == incoming.id && active?.revision == incoming.revision
        let wasMarked = active?.view.hasMarkedText() == true
        if currentID != incoming.id || (sameRevision && wasMarked) {
            if let view = active?.view, view.hasMarkedText() {
                // Commit the visible composition through NSTextInputClient, then end the IME session.
                // Never rewrite the marked string or guess which candidate the user intended.
                view.unmarkText(); view.inputContext?.discardMarkedText()
            }
            flush()
            if sameRevision && wasMarked, let refreshed = store?.documents.first(where: { $0.id == incoming.id }) { document = refreshed }
        } else { flushPosition() }
        if currentID != document.id { retainVisibleImages([]) }
        self.settings = settings; sourceMode = source; currentID = document.id
        guard let host else { return }
        let session: NativeSession
        let isNew = sessions[document.id] == nil
        if let existing = sessions[document.id] { session = existing }
        else { session = NativeSession(id: document.id, revision: document.revision, bridge: self); sessions[document.id] = session }
        let reset = session.revision != document.revision || session.view.string != document.text
        if reset {
            session.programmatic = true; session.view.string = document.text; session.revision = document.revision
            session.view.documentUndo.removeAllActions(); session.programmatic = false
        }
        host.subviews.forEach { $0.removeFromSuperview() }; session.scroll.frame = host.bounds; host.addSubview(session.scroll)
        let restored = NSRange(location: min(max(document.selection, 0), (document.text as NSString).length), length: 0)
        let selection = isNew || reset ? restored : session.view.selectedRange()
        let position = selection.location
        session.programmatic = true; session.view.setSelectedRange(selection); session.programmatic = false
        session.needsFullStyle = true; style(session); updateOutline()
        // Noncontiguous layout avoids laying out a megabyte just to display its first page.
        session.view.layoutManager?.ensureLayout(forCharacterRange: NSRange(location: position, length: 0))
        let maxY = max(0, session.view.bounds.height - session.scroll.contentView.bounds.height)
        session.scroll.contentView.scroll(to: NSPoint(x: 0, y: min(max(document.scroll, 0), maxY)))
        session.scroll.reflectScrolledClipView(session.scroll.contentView)
    }
    func send(_ action: String, value: Any = NSNull()) {
        if let rich { rich.send(action, value: value); return }
        switch action {
        case "empty": retainVisibleImages([]); flushPosition(); currentID = ""; host?.subviews.forEach { $0.removeFromSuperview() }
        case "forget": if let id = value as? String { sessions.removeValue(forKey: id) }
        case "flush": flush()
        case "mode": sourceMode = value as? Bool ?? false; store?.sourceMode = sourceMode; if let active { active.needsFullStyle = true; style(active) }
        case "settings":
            if let values = value as? [String: Any] {
                settings.fontSize = values["fontSize"] as? Double ?? settings.fontSize
                settings.contentWidth = values["contentWidth"] as? Double ?? settings.contentWidth
                settings.fontFamily = values["fontFamily"] as? String ?? settings.fontFamily
            }
            if let active { active.needsFullStyle = true; style(active) }
        case "command": if let command = value as? String { perform(command) }
        case "goto": if let location = value as? Int { go(location) }
        case "anchor":
            if let value = value as? String {
                let name = value.removingPercentEncoding ?? value
                if let item = store?.outline.first(where: { $0.title == name || $0.title.lowercased().replacingOccurrences(of: " ", with: "-") == name }) { go(item.id) }
                else if let text = active?.view.string as NSString? {
                    let range = text.range(of: "[^\(name.replacingOccurrences(of: "note-", with: ""))]:")
                    if range.location != NSNotFound { go(range.location) }
                }
            }
        case "insert":
            if let values = value as? [String: Any], let id = values["id"] as? String, let text = values["text"] as? String, let target = sessions[id] {
                target.view.insertText(text, replacementRange: target.view.selectedRange())
            }
        default: break
        }
    }
    func flush() {
        if let rich { rich.send("flush"); return }
        guard let session = active else { return }
        if store?.documents.first(where: { $0.id == currentID })?.text != session.view.string { notifyChange(session) }
        flushPosition()
    }
    func flushBeforeQuit(_ completion: @escaping (Bool) -> Void) {
        guard let rich, rich.ready, let web = rich.webView else { flush(); completion(true); return }
        web.evaluateJavaScript("({id:tl.inspect().id,text:tl.getText(),selection:tl.inspect().selection,scroll:tl.inspect().scroll})") { [weak self] result, error in
            if let value = result as? [String: Any], let id = value["id"] as? String,
               let text = value["text"] as? String {
                self?.store?.changed(id: id, text: text, selection: value["selection"] as? Int ?? 0, scroll: value["scroll"] as? Double ?? 0)
                completion(true)
            } else {
                self?.store?.banner = "未能读取当前编辑内容，请重试保存。"
                completion(false)
            }
        }
    }
    private func flushPosition() {
        guard let session = active else { return }
        store?.position(id: currentID, selection: session.view.selectedRange().location, scroll: session.scroll.contentView.bounds.origin.y)
    }
    @objc private func scrolled(_ note: Notification) {
        guard let active, note.object as? NSClipView === active.scroll.contentView, !active.programmatic else { return }
        flushPosition()
    }
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let view = textView as? MarkdownTextView, let session = sessions[view.documentID] else { return true }
        let replacement = replacementString ?? ""
        let old = (view.string as NSString).substring(with: affectedCharRange)
        // A change to line boundaries/fences can change all following block interpretation.
        if replacement.contains("\n") || old.contains("\n") || replacement.contains("`") || old.contains("`") || replacement.contains("~") || old.contains("~") {
            session.needsFullStyle = true
        }
        let delta = replacement.utf16.count - affectedCharRange.length
        session.codeRanges = session.codeRanges.map { range in
            if range.location >= NSMaxRange(affectedCharRange) { return NSRange(location: max(0, range.location + delta), length: range.length) }
            if NSLocationInRange(affectedCharRange.location, range) { return NSRange(location: range.location, length: max(0, range.length + delta)) }
            return range
        }
        view.imageOverlays = view.imageOverlays.compactMap { item in
            var item = item
            if NSIntersectionRange(item.range, affectedCharRange).length > 0 { return nil }
            if item.range.location >= NSMaxRange(affectedCharRange) { item.range.location = max(0, item.range.location + delta) }
            return item
        }
        return true
    }
    func textDidChange(_ notification: Notification) {
        guard let view = notification.object as? MarkdownTextView, let session = sessions[view.documentID], !session.programmatic else { return }
        session.needsLineStyle = true
        notifyChange(session)
        styleWork?.cancel()
        let work = DispatchWorkItem { [weak self, weak view] in
            guard let self, let view, !view.hasMarkedText(), let session = self.sessions[view.documentID] else { return }
            self.style(session)
            if view.documentID == self.currentID { self.updateOutline() }
        }
        styleWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }
    private func notifyChange(_ session: NativeSession) {
        store?.changed(id: session.view.documentID, text: session.view.string, selection: session.view.selectedRange().location, scroll: session.scroll.contentView.bounds.origin.y)
    }
    func textViewDidChangeSelection(_ notification: Notification) {
        guard let view = notification.object as? MarkdownTextView, let session = sessions[view.documentID], !session.programmatic, !view.hasMarkedText() else { return }
        if view.documentID == currentID { flushPosition() }
        style(session)
    }
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let href = link as? String else { return false }
        if href.hasPrefix("#") { send("anchor", value: String(href.dropFirst())); return true }
        if let url = URL(string: href), ["https", "http", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url); return true }
        if let path = store?.documents.first(where: { $0.id == currentID })?.path,
           let url = URL(string: href, relativeTo: URL(fileURLWithPath: path))?.absoluteURL,
           ["md", "markdown"].contains(url.pathExtension.lowercased()) { store?.open(url); return true }
        return true
    }
    func acceptImage(_ data: Data, ext: String, id: String) {
        guard data.count < 40_000_000 else { store?.banner = "图片过大（上限 40 MB）"; return }
        store?.insertImage(data: data, ext: ext, documentID: id)
    }
    private func go(_ position: Int) {
        guard let view = textView else { return }
        let range = NSRange(location: max(0, min(position, (view.string as NSString).length)), length: 0)
        view.setSelectedRange(range); view.scrollRangeToVisible(range); view.window?.makeFirstResponder(view)
    }
    private func perform(_ command: String) {
        guard let view = textView else { return }
        switch command {
        case "undo": view.undoManager?.undo()
        case "redo": view.undoManager?.redo()
        case "find", "findNext":
            sourceMode = true; store?.sourceMode = true; if let active { active.needsFullStyle = true; style(active) }
            let item = NSMenuItem(); item.tag = command == "find" ? NSTextFinder.Action.showReplaceInterface.rawValue : NSTextFinder.Action.nextMatch.rawValue
            view.performFindPanelAction(item)
        case "bold": wrap("**")
        case "italic": wrap("*")
        case "link": wrap("[", "](网址)")
        default: break
        }
    }
    private func wrap(_ before: String, _ after: String? = nil) {
        guard let view = textView else { return }; let range = view.selectedRange()
        let selected = (view.string as NSString).substring(with: range)
        view.insertText(before + selected + (after ?? before), replacementRange: range)
        view.setSelectedRange(NSRange(location: range.location + before.utf16.count, length: selected.utf16.count))
        view.window?.makeFirstResponder(view)
    }
    private func updateOutline() {
        guard let text = textView?.string else { store?.outline = []; return }
        let ns = text as NSString
        var items: [OutlineItem] = [], location = 0
        var fence: (marker: Character, count: Int)?
        while location < ns.length {
            let line = ns.lineRange(for: NSRange(location: location, length: 0)), raw = ns.substring(with: line)
            defer { location = NSMaxRange(line) }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let marker = trimmed.first
            let count = marker.map { character in trimmed.prefix(while: { $0 == character }).count } ?? 0
            if let open = fence {
                if marker == open.marker && count >= open.count && trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                continue
            }
            if let marker, (marker == "`" || marker == "~"), count >= 3 {
                if marker != "`" || !trimmed.dropFirst(count).contains("`") { fence = (marker, count); continue }
            }
            if let match = Self.heading.firstMatch(in: raw, range: NSRange(location: 0, length: (raw as NSString).length)) {
                items.append(OutlineItem(id: location + match.range.location, title: (raw as NSString).substring(with: match.range(at: 2)), level: match.range(at: 1).length))
            }
        }
        store?.outline = items
    }
    private static let heading = try! NSRegularExpression(pattern: "(?m)^(#{1,6})[ \\t]+(.+)$")
    private static let inlineRules: [(NSRegularExpression, Int)] = [
        (try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1"), 1),
        (try! NSRegularExpression(pattern: "(?<!\\*)(\\*)(?!\\*)(?=\\S)(.+?)(?<=\\S)\\1(?!\\*)"), 2),
        (try! NSRegularExpression(pattern: "(`)([^`\\n]+)\\1"), 3),
        (try! NSRegularExpression(pattern: "(~~)(.+?)\\1"), 4)
    ]
    private static let image = try! NSRegularExpression(pattern: "^\\s*!\\[([^]\\n]*)\\]\\((?:<([^>]+)>|([^\\s)]+))\\)\\s*$")
    private func localImage(_ href: String, id: String) -> (url: URL, size: NSSize)? {
        guard !href.contains("://"), let path = store?.documents.first(where: { $0.id == id })?.path else { return nil }
        let decoded = href.removingPercentEncoding ?? href
        let url = decoded.hasPrefix("/") ? URL(fileURLWithPath: decoded) : URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent(decoded)
        if let size = imageSizes[url.path] { return (url, size) }
        // Properties inspect the image header. No bitmap is decoded during document styling.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let size = (5...8).contains(orientation) ? NSSize(width: height.doubleValue, height: width.doubleValue) : NSSize(width: width.doubleValue, height: height.doubleValue)
        if imageSizes.count >= 256 { imageSizes.removeAll(keepingCapacity: true) }
        imageSizes[url.path] = size
        return (url, size)
    }
    fileprivate func retainVisibleImages(_ paths: Set<String>) {
        for key in imageCacheKeys.subtracting(paths) { imageCache.removeObject(forKey: key as NSString) }
        imageCacheKeys.formIntersection(paths)
    }
    fileprivate func thumbnail(at url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1200, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        let result = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        imagePreviewDecodeCount += 1
        // NSCache's cost limit is an eviction budget, not a strict process-memory ceiling.
        imageCache.totalCostLimit = 8_000_000; imageCache.countLimit = 4
        imageCache.setObject(result, forKey: key, cost: image.width * image.height * 4)
        imageCacheKeys.insert(url.path)
        return result
    }
    private static let link = try! NSRegularExpression(pattern: "(?<!!)\\[([^]\\n]+)\\]\\(([^)\\n]+)\\)")
    private func style(_ session: NativeSession) {
        let view = session.view
        guard !view.hasMarkedText(), let storage = view.textStorage else { return }
        session.programmatic = true; defer { session.programmatic = false }
        let ns = view.string as NSString, all = NSRange(location: 0, length: ns.length)
        let font: NSFont
        switch settings.fontFamily {
        case "serif": font = NSFont(name: "Songti SC", size: settings.fontSize) ?? .systemFont(ofSize: settings.fontSize)
        case "mono": font = .monospacedSystemFont(ofSize: settings.fontSize, weight: .regular)
        default: font = .systemFont(ofSize: settings.fontSize)
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 5; paragraph.paragraphSpacing = 5
        view.textContainerInset.width = max(28, (session.scroll.contentSize.width - settings.contentWidth) / 2)
        view.typingAttributes = [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]
        guard all.length > 0 else { return }
        let activeLine = ns.lineRange(for: NSRange(location: min(view.selectedRange().location, ns.length), length: 0))
        if !session.needsFullStyle && !session.needsLineStyle && session.styledLine == activeLine { return }
        let full = session.needsFullStyle || session.styledLine.location == NSNotFound
        let previousLine = NSIntersectionRange(session.styledLine, all)
        let workRanges: [NSRange]
        if full { workRanges = [all] }
        else if NSIntersectionRange(previousLine, activeLine).length > 0 || previousLine == activeLine {
            workRanges = [NSIntersectionRange(NSUnionRange(previousLine, activeLine), all)]
        } else { workRanges = [previousLine, NSIntersectionRange(activeLine, all)].filter { $0.length > 0 } }
        session.styledLine = activeLine; session.needsFullStyle = false; session.needsLineStyle = false
        if full { session.codeRanges = [] }
        view.imageOverlays.removeAll { item in sourceMode || workRanges.contains { NSIntersectionRange(item.range, $0).length > 0 } }
        view.needsDisplay = true
        func hide(_ range: NSRange) {
            if !sourceMode && NSIntersectionRange(range, activeLine).length == 0 {
                storage.addAttributes([.font: NSFont.systemFont(ofSize: 0.1), .foregroundColor: NSColor.clear], range: range)
            }
        }
        storage.beginEditing()
        for workRange in workRanges {
        storage.setAttributes([.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph], range: workRange)
        if sourceMode { storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: settings.fontSize, weight: .regular), range: workRange) }
        var location = workRange.location
        var fenced = !full && session.codeRanges.contains { NSLocationInRange(location, $0) }
        while location < NSMaxRange(workRange) {
            let line = ns.lineRange(for: NSRange(location: location, length: 0)), raw = ns.substring(with: line), trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fenced.toggle(); storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: line)
                if !sourceMode { hide(NSRange(location: line.location, length: max(0, line.length - (raw.hasSuffix("\n") ? 1 : 0)))) }
            } else if fenced || trimmed.hasPrefix("|") {
                if full && fenced { session.codeRanges.append(line) }
                storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: settings.fontSize * 0.9, weight: .regular), .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.12)], range: line)
            } else if !sourceMode {
                for match in Self.heading.matches(in: raw, range: NSRange(location: 0, length: (raw as NSString).length)) {
                    storage.addAttribute(.font, value: NSFont.systemFont(ofSize: settings.fontSize + Double(7 - match.range(at: 1).length) * 2.3, weight: .semibold), range: line)
                    hide(NSRange(location: line.location, length: match.range(at: 2).location))
                }
                if trimmed.hasPrefix("> ") {
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: line)
                    let marker = (raw as NSString).range(of: "> "); hide(NSRange(location: location + marker.location, length: marker.length))
                }
                for (regex, kind) in Self.inlineRules {
                    for match in regex.matches(in: raw, range: NSRange(location: 0, length: (raw as NSString).length)) {
                        let body = NSRange(location: location + match.range(at: 2).location, length: match.range(at: 2).length)
                        if kind == 1 { storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask), range: body) }
                        if kind == 2 { storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask), range: body) }
                        if kind == 3 { storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: settings.fontSize * 0.92, weight: .regular), .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.15)], range: body) }
                        if kind == 4 { storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: body) }
                        hide(NSRange(location: location + match.range.location, length: match.range(at: 1).length))
                        hide(NSRange(location: location + NSMaxRange(match.range) - match.range(at: 1).length, length: match.range(at: 1).length))
                    }
                }
                if trimmed.hasPrefix("!["), let match = Self.image.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) {
                    let range = match.range(at: match.range(at: 2).location == NSNotFound ? 3 : 2)
                    let href = (trimmed as NSString).substring(with: range)
                    if let image = localImage(href, id: view.documentID), image.size.width > 0, image.size.height > 0 {
                        let width = min(image.size.width, max(100, session.scroll.contentSize.width - view.textContainerInset.width * 2 - 16))
                        let size = NSSize(width: width, height: image.size.height * width / image.size.width)
                        let spacing = paragraph.mutableCopy() as! NSMutableParagraphStyle; spacing.paragraphSpacing = size.height + 20
                        storage.addAttribute(.paragraphStyle, value: spacing, range: line)
                        view.imageOverlays.append(NativeImageOverlay(range: NSRange(location: line.location, length: max(1, line.length - 1)), url: image.url, size: size))
                        hide(NSRange(location: line.location, length: max(0, line.length - (raw.hasSuffix("\n") ? 1 : 0))))
                    }
                }
                for match in Self.link.matches(in: raw, range: NSRange(location: 0, length: (raw as NSString).length)) {
                    let body = NSRange(location: location + match.range(at: 1).location, length: match.range(at: 1).length)
                    storage.addAttributes([.link: (raw as NSString).substring(with: match.range(at: 2)), .foregroundColor: NSColor.linkColor], range: body)
                    hide(NSRange(location: location + match.range.location, length: 1))
                    hide(NSRange(location: NSMaxRange(body), length: NSMaxRange(match.range) + location - NSMaxRange(body)))
                }
            }
            location = NSMaxRange(line)
        }
        }
        storage.endEditing()
        view.imageOverlays.sort { $0.range.location < $1.range.location }
        if view.imageOverlays.isEmpty { retainVisibleImages([]) }
    }
}

struct EditorSurface: NSViewRepresentable {
    let bridge: EditorBridge
    func makeNSView(context: Context) -> NSView { bridge.makeEditorView(live: true) }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

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
@MainActor final class RichEditorBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKURLSchemeHandler {
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
