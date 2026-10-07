import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// Explicit recording mode requires its own session and never opens a key window.
/// It hosts the production ContentView and store; it does not simulate product UI.
enum FolioLaunch {
    static var uiSelfTest: Bool { CommandLine.arguments.contains("--ui-self-test") }
    /// The running window for the lifecycle command checks: the store and the「配置与更新」wiring of an ordinary
    /// launch, on isolated state, with no window, Dock icon or activation (see FolioLifecycleSelfTest).
    static var lifecycleSelfTest: Bool { CommandLine.arguments.contains("--lifecycle-self-test") }
    static var selfTest: Bool { uiSelfTest || lifecycleSelfTest }
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
    var lifecycle: AppConfiguration?
    var pending: [URL] = []
    private var recordingPanel: NSPanel?
    func applicationWillFinishLaunching(_ notification: Notification) {
        if FolioLaunch.selfTest { NSApp.setActivationPolicy(.prohibited) }
        if FolioLaunch.background {
            // A nonactivating NSPanel is not a SwiftUI Window scene. AppKit can
            // otherwise mark this accessory process eligible for TAL recycling.
            // These only opt out of OS reclamation; explicit Quit still flushes.
            ProcessInfo.processInfo.disableAutomaticTermination("Folio isolated recording session")
            ProcessInfo.processInfo.disableSuddenTermination()
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if FolioLaunch.uiSelfTest, let store {
            Task { await FolioUISelfTest.run(store: store) }
            return
        }
        if FolioLaunch.lifecycleSelfTest, let store {
            // A run-loop block, not a main-queue one: the self-test spins the run loop while its commands run, and
            // the main dispatch queue is only served again once no main-queue block is in progress.
            RunLoop.main.perform { [lifecycle] in MainActor.assumeIsolated { FolioLifecycleSelfTest.run(store: store, configuration: lifecycle) } }
            return
        }
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
        return !FolioLaunch.background && !FolioLaunch.selfTest
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
        if FolioLaunch.background || FolioLaunch.selfTest { return false }
        if !flag { sender.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil) }; return true
    }
}

@main struct TLMarkdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store: EditorStore
    private let configuration: AppConfiguration?
    init() {
        // Refuse these diagnostics before creating a store unless their state is isolated.
        if FolioLaunch.selfTest && !FolioLaunch.background {
            fputs("--ui-self-test and --lifecycle-self-test require FOLIO_BACKGROUND=1 and an isolated TL_MARKDOWN_STATE_DIR\n", stderr)
            exit(64)
        }
        if FolioLaunch.lifecycleSelfTest && !(FolioLifecycle.lifecycleIsolated && FolioLifecycle.stateIsolated) {
            fputs("--lifecycle-self-test also requires APP_LIFECYCLE_SUPPORT_DIR, APP_LIFECYCLE_CLOUD_DIR and FOLIO_PREFERENCES_SUITE\n", stderr)
            exit(64)
        }
        let root = ProcessInfo.processInfo.environment["TL_MARKDOWN_STATE_DIR"].map { URL(fileURLWithPath: $0) }
        // An ordinary launch has the「配置与更新」window (recording and UI-test windows do not); the lifecycle
        // self-test runs this same wiring on isolated state. The configuration comes from the one factory the
        // `folio` command uses, and the store gets the means to run `folio config import|sync` in this window.
        let wired = (!FolioLaunch.background && !FolioLaunch.uiSelfTest) || FolioLaunch.lifecycleSelfTest
        let config = wired ? FolioLifecycle.configuration() : nil
        let model = EditorStore(directory: root, lifecycle: config.map(FolioLifecycle.windowCommand))
        _store = StateObject(wrappedValue: model)
        configuration = config
        if wired { FolioLifecycle.installApp(config, store: model) }
        if FolioLaunch.background || FolioLaunch.selfTest { delegate.store = model }
        if FolioLaunch.lifecycleSelfTest { delegate.lifecycle = config }
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
        .defaultLaunchBehavior(FolioLaunch.background || FolioLaunch.selfTest ? .suppressed : .automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建文档") { store.newDocument() }.keyboardShortcut("n")
                Button("打开…") { store.openPanel() }.keyboardShortcut("o")
                Divider(); Button("保存") { store.bridge.flushBeforeQuit { if $0 { store.save() } } }.keyboardShortcut("s")
                Button("另存为…") { store.bridge.flushBeforeQuit { if $0 { store.save(saveAs: true) } } }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("关闭标签 / 预览") { if !FullPreview.shared.closeIfKey(), let id = store.activeID { store.close(id) } }.keyboardShortcut("w")
                Button("恢复关闭的草稿") { store.restoreClosedDraft() }.disabled(store.closedDrafts.isEmpty)
                Divider()
                Button("生成目录图谱…") { store.generateDirectoryGraphPanel() }.disabled(store.graphGenerating)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("撤销") { if !FullPreview.shared.isKey { store.command("undo") } }.keyboardShortcut("z")
                Button("重做") { if !FullPreview.shared.isKey { store.command("redo") } }.keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { store.showSettings = true }.keyboardShortcut(",")
                Button("配置与更新…") { AppLifecycleUI.shared.show() }
                Button("检查更新…") { AppLifecycleUI.shared.checkForUpdates() }
            }
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
                Button("搜索全部笔记") { NotificationCenter.default.post(name: .folioSearchNotes, object: nil) }.keyboardShortcut("f", modifiers: [.command, .shift])
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
                Button("放大字号") { store.settings.fontSize = SessionEdits.steppedFontSize(store.settings.fontSize, by: 1); store.settingsChanged() }.keyboardShortcut("+")
                Button("缩小字号") { store.settings.fontSize = SessionEdits.steppedFontSize(store.settings.fontSize, by: -1); store.settingsChanged() }.keyboardShortcut("-")
            }
        }
    }
}

