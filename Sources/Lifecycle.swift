import AppKit

// Folio's side of the shared「配置与更新」layer (Shared/AppLifecycle*.swift, byte copies of swift-shared). This file is
// the one place that names the product, its release channel and its portable settings. The app's window, the
// `folio config …` / `folio update check|install` commands and a window answering such a command are all built
// from it, so they read and write one thing. Compiled into the app and into Resources/bin/folio.
enum FolioLifecycle {
    static let productID = "cyou.tianli.TLMarkdown"
    static let name = "Folio"
    static let command = "folio"
    /// The one release channel: the window's「检查更新」and「升级到新版…」, `folio update check` and
    /// `folio update install` all read it.
    static let releaseFeed = URL(string: "https://app-mac-folio.tianli.cyou/release.json")!
    /// An isolated run (APP_LIFECYCLE_SUPPORT_DIR) never reads the public channel or the network: it reads the test
    /// release record the shared layer keeps under APP_LIFECYCLE_CLOUD_DIR (TianliApps/Updates/<bundle id>/isolated).
    static let isolatedChannel = "isolated"
    static var updateSource: AppUpdateSource { lifecycleIsolated ? .privateCloud(channel: isolatedChannel) : .manifest(releaseFeed) }
    /// The reading preferences inside session.json that travel with「导出配置」and the optional iCloud copy.
    /// The custom index file, the index folders, the recent list and the tabs stay on this Mac.
    static let portableKeys = ["settings.fontFamily", "settings.fontSize", "settings.contentWidth", "settings.restoreSession", "settings.imageFolder"]

    // MARK: Isolation