extension FolioLifecycle {
    /// The window's side, called once at launch (and so by the lifecycle self-test): the shared window with Folio's
    /// portable settings, and the store re-reading them when an import or a sync changed session.json.
    /// There is no cross-process follower here: while this window runs it is the only writer of session.json and of
    /// the switch, because `folio config import|sync` hands the command to it (EditorStore.answerRequests).
    @MainActor static func installApp(_ configuration: AppConfiguration?, store: EditorStore) {
        configuration?.onChange = { [weak store] in store?.reloadConfiguration() }
        AppLifecycleUI.install(name: name, configuration: configuration, updateSource: updateSource)
    }
}

/// `--lifecycle-self-test`: this process is the running Folio window. It holds the session lock and has the
/// production「配置与更新」wiring (TLMarkdownApp.init), offscreen: activation policy .prohibited, no window ordered
/// in, no Dock icon. The real `folio` from this bundle's Resources/bin is run against it as child processes, through
/// a symlink named folio the way the installed command is called. Every judgement reads the stored values back
/// with a fresh process. State folder, preference domain, support folder and "cloud" folder are throwaway (set by
/// scripts/accept/lifecycle.sh): the owner's session, preferences and iCloud Drive are only stat'ed, before and after.
@MainActor private enum FolioLifecycleSelfTest {
    static func run(store: EditorStore, configuration: AppConfiguration?) {
        let files = FileManager.default, environment = ProcessInfo.processInfo.environment
        let suite = environment["FOLIO_PREFERENCES_SUITE"] ?? ""
        var checks: [String: Bool] = [:], order: [String] = [], facts: [String: Any] = [:]
        func check(_ name: String, _ passed: Bool) {
            if checks[name] == nil { order.append(name) }
            checks[name] = (checks[name] ?? true) && passed
            fputs("\(passed ? "ok  " : "FAIL") \(name)\n", stderr)   // progress, should the run be cut short
        }
        func finish() -> Never {
            // The throwaway preference domain goes with the run. The preferences daemon may still write an empty
            // shell for it after this process is gone; the caller deletes that by the name reported below.
            if suite.hasPrefix(FolioLifecycle.isolatedSuitePrefix) {
                UserDefaults.standard.removePersistentDomain(forName: suite); CFPreferencesAppSynchronize(suite as CFString)
            }
            let passed = !checks.isEmpty && checks.values.allSatisfy { $0 }
            var result: [String: Any] = ["ok": passed, "checks": checks, "failed": order.filter { checks[$0] == false }, "count": checks.count,
                                         "not_covered": ["the owner's real iCloud Drive and preference domain",
                                                         "the public release channel (an isolated run reads its own test release record, never the network)",
                                                         "update install --yes (the replacement itself is exercised by scripts/accept/cli_cases.py on a throwaway app)",
                                                         "a physical click on the window's switch and menus", "a visible window",
                                                         "a save by the window at the very moment a background sync pass writes session.json"]]
            facts.forEach { result[$0.key] = $0.value }
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8))
            }
            exit(passed ? 0 : 1)
        }
        // Deadlines count time the Mac was awake: a wait that spans a sleep must not fail (or pass) because of it.
        func awake() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
        func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        @discardableResult func wait(_ seconds: Double, until done: () -> Bool) -> Bool {
            let end = awake() + seconds
            while !done() && awake() < end { spin(0.02) }
            return done()
        }
        func stamp(_ url: URL) -> String {
            guard let attributes = try? files.attributesOfItem(atPath: url.path) else { return "absent" }
            return "\((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)/\(attributes[.size] ?? 0)"
        }

        // The owner's real state, looked at (never opened) before and after.
        let home = files.homeDirectoryForCurrentUser
        let owned = [home.appendingPathComponent("Library/Application Support/TLMarkdown/session.json"),
                     home.appendingPathComponent("Library/Preferences/\(FolioLifecycle.productID).plist"),
                     home.appendingPathComponent("Library/Application Support/TianliApps/Configuration/\(FolioLifecycle.productID)")]
        let ownedBefore = owned.map(stamp)

        let state = store.disk.directory
        guard let configuration, let outPath = environment["SOP_OUT_DIR"], let supportPath = environment["APP_LIFECYCLE_SUPPORT_DIR"],
              let cloudPath = environment["APP_LIFECYCLE_CLOUD_DIR"] else { check("isolated_environment", false); finish() }
        let out = URL(fileURLWithPath: outPath), support = URL(fileURLWithPath: supportPath), cloud = URL(fileURLWithPath: cloudPath)
        try? files.createDirectory(at: out, withIntermediateDirectories: true)
        facts["preference_domain"] = suite
        check("isolation_in_force", FolioLifecycle.lifecycleIsolated && FolioLifecycle.stateIsolated && FolioLifecycle.isolationProblem == nil
              && suite.hasPrefix(FolioLifecycle.isolatedSuitePrefix) && !state.path.hasPrefix(home.appendingPathComponent("Library").path)
              && environment["APP_LIFECYCLE_FOLLOW_CHANNEL"] == nil)
        check("window_owns_the_session", store.ownsSession && SessionLock.held(in: state))
        guard checks.values.allSatisfy({ $0 }) else { finish() }

        // What the owner would have open: a reading size of their own, a saved document and an unsaved draft.
        let note = state.appendingPathComponent("note.md")
        try? Data("# 笔记\n\n正文\n".utf8).write(to: note)
        guard let saved = try? DocumentIO.open(note) else { check("seed", false); finish() }
        store.documents = [saved]; store.activeID = saved.id
        store.newDocument()
        guard let draftID = store.activeID else { check("seed", false); finish() }
        store.changed(id: draftID, text: "未保存的草稿正文", selection: 0, scroll: 0)
        store.settings.fontSize = 18; store.settingsChanged()
        check("seed", store.persist() && store.documents.count == 2)

        // The shared window, built offscreen; its switch and status line are read directly.
        let shot = (try? AppLifecycleUI.shared.offscreenSnapshot(to: out.appendingPathComponent("lifecycle-window.png"))) ?? [:]
        let mirror = Mirror(reflecting: AppLifecycleUI.shared)
        let toggle = mirror.descendant("cloudToggle") as? NSControl, statusLine = mirror.descendant("syncStatus") as? NSTextField
        // A checkbox in this copy of the shared window, a switch in the current shared one: both are read.
        func toggleOn() -> Bool? { (toggle as? NSButton).map { $0.state == .on } ?? (toggle as? NSSwitch).map { $0.state == .on } }
        let off = "iCloud 配置同步已关闭"
        check("settings_window_offscreen_with_configuration_group", shot["upgrade_window_offscreen"] == true && shot["upgrade_image_rendered"] == true
              && toggle?.window != nil && toggle?.window?.isVisible == false && statusLine?.window === toggle?.window)
        check("app_starts_with_sync_off", !configuration.enabled && toggleOn() == false && statusLine?.stringValue == off)

        // The command, as an agent runs it: the bundle's own folio through a symlink named folio.
        let link = out.appendingPathComponent("folio")
        try? files.removeItem(at: link)
        let cli = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/bin/folio")
        guard files.isExecutableFile(atPath: cli.path), (try? files.createSymbolicLink(at: link, withDestinationURL: cli)) != nil else { check("command_link", false); finish() }
        var commands = 0
        func run(_ arguments: String..., json: Bool = true) -> (code: Int32, body: [String: Any], out: String, err: String) {
            let process = Process(), outPipe = Pipe(), errPipe = Pipe()
            process.executableURL = link; process.arguments = arguments + (json ? ["--json"] : [])
            process.standardOutput = outPipe; process.standardError = errPipe; process.standardInput = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return (-1, [:], "", "not started") }
            commands += 1
            // The window keeps running while the command does: this is where it takes the request and answers it.
            while process.isRunning { spin(0.01) }
            let text = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let body = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
            return (process.terminationStatus, body ?? [:], text, String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }
        /// The stored switch, and the stored reading size, as a fresh process reads them; nil when the readback failed.
        func stored() -> Bool? { let status = run("config", "status"); return status.code == 0 ? status.body["sync_enabled"] as? Bool : nil }
        func storedSize() -> Double? { let r = run("settings"); return r.code == 0 ? (r.body["settings"] as? [String: Any])?["font_size"] as? Double : nil }
        let cloudFile = cloud.appendingPathComponent(FolioLifecycle.productID + ".json")
        func cloudSize() -> Double? {
            (((try? JSONSerialization.jsonObject(with: Data(contentsOf: cloudFile))) as? [String: Any])?["values"] as? [String: Any])?["file.0.settings.fontSize"] as? Double
        }
        /// For `seconds`, the window, its switch and every fresh read of the stored value all stay at `target`.
        func holds(_ target: Bool, _ seconds: Double) -> Bool {
            let end = awake() + seconds
            repeat {
                guard configuration.enabled == target, toggleOn() == target, stored() == target else { return false }
                spin(0.03)
            } while awake() < end
            return true
        }
        func sync(_ target: Bool) -> (code: Int32, body: [String: Any], out: String, err: String) { run("config", "sync", target ? "on" : "off", "--yes") }
        var unfollowed: [[String: Any]] = []
        func follows(_ target: Bool) -> Bool {
            let began = awake(), clock = Date()
            let followed = wait(5) { configuration.enabled == target && toggleOn() == target && (statusLine?.stringValue == off) == !target }
            if !followed {
                unfollowed.append(["target": target, "enabled": configuration.enabled, "toggle_on": toggleOn() ?? false,
                                   "status": statusLine?.stringValue ?? "", "awake_s": awake() - began, "wall_s": Date().timeIntervalSince(clock)])
            }
            return followed
        }

        /// `sync_status` of a fresh `folio config status`: the sentence under the window's switch, as a command reads it.
        func sentence() -> (text: String?, from: String?, live: Bool?) {
            let status = run("config", "status").body["sync_status"] as? [String: Any]
            return (status?["text"] as? String, status?["from"] as? String, status?["live"] as? Bool)
        }
        /// The command reports this window's own sentence, the one its status line shows right now.
        func sentenceIsTheWindows() -> Bool {
            wait(3) { let read = sentence(); return read.from == "app" && read.live == true && read.text == statusLine?.stringValue && read.text == configuration.status }
        }

        let first = run("config", "status")
        check("status_reads_the_same_settings", first.code == 0 && first.body["has_settings"] as? Bool == true && first.body["sync_enabled"] as? Bool == false
              && first.body["app_running"] as? Bool == true && first.body["problem"] is NSNull
              && (first.body["keys"] as? [String])?.contains("file.0.settings.fontSize") == true)
        // A window that has published no sentence yet shows the switch's initial one: that is what the command reports.
        let initial = first.body["sync_status"] as? [String: Any]
        check("status_gives_the_sentence_under_the_switch", initial?["text"] as? String == off && initial?["text"] as? String == statusLine?.stringValue
              && initial?["live"] as? Bool == true && initial?["from"] as? String == "derived")
        facts["portable_keys"] = first.body["keys"] ?? []
        check("status_writes_nothing", !files.fileExists(atPath: support.appendingPathComponent(FolioLifecycle.productID).path) && !files.fileExists(atPath: cloud.path))

        // Switch on and off, several rounds: the command is run by this window, which shows it; nothing puts the old value back.
        for round in 1...3 {
            let on = sync(true)
            check("round\(round)_command_switches_on", on.code == 0 && on.body["changed"] as? Bool == true && on.body["sync_enabled"] as? Bool == true
                  && on.body["applied_by"] as? String == "window" && on.body["app_running"] as? Bool == true)
            check("round\(round)_window_follows_on", follows(true))
            check("round\(round)_on_is_not_written_back", holds(true, 1.2))
            // The window ran that command on its own configuration; the sentence it shows is still read as the window's.
            check("round\(round)_command_reads_the_windows_sentence_on", statusLine?.stringValue != off && sentenceIsTheWindows())
            if round == 1 {
                check("sync_on_uploads_through_the_shared_reconcile", cloudSize() == 18)
                // Nothing below can pass when the very first command did not get through: stop here with what was seen.
                if checks.values.contains(false) { facts["first_sync"] = ["code": Int(on.code), "out": on.out, "err": on.err]; finish() }
            }
            let offResult = sync(false)
            check("round\(round)_command_switches_off", offResult.code == 0 && offResult.body["changed"] as? Bool == true && offResult.body["sync_enabled"] as? Bool == false)
            check("round\(round)_window_follows_off", follows(false))
            check("round\(round)_off_is_not_written_back", holds(false, 1.2))
            check("round\(round)_command_reads_the_windows_sentence_off", statusLine?.stringValue == off && sentenceIsTheWindows())
        }

        // Back to back: the second command is sent the moment the first returns. From the moment the second
        // returns, no fresh read may see the first command's value again.
        var regressions: [String] = []
        func settled(_ target: Bool, _ label: String) {
            let end = awake() + 1.5
            while awake() < end { if stored() != target { regressions.append(label); return } }
            if !follows(target) { regressions.append(label + ":window") }
        }
        for round in 1...4 {
            _ = sync(true); _ = sync(false)
            settled(false, "on>off#\(round)")
            _ = sync(true); _ = follows(true); wait(0.5) { false }
            _ = sync(false); _ = sync(true)
            settled(true, "off>on#\(round)")
            _ = sync(false); _ = follows(false); wait(0.5) { false }
        }
        facts["back_to_back_regressions"] = regressions
        check("back_to_back_switches_never_regress", regressions.isEmpty)

        // The window's own switch and the command are one setting, both ways.
        if let toggle, let action = toggle.action {
            (toggle as? NSButton)?.state = .on; (toggle as? NSSwitch)?.state = .on
            NSApp.sendAction(action, to: toggle.target, from: toggle)
            check("window_switch_is_read_by_the_command", wait(5) { configuration.status != off } && stored() == true && sentenceIsTheWindows())
            let back = sync(false)
            check("command_switch_is_shown_by_the_window", back.code == 0 && follows(false) && holds(false, 0.6))
        } else { check("window_switch_is_read_by_the_command", false) }

        // Import: this window takes the settings, the switch is left alone, tabs and the unsaved draft stay.
        /// A complete set of the portable settings (an import replaces the set), with `changes` on top; `only` writes just those.
        func envelope(_ changes: [String: Any], product: String = FolioLifecycle.productID, only: Bool = false) -> Data {
            var values: [String: Any] = only ? [:] : ["file.0.settings.fontFamily": "system", "file.0.settings.fontSize": 18, "file.0.settings.contentWidth": 820,
                                                      "file.0.settings.restoreSession": true, "file.0.settings.imageFolder": "assets"]
            changes.forEach { values[$0.key] = $0.value }
            return (try? JSONSerialization.data(withJSONObject: ["version": 1, "product": product, "values": values], options: [.sortedKeys])) ?? Data()
        }
        func draftIntact() -> Bool {
            let session = run("session", "--text")
            let documents = session.body["documents"] as? [[String: Any]] ?? []
            return session.code == 0 && documents.count == 2 && documents.contains { $0["id"] as? String == draftID && $0["text"] as? String == "未保存的草稿正文" }
                && store.documents.first { $0.id == draftID }?.text == "未保存的草稿正文"
        }
        /// For `seconds` from now, every fresh read of the stored size is `size`; the window saves and "types" meanwhile,
        /// which is what would put a stale setting back if the window still held one.
        func sizeHolds(_ size: Double, _ seconds: Double, _ label: String) -> Bool {
            let end = awake() + seconds
            var saves = 0
            repeat {
                store.changed(id: draftID, text: "未保存的草稿正文", selection: saves % 3, scroll: 0)   // schedules the window's own save
                if saves % 2 == 0 { store.persist() }
                saves += 1
                guard storedSize() == size, store.settings.fontSize == size else { facts["size_regression_" + label] = ["stored": storedSize() ?? -1, "window": store.settings.fontSize]; return false }
                spin(0.05)
            } while awake() < end
            return true
        }
        // Someone typing in the window while the commands run: every keystroke ends in a save of the window's own
        // state a moment later. Here a save is due every millisecond, so one is always waiting to run the instant
        // the shared layer has written the imported settings into session.json: what a window still holding the
        // old settings would use to put them back.
        var typing: DispatchSourceTimer?
        func type(_ on: Bool) {
            typing?.cancel(); typing = nil
            guard on else { return }
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now(), repeating: .milliseconds(1))
            timer.setEventHandler { MainActor.assumeIsolated { _ = store.persist() } }
            timer.resume(); typing = timer
        }
        let incoming = out.appendingPathComponent("in.json")
        try? envelope(["file.0.settings.fontSize": 21, "file.0.settings.contentWidth": 900]).write(to: incoming)
        type(true)
        check("import_needs_yes", run("config", "import", incoming.path).code == 2 && storedSize() == 18)
        let imported = run("config", "import", incoming.path, "--yes")
        check("import_command_runs_in_the_window", imported.code == 0 && imported.body["imported"] as? Bool == true && imported.body["applied_by"] as? String == "window"
              && imported.body["sync"] == nil && imported.body["sync_enabled"] as? Bool == false)
        check("window_takes_imported_settings", wait(5) { store.settings.fontSize == 21 && store.settings.contentWidth == 900 })
        check("import_survives_the_windows_own_saves", sizeHolds(21, 1.5, "import"))
        check("import_leaves_the_switch_alone", holds(false, 0.6))
        check("import_keeps_tabs_and_unsaved_draft", draftIntact())
        let backups = (try? files.contentsOfDirectory(atPath: support.appendingPathComponent(FolioLifecycle.productID + "/Backups").path)) ?? []
        check("import_backs_up_and_keeps_owner_only_mode", backups.count == 1
              && ((try? files.attributesOfItem(atPath: store.disk.file.path))?[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        // Two imports back to back: the second one stands.
        let second = out.appendingPathComponent("in2.json")
        try? envelope(["file.0.settings.fontSize": 22]).write(to: incoming)
        try? envelope(["file.0.settings.fontSize": 23]).write(to: second)
        let a = run("config", "import", incoming.path, "--yes"), b = run("config", "import", second.path, "--yes")
        check("back_to_back_imports_keep_the_last", a.code == 0 && b.code == 0 && sizeHolds(23, 1.5, "back_to_back"))
        type(false)

        // Refused imports change nothing, and the session record stays readable.
        let bad: [(String, Data)] = [("wrong-type", envelope(["file.0.settings.fontSize": "big"])), ("out-of-range", envelope(["file.0.settings.fontSize": 99])),
                                     ("number-as-switch", envelope(["file.0.settings.restoreSession": 1])),
                                     ("incomplete", envelope(["file.0.settings.fontSize": 20], only: true)),
                                     ("foreign", envelope(["file.0.settings.fontSize": 20], product: "someone.else")),
                                     ("not-portable", envelope(["file.0.settings.noteIndexPath": "/tmp/other.db"]))]
        var refusedAll = true
        for (name, data) in bad {
            let file = out.appendingPathComponent("bad-\(name).json")
            try? data.write(to: file)
            let refused = run("config", "import", file.path, "--yes")
            if !(refused.code == 1 && refused.body["code"] as? String == "import_rejected" && refused.body["ok"] as? Bool == false && refused.body["error"] is String) {
                refusedAll = false; facts["not_refused_" + name] = refused.out
            }
        }
        check("bad_imports_are_refused_and_change_nothing", refusedAll && storedSize() == 23 && store.settings.fontSize == 23 && draftIntact())

        // With sync on, an import reaches the cloud copy; preferences, product file and cloud copy all keep it.
        check("window_follows_on_before_synced_import", sync(true).code == 0 && follows(true))
        try? envelope(["file.0.settings.fontSize": 24]).write(to: incoming)
        type(true)
        let carried = run("config", "import", incoming.path, "--yes")
        check("import_while_syncing_reaches_the_cloud_copy", carried.code == 0 && (carried.body["sync"] as? [String: Any])?["completed"] as? Bool == true && cloudSize() == 24)
        var syncedHolds = true
        let syncedEnd = awake() + 1.5
        repeat {
            store.persist()
            if !(storedSize() == 24 && cloudSize() == 24 && stored() == true && store.settings.fontSize == 24) { syncedHolds = false; break }
            spin(0.05)
        } while awake() < syncedEnd
        type(false)
        check("synced_import_holds_in_preferences_file_and_cloud", syncedHolds && follows(true))
        // A change made in the window while sync is on still reaches the cloud copy (the window's own path, untouched).
        store.settings.fontSize = 25; store.settingsChanged()
        check("window_change_while_syncing_reaches_the_cloud_copy", wait(8) { cloudSize() == 25 } && storedSize() == 25)
        _ = sync(false)
        check("window_follows_final_off", follows(false) && holds(false, 0.6))
        try? envelope(["file.0.settings.fontSize": 20]).write(to: incoming)
        let afterOff = run("config", "import", incoming.path, "--yes")
        check("import_after_switching_off_stays_local", afterOff.code == 0 && afterOff.body["sync"] == nil && sizeHolds(20, 0.8, "after_off") && cloudSize() == 25 && stored() == false)

        // Export is the window's envelope; failures use folio's own envelope; help lists every subcommand.
        let exported = out.appendingPathComponent("out.json")
        try? files.removeItem(at: exported)
        let export = run("config", "export", "-o", exported.path)
        let written = (try? JSONSerialization.jsonObject(with: Data(contentsOf: exported))) as? [String: Any]
        let again = run("config", "export", "-o", exported.path)
        check("export_writes_the_portable_settings_only", export.code == 0 && written?["product"] as? String == FolioLifecycle.productID
              && Set((written?["values"] as? [String: Any] ?? [:]).keys).isSubset(of: Set(FolioLifecycle.portableKeys.map { "file.0." + $0 }))
              && (written?["values"] as? [String: Any])?["file.0.settings.fontSize"] as? Double == 20
              && again.code == 2 && again.body["code"] as? String == "file_exists")
        let usage = run("config", "sync", "maybe")
        check("usage_error_exit_2_in_folios_envelope", usage.code == 2 && usage.body["code"] as? String == "usage" && usage.body["usage"] as? Bool == true
              && usage.body["ok"] as? Bool == false && usage.body["error"] is String && usage.err.contains("[usage]"))
        let help = run("--help", json: false).out
        check("help_lists_every_lifecycle_subcommand", ["\n  config status", "\n  config export", "\n  update check", "\n  config import", "\n  config sync on|off",
                                                        "\n  update install --yes", "\n  tabs close"].allSatisfy(help.contains) && !help.contains("暂无命令"))

        // Updates: an isolated run reads its own release record. A dry run names this window as the app it would ask
        // to quit, and asks nothing; without --yes nothing is installed. (--yes is never given here.)
        let unpublished = run("update", "check")
        check("update_reads_the_isolated_channel_only", unpublished.code == 1 && unpublished.body["code"] as? String == "check_incomplete"
              && (unpublished.body["source"] as? [String: Any])?["kind"] as? String == "private_cloud")
        let own = Bundle.main.bundleIdentifier ?? ""
        let feed = cloud.appendingPathComponent("TianliApps/Updates/\(own)/\(FolioLifecycle.isolatedChannel)")
        try? files.createDirectory(at: feed, withIntermediateDirectories: true)
        let release: [String: Any] = ["version": "99.0", "build": "1", "bundle_id": own, "channel": FolioLifecycle.isolatedChannel,
                                      "filename": "Folio-99.0.zip", "sha256": String(repeating: "a", count: 64), "size_bytes": 10]
        try? JSONSerialization.data(withJSONObject: release).write(to: feed.appendingPathComponent("release.json"))
        let offered = run("update", "check"), plan = run("update", "install", "--dry-run"), unconfirmed = run("update", "install")
        check("update_check_names_the_install_command", offered.code == 0 && offered.body["state"] as? String == "update_available"
              && (offered.body["upgrade"] as? [String: Any])?["command"] as? String == "folio update install --yes")
        check("update_install_dry_run_names_this_window_and_quits_nothing", plan.code == 0 && plan.body["dry_run"] as? Bool == true && plan.body["installed"] as? Bool == false
              && plan.body["app_running"] as? Bool == true && plan.body["will_quit_app"] as? Bool == true && plan.body["will_relaunch"] as? Bool == true
              && ((plan.body["would_install"] as? [String: Any])?["to"] as? [String: Any])?["version"] as? String == "99.0")
        check("update_install_needs_yes", unconfirmed.code == 2 && unconfirmed.body["code"] as? String == "confirmation_required" && unconfirmed.body["usage"] as? Bool == true)
        check("update_commands_leave_the_app_in_place", files.isExecutableFile(atPath: cli.path) && store.ownsSession && SessionLock.held(in: state)
              && ((try? files.contentsOfDirectory(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path)) ?? []).filter { $0.hasSuffix(".app") }.count == 1)

        // The tab commands, run by this window: close keeping the draft, bring it back, reload a changed file.
        let refusedClose = run("tabs", "close", draftID)
        let closed = run("tabs", "close", draftID, "--keep-draft")
        check("tabs_close_asks_then_keeps_the_draft", refusedClose.code == 1 && refusedClose.body["code"] as? String == "window_unsaved"
              && closed.code == 0 && closed.body["kept_draft"] as? Bool == true && closed.body["applied_by"] as? String == "window"
              && store.documents.count == 1 && store.closedDrafts.count == 1)
        let restored = run("tabs", "restore")
        check("tabs_restore_brings_the_draft_back", restored.code == 0 && store.documents.count == 2 && store.closedDrafts.isEmpty
              && store.active?.text == "未保存的草稿正文" && (run("session").body["closed_drafts"] as? [Any])?.isEmpty == true)
        try? Data("# 笔记\n\n别的软件改过\n".utf8).write(to: note, options: .atomic)
        if let i = store.documents.firstIndex(where: { $0.path != nil }) {
            let id = store.documents[i].id
            store.changed(id: id, text: "# 笔记\n\n窗口里没保存的修改\n", selection: 0, scroll: 0)
            let reloaded = run("tabs", "reload", note.path)
            check("tabs_reload_takes_the_file_and_keeps_the_edits", reloaded.code == 0 && reloaded.body["draft_copy"] is String
                  && store.documents.first { $0.id == id }?.text == "# 笔记\n\n别的软件改过\n"
                  && store.documents.contains { $0.path == nil && $0.text == "# 笔记\n\n窗口里没保存的修改\n" })
        } else { check("tabs_reload_takes_the_file_and_keeps_the_edits", false) }

        check("never_visible_or_active", NSApp.activationPolicy() == .prohibited && !NSApp.isActive && NSApp.windows.allSatisfy { !$0.isVisible })
        check("owner_session_preferences_and_sync_state_untouched", owned.map(stamp) == ownedBefore)
        facts["not_followed"] = unfollowed
        facts["commands_run"] = commands
        finish()
    }
}

/// Exercises the production SwiftUI shell, embedded editor and button action paths.
/// The panel is never ordered, activated or made key; only fictional files are used.
@MainActor private enum FolioUISelfTest {
    private struct Failure: Error { let message: String }
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
    private static func webView(in view: NSView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        return view.subviews.compactMap { webView(in: $0) }.first
    }
    private static func inspect(_ web: WKWebView) async throws -> [String: Any] {
        try await web.evaluateJavaScript("window.tl && window.tl.inspect()") as? [String: Any] ?? [:]
    }
    private static func wait(_ message: String, until condition: () async throws -> Bool) async throws {
        for _ in 0..<100 {
            if (try? await condition()) == true { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw Failure(message: "Timed out: " + message)
    }
    private static func capture(_ view: NSView, web: WKWebView, source: Bool, text: String, heading: String, to url: URL) async throws -> [String: Int] {
        let expected = String(decoding: try JSONSerialization.data(withJSONObject: ["source": source, "text": text, "heading": heading]), as: UTF8.self)
        // inspect() proves editor state only. Check the actual DOM and CSS too,
        // then ask WebKit to snapshot after committing its latest rendering update.
        let domCheck = """
        (() => { const expected = \(expected), content = document.querySelector('.cm-content');
          return document.body.classList.contains('source') === expected.source
            && window.tl.getText() === expected.text && !!content
            && content.innerText.includes(expected.heading)
            && (expected.source ? content.querySelectorAll('.rendered').length === 0
                                : content.querySelectorAll('.rendered').length > 0); })()
        """
        try await wait("rendered DOM matches screenshot state") { try await web.evaluateJavaScript(domCheck) as? Bool == true }
        _ = try await web.evaluateJavaScript("window.tl.getView().requestMeasure(); document.body.getBoundingClientRect().height")
        // Yield the native render transaction. requestAnimationFrame alone is not
        // reliable for a deliberately never-visible WebView.
        try await Task.sleep(for: .milliseconds(150))
        view.layoutSubtreeIfNeeded(); web.layoutSubtreeIfNeeded()
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true
        let snapshot = try await web.takeSnapshot(configuration: configuration)
        try require(try await web.evaluateJavaScript(domCheck) as? Bool == true, "DOM changed while capturing")
        guard let tiff = snapshot.tiffRepresentation, let webBitmap = NSBitmapImageRep(data: tiff),
              let webPNG = webBitmap.representation(using: .png, properties: [:]) else { throw Failure(message: "No WebKit PNG") }
        try require(webBitmap.pixelsWide >= 600 && webBitmap.pixelsHigh >= 400 && webPNG.count > 5000, "WebKit screenshot is empty or too small")
        let webURL = url.deletingPathExtension().appendingPathExtension("web.png")
        try webPNG.write(to: webURL, options: .atomic)
        view.needsDisplay = true
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure(message: "No native bitmap") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure(message: "No native PNG") }
        try png.write(to: url, options: .atomic)
        try require(bitmap.pixelsWide >= 1120 && bitmap.pixelsHigh >= 780 && png.count > 10000, "Native screenshot is empty or too small")
        return [url.lastPathComponent: png.count, webURL.lastPathComponent: webPNG.count]
    }
    private static func captureNative(_ view: NSView, to url: URL) async throws -> Int {
        try await Task.sleep(for: .milliseconds(150))
        view.layoutSubtreeIfNeeded(); view.needsDisplay = true; view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure(message: "No settings bitmap") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure(message: "No settings PNG") }
        try require(bitmap.pixelsWide >= 580 && bitmap.pixelsHigh >= 500 && png.count > 8000, "Settings screenshot is empty or too small")
        try png.write(to: url, options: .atomic)
        return png.count
    }
    static func run(store: EditorStore) async {
        var checks: [String: Bool] = [:]
        var screenshots: [String: Int] = [:]
        var panel: NSPanel?
        do {
            guard let output = ProcessInfo.processInfo.environment["SOP_OUT_DIR"] else { throw Failure(message: "SOP_OUT_DIR is required") }
            let outputURL = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: store.disk.directory, withIntermediateDirectories: true)
            let file = store.disk.directory.appendingPathComponent("ui-fixture.md")
            let original = "# Folio 界面验收\n\n真实编辑器 · 独立合成数据。\n\n## 第二节\n\n- 本地读写\n"
            try Data(original.utf8).write(to: file)
            let document = try DocumentIO.open(file)
            store.documents = [document]; store.activeID = document.id
            store.settings.noteIndexPath = store.disk.directory.appendingPathComponent("absent-index.sqlite").path
            let host = NSHostingView(rootView: ContentView(store: store).preferredColorScheme(.light))
            let window = FolioRecordingPanel(contentRect: NSRect(x: -20000, y: -20000, width: 1120, height: 780),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel = window; window.isReleasedWhenClosed = false; window.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: 1120, height: 780); host.layoutSubtreeIfNeeded()
            try await wait("production EditorSurface exists") { host.layoutSubtreeIfNeeded(); return webView(in: host) != nil }
            guard let web = webView(in: host) else { throw Failure(message: "Production EditorSurface missing") }
            try await wait("editor loaded document") { try await inspect(web)["id"] as? String == document.id }
            let loaded = try await inspect(web)
            try require(loaded["length"] as? Int == original.utf16.count, "Editor content length differs")
            try require((loaded["headings"] as? [[String: Any]])?.count == 2, "Heading render differs")
            checks["production_content_view_and_editor"] = true
            checks["document_content_and_outline"] = true

            store.toggleSource()
            try await wait("source toggle") { try await inspect(web)["source"] as? Bool == true }
            try require(store.sourceMode, "Source state differs")
            screenshots.merge(try await capture(host, web: web, source: true, text: original, heading: "# Folio 界面验收", to: outputURL.appendingPathComponent("native_ui-source.png"))) { _, new in new }
            checks["source_dom_css_and_render"] = true
            store.toggleSource()
            try await wait("rich toggle") { try await inspect(web)["source"] as? Bool == false }
            checks["source_mode_round_trip"] = true

            store.newDocument()
            let draftID = store.activeID
            try await wait("new document") { try await inspect(web)["id"] as? String == draftID }
            store.select(document.id)
            try await wait("tab selection") { try await inspect(web)["id"] as? String == document.id }
            checks["new_and_select_tab"] = store.documents.count == 2

            let refreshed = "# 刷新后的标题\n\n重新载入的内容。\n"
            try Data(refreshed.utf8).write(to: file, options: .atomic)
            store.reload()
            try await wait("reload action") { try await web.evaluateJavaScript("window.tl.getText()") as? String == refreshed }
            try require(store.active?.text == refreshed && store.active?.dirty == false, "Reloaded state differs")
            checks["reload_updates_editor_and_store"] = true
            screenshots.merge(try await capture(host, web: web, source: false, text: refreshed, heading: "刷新后的标题", to: outputURL.appendingPathComponent("native_ui-editor.png"))) { _, new in new }
            checks["reloaded_dom_css_and_render"] = true

            store.close(document.id)
            try await wait("close tab") { try await inspect(web)["id"] as? String == draftID }
            try require(store.documents.count == 1 && store.activeID == draftID, "Close did not select remaining draft")
            if let draftID { store.close(draftID) }
            try require(store.documents.isEmpty && store.active == nil, "Last tab did not close")
            checks["close_tab_and_empty_state"] = true

            // Use the same settings model and actions as the live controls; no sheet, chooser,
            // menu tracking or browser is opened by the self-test.
            store.sidebarTab = 2; store.notes.reloadIndex()
            try require(!store.notes.indexAvailable && store.indexSettings.config.roots.isEmpty, "Missing-index empty state differs")
            let emptyURL = outputURL.appendingPathComponent("native_ui-index-empty.png")
            screenshots[emptyURL.lastPathComponent] = try await captureNative(host, to: emptyURL)
            checks["missing_index_shows_setup_empty_state"] = true
            let indexRoot = store.disk.directory.appendingPathComponent("Example Notes", isDirectory: true)
            try FileManager.default.createDirectory(at: indexRoot, withIntermediateDirectories: true)
            try Data("# 文件夹笔记\n\n目录索引与两字搜索。\n".utf8).write(to: indexRoot.appendingPathComponent("note.md"))
            try require(store.indexSettings.addRoot(indexRoot), "Settings could not add a folder")
            let configured = try FolioIndexConfig.load(from: store.indexSettings.configURL)
            try require(configured.roots == [indexRoot.path], "Settings root was not persisted")
            store.indexSettings.removeRoot(indexRoot.path)
            try require(store.indexSettings.config.roots.isEmpty, "Settings could not remove a folder")
            try require(store.indexSettings.addRoot(indexRoot), "Settings could not restore a folder")
            store.indexSettings.useDatabase(URL(fileURLWithPath: store.settings.noteIndexPath!))
            store.indexSettings.updateIndex()
            try await wait("settings update index action") { !store.indexSettings.updating }
            try require(store.indexSettings.documentCount == 1 && store.indexSettings.updatedAt != nil, "Settings index count/time differs: " + store.indexSettings.message)
            try require(store.notes.indexAvailable, "Search did not see the newly created index")
            store.notes.query = "索引"; store.notes.schedule(immediately: true)
            try await wait("search newly created index") { !store.notes.searching && store.notes.result.files.count == 1 }
            try require(store.notes.result.files[0].lines.first?.line == 3, "Index search line differs")
            checks["settings_add_remove_and_update_index"] = true
            checks["updated_index_search_and_line"] = true
            let settingsHost = NSHostingView(rootView: FolioSettingsView(store: store).preferredColorScheme(.light))
            let settingsWindow = FolioRecordingPanel(contentRect: NSRect(x: -20000, y: -20000, width: 580, height: 760),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            settingsWindow.isReleasedWhenClosed = false; settingsWindow.contentView = settingsHost
            settingsHost.frame = NSRect(x: 0, y: 0, width: 580, height: 760)
            let settingsURL = outputURL.appendingPathComponent("native_ui-settings.png")
            screenshots[settingsURL.lastPathComponent] = try await captureNative(settingsHost, to: settingsURL)
            try require(!settingsWindow.isVisible && !settingsWindow.isKeyWindow && !settingsWindow.isMainWindow, "Settings became visible")
            settingsWindow.contentView = nil

            store.generateDirectoryGraph(at: indexRoot, openBrowser: false)
            try await wait("generate graph menu action") { !store.graphGenerating }
            guard let graph = store.lastGraphURL else { throw Failure(message: "Graph action failed: " + (store.graphError ?? "unknown")) }
            let generated = try String(contentsOf: graph, encoding: .utf8)
            try require(generated.contains("note.md"), "Graph does not contain fixture document")
            let foreign = "This is a user's existing HTML file."
            try Data(foreign.utf8).write(to: graph, options: .atomic)
            store.generateDirectoryGraph(at: indexRoot, openBrowser: false)
            try await wait("graph refuses overwrite") { !store.graphGenerating }
            let preserved = try String(contentsOf: graph, encoding: .utf8)
            try require(store.lastGraphURL == nil && store.graphError != nil && preserved == foreign, "Graph action overwrote a foreign file")
            checks["graph_menu_action_and_safe_collision"] = true
            checks["never_visible_or_key"] = !window.isVisible && !window.isKeyWindow && !window.isMainWindow && !NSApp.isActive
            checks["native_render_dimensions_and_bytes"] = screenshots.count == 6
            try require(checks.values.allSatisfy { $0 }, "A state assertion failed")
            store.persist()
            let result: [String: Any] = ["ok": true, "checks": checks, "screenshots": screenshots,
                "scope": "In-process production ContentView/EditorSurface/settings; source, tabs, reload, close, index setup/update/search and graph menu action/collision; isolated fictional data; never ordered or activated."]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8))
            panel?.contentView = nil
            exit(0)
        } catch {
            let detail = (error as? Failure)?.message ?? error.localizedDescription
            fputs("Folio UI self-test failed: \(detail)\n", stderr)
            panel?.contentView = nil
            exit(1)
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