    /// A test run keeps the switch in a throwaway named preference domain (FOLIO_PREFERENCES_SUITE, this prefix only).
    static let isolatedSuitePrefix = "test.tianli.folio."
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }
    /// The shared layer keeps its backups, sync record and "cloud" copy in test folders when this is set.
    static var lifecycleIsolated: Bool { !(environment["APP_LIFECYCLE_SUPPORT_DIR"] ?? "").isEmpty }
    /// Folio keeps session.json outside the owner's state folder when TL_MARKDOWN_STATE_DIR says so.
    static var stateIsolated: Bool {
        func real(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }
        let owner = real(URL(fileURLWithPath: FolioIndexConfig.home, isDirectory: true).appendingPathComponent("Library/Application Support/TLMarkdown"))
        let current = real(FolioIndexConfig.stateDirectory)
        return current != owner && !current.hasPrefix(owner + "/")
    }
    /// The two isolations go together. One without the other would carry test settings into the owner's iCloud copy
    /// and preferences, or let a test write the owner's session.json: such a run gets no portable configuration.
    static var isolationProblem: String? {
        guard lifecycleIsolated != stateIsolated else { return nil }
        return lifecycleIsolated
            ? "设了 APP_LIFECYCLE_SUPPORT_DIR 的隔离运行还要用 TL_MARKDOWN_STATE_DIR 指到独立的状态目录，否则会改到本人的会话记录；未执行。"
            : "TL_MARKDOWN_STATE_DIR 指到了独立的状态目录：配置命令还要设 APP_LIFECYCLE_SUPPORT_DIR（与 APP_LIFECYCLE_CLOUD_DIR），否则会读写本人的 iCloud 配置与偏好；未执行。"
    }

    // MARK: One factory for the window and the command line

    /// The .app this executable belongs to: the app itself, or the bundle whose Resources/bin holds the command
    /// (also when it was started through the ~/.local/bin symlink). nil for a development binary outside a bundle.
    static let hostBundle: Bundle? = {
        if Bundle.main.bundleURL.pathExtension == "app", Bundle.main.bundleIdentifier != nil { return .main }
        let contents = FolioExecutable.url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        return contents.lastPathComponent == "Contents" && app.pathExtension == "app" ? Bundle(url: app) : nil
    }()

    /// The preference domain that holds the「使用 iCloud 记住配置」switch.
    /// The app's standard domain is the product's. The command has no bundle of its own (Resources/bin/folio, or
    /// the ~/.local/bin link), so its standard domain would be a different one: it names the app's domain.
    /// An isolated run uses a named throwaway domain; a file-path suite is not kept in step between two running
    /// processes, a named one is.
    static func defaults() -> UserDefaults {
        if lifecycleIsolated {
            let requested = environment["FOLIO_PREFERENCES_SUITE"] ?? ""
            // A test-prefixed name is never the main bundle's identifier or the global domain, the two names UserDefaults refuses.
            return UserDefaults(suiteName: requested.hasPrefix(isolatedSuitePrefix) ? requested : isolatedSuitePrefix + "isolated")!
        }
        if hostBundle === Bundle.main { return .standard }
        return UserDefaults(suiteName: hostBundle?.bundleIdentifier ?? productID) ?? .standard
    }

    static func makeConfiguration() -> AppConfiguration {
        AppConfiguration(productID: productID,
                         files: [AppConfigurationFile(url: FolioIndexConfig.stateDirectory.appendingPathComponent("session.json"), keys: portableKeys)],
                         defaults: defaults())
    }
    /// nil when the run mixes isolated and real state (see `isolationProblem`): the window then shows the update
    /// group only, and the commands refuse.
    static func configuration() -> AppConfiguration? { isolationProblem == nil ? makeConfiguration() : nil }

    // MARK: Commands

    /// Which process is running the command, for the `app_running` it reports.
    enum Runner {
        /// The window that owns session.json, answering a command handed to it.
        case window
        /// The command itself, holding the session lock: no window is running.
        case commandWithLock
        /// The command itself, reading only.
        case reader
    }

    /// One `config …` / `update …` command through the shared layer, with what it printed (the shared layer's own
    /// text or JSON; `folio` puts a failure into its usual envelope). `arguments` starts at the verb; main thread.
    static func run(_ arguments: [String], configuration: AppConfiguration?, as runner: Runner) -> SessionRequests.CommandReply {
        if let refusal = importRefusal(arguments) { return refusal }
        if let problem = replacementProblem(arguments) {
            return failure(command: "update install", code: "isolation_incomplete", message: problem, exit: 1, json: arguments.contains("--json"))
        }
        var out = "", err = ""
        var product = AppLifecycleCLI.Product(command: command, name: name, configuration: configuration, updateSource: updateSource)
        if let hostBundle { product.bundle = hostBundle }
        product.out = { out += $0 + "\n" }
        product.err = { err += $0 + "\n" }
        switch runner {
        case .window: product.runningApp = { [ProcessInfo.processInfo.processIdentifier] }
        case .commandWithLock: product.runningApp = { [] }
        case .reader:
            // An isolated run has no installed app to look up: its "app" is whoever holds that state folder's lock.
            // That is this command's own app when one is running (the self-test's window), found the way the shared
            // layer finds the installed one. A holder with no process to name (a test holding the lock) still counts
            // as a running window for `config`; `update install` asks the processes it is given to quit, so it is
            // never handed a made-up pid.
            if lifecycleIsolated {
                let state = FolioIndexConfig.stateDirectory, identifier = hostBundle?.bundleIdentifier, update = arguments.first == "update"
                product.runningApp = {
                    guard SessionLock.held(in: state) else { return [] }
                    let own = ProcessInfo.processInfo.processIdentifier
                    let windows = identifier.map { NSRunningApplication.runningApplications(withBundleIdentifier: $0).map(\.processIdentifier).filter { $0 != own } } ?? []
                    return windows.isEmpty && !update ? [0] : windows
                }
            }
        }
        // The shared layer writes session.json itself, not through SessionDisk. When this command is the writer
        // (no window), it keeps the record as it was, to put back should the result not be a readable session.
        let disk = SessionDisk(directory: FolioIndexConfig.stateDirectory)
        var kept: Data?
        if case .commandWithLock = runner, (try? disk.read()) != nil { kept = FileManager.default.contents(atPath: disk.file.path) }
        // The shared layer gives every command its own status record, so that a short-lived command never replaces
        // the sentence a running window shows. Here the window itself runs the command, on its own configuration:
        // what that publishes is the window's sentence, and `folio config status` reads it from the window's record.
        // The name is put back before the first sentence of this command is recorded (those arrive on the main
        // queue, behind this block) and again when the command returns without having waited for anything.
        if case .window = runner, let configuration {
            DispatchQueue.main.async { configuration.statusRecordName = AppConfiguration.appStatusRecord }
        }
        let code = AppLifecycleCLI.run(arguments, product: product)
        if case .window = runner, let configuration {
            configuration.statusRecordName = AppConfiguration.appStatusRecord
            // A sentence that was already on its way when the command began went to the command's record. Should the
            // window's record now say something else than the window shows, one more pass publishes it again.
            if let record = configuration.statusRecord(), record.status != configuration.status { configuration.reconcile() }
        }
        if case .commandWithLock = runner, FileManager.default.fileExists(atPath: disk.file.path) {
            if let kept, (try? disk.read()) == nil {
                // Settings that arrived (from the cloud copy, say) left the record undecodable: tabs and drafts come first.
                try? kept.write(to: disk.file, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: disk.file.path)
                var message = "收到的设置会让会话记录读不出（缺项或类型不对），已恢复原记录，未采用"
                if configuration?.enabled == true, positionals(arguments).first == "sync" {
                    var quiet = product; quiet.out = { _ in }; quiet.err = { _ in }
                    _ = AppLifecycleCLI.run(["config", "sync", "off", "--yes"], product: quiet)
                    message += "；「使用 iCloud 记住配置」已拨回关"
                }
                return failure(command: (["config"] + positionals(arguments).prefix(1)).joined(separator: " "), code: "failed",
                               message: message, exit: 1, json: arguments.contains("--json"))
            }
            // Put the owner-only mode back (in the window, the store's own save does, right after this returns).
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: disk.file.path)
        }
        return .init(exit: code, out: out, err: err)
    }
    /// What the app gives its window's store: `folio config import|sync` arriving while the window runs is run here,
    /// on the window's own configuration, so the switch, the status line and the settings follow at once.
    static func windowCommand(_ configuration: AppConfiguration) -> ([String]) -> SessionRequests.CommandReply {
        { words in run(words, configuration: configuration, as: .window) }
    }

    /// The words that are not flags or `-o`'s value, as the shared layer reads them; the verb is not included.
    static func positionals(_ arguments: [String]) -> [String] {
        var words: [String] = [], index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "-o" || argument == "--output" { index += 2; continue }
            if !argument.hasPrefix("-") { words.append(argument) }
            index += 1
        }
        return words
    }
    /// Whether the command changes settings and so must be run by whoever may write session.json. A dry run, a
    /// missing --yes and everything else only read. (`config import` ignores --dry-run: only --yes decides.)
    static func writes(_ arguments: [String]) -> Bool {
        guard arguments.first == "config", arguments.contains("--yes") else { return false }
        switch positionals(arguments).first {
        case "import": return true
        case "sync": return !arguments.contains("--dry-run")
        default: return false
        }
    }
    /// `update install` that would really replace the app: not a dry run, and confirmed.
    static func replaces(_ arguments: [String]) -> Bool {
        arguments.first == "update" && positionals(arguments).first == "install" && arguments.contains("--yes") && !arguments.contains("--dry-run")
    }
    /// A test or diagnostic run never swaps the owner's installed Folio, whatever a release record says. A run on
    /// its own state folder alone replaces nothing; an isolated run replaces only an app inside its own support
    /// folder (where the shared layer also keeps that run's rollback copy and its "Trash"). nil: nothing to object to.
    static func replacementProblem(_ arguments: [String]) -> String? {
        guard replaces(arguments) else { return nil }
        guard lifecycleIsolated else {
            return stateIsolated ? "TL_MARKDOWN_STATE_DIR 指到了独立的状态目录（测试或诊断运行）：这样的运行不替换 App；未执行。" : nil
        }
        func real(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }
        let support = real(URL(fileURLWithPath: environment["APP_LIFECYCLE_SUPPORT_DIR"] ?? "", isDirectory: true)) + "/"
        guard let app = hostBundle?.bundleURL, real(app).hasPrefix(support) else {
            return "隔离运行只替换隔离目录（APP_LIFECYCLE_SUPPORT_DIR）里的 App，不替换这一个；未执行。"
        }
        return nil
    }
    /// The window may run in another folder: the file to import is named by absolute path.
    static func absolute(_ arguments: [String]) -> [String] {
        let words = positionals(arguments)
        guard arguments.first == "config", words.count == 2, words[0] == "import", let index = arguments.lastIndex(of: words[1]) else { return arguments }
        var result = arguments
        result[index] = URL(fileURLWithPath: FolioIndexConfig.expanded(words[1])).standardizedFileURL.path
        return result
    }

    // MARK: Import check

    /// The settings session.json cannot be read without. An import replaces the portable set: a key the file leaves
    /// out is removed from session.json, and without one of these the whole record no longer decodes.
    static let requiredKeys = ["settings.fontSize", "settings.contentWidth", "settings.restoreSession", "settings.imageFolder"]

    /// A value of the wrong type in session.json's settings, or a missing one, makes the whole record unreadable at
    /// the next launch (tabs and drafts would be set aside), and the shared import validates a value without knowing
    /// its key. So an import is first held to the settings panel's own limits (SessionEdits.validate) and must
    /// carry every required setting. nil: nothing to object to, or not an envelope at all, which the shared layer
    /// reports itself.
    static func importProblem(_ data: Data) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let values = object["values"] as? [String: Any] else { return nil }
        func isBool(_ value: Any) -> Bool { CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() }
        func number(_ value: Any) -> Double? { isBool(value) ? nil : (value as? NSNumber)?.doubleValue }
        var edit = SessionEdit()
        for (key, value) in values {
            switch key {
            case "file.0.settings.fontFamily":
                guard let family = value as? String else { return "正文字体须是文字（\(SessionEdits.fontFamilies.joined(separator: "、"))）" }
                edit.fontFamily = family
            case "file.0.settings.fontSize":
                guard let size = number(value) else { return "正文字号须是数字" }
                edit.fontSize = size
            case "file.0.settings.contentWidth":
                guard let width = number(value) else { return "正文宽度须是数字" }
                edit.contentWidth = width
            case "file.0.settings.restoreSession":
                guard isBool(value) else { return "启动时恢复须是 true 或 false" }
            case "file.0.settings.imageFolder":
                guard let folder = value as? String else { return "图片目录须是文字" }
                edit.imageFolder = folder
            default: continue   // not one of Folio's keys: the shared layer refuses what is outside the allowlist
            }
        }
        do { try SessionEdits.validate(edit) } catch { return error.localizedDescription }
        let missing = requiredKeys.filter { values["file.0." + $0] == nil }
        if !missing.isEmpty {
            return "配置里缺少 \(missing.joined(separator: "、"))；导入会用文件里的整组设置替换现有的，缺的项会被删掉。请导入 folio config export 导出的完整文件（只改一项用 folio settings set）"
        }
        return nil
    }
    private static func importRefusal(_ arguments: [String]) -> SessionRequests.CommandReply? {
        let words = positionals(arguments)
        guard arguments.first == "config", arguments.contains("--yes"), words.count == 2, words[0] == "import",
              let data = FileManager.default.contents(atPath: FolioIndexConfig.expanded(words[1])),
              let problem = importProblem(data) else { return nil }
        return failure(command: "config import", code: "import_rejected", message: "导入未完成，原配置已保留：" + problem, exit: 1, json: arguments.contains("--json"))
    }
    /// A refusal in the shared layer's own shape, so every lifecycle result is read the same way.
    static func failure(command: String, code: String, message: String, exit: Int32, json: Bool) -> SessionRequests.CommandReply {
        guard json else { return .init(exit: exit, out: "", err: message + "\n") }
        let body: [String: Any] = ["ok": false, "command": command, "error": ["code": code, "message": message]]
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return .init(exit: exit, out: String(decoding: data, as: UTF8.self) + "\n", err: "")
    }
}
