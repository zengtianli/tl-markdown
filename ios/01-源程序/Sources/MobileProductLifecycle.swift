import Foundation
import SwiftUI

// Product allowlist and release channel; shared lifecycle code owns transfer/checking.
@MainActor
enum MobileProductLifecycle {
    // ASC readback: cyou.tianli.TLMarkdown.mobile, not the Mac listing.
    static let storeID = "6819568883"
    static var channel: MobileUpdateChannel { .appStore(id: storeID) }
    static let preferences = MobileReadingPreferences(url: support.appendingPathComponent("reading.json"))
    static var support: URL {
        if let context = MobileBasicsContext.current { return context.root }
        let demo = ProcessInfo.processInfo.arguments.contains("-folio-demo")
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(demo ? "FolioMobile-Demo" : "FolioMobile", isDirectory: true)
    }
    static var defaults: UserDefaults { MobileBasicsContext.current?.defaults ?? .standard }
    static let configuration = makeConfiguration()
    static func makeConfiguration() -> AppConfiguration {
        let configuration = AppConfiguration(productID: "folio-mobile", files: [
            AppConfigurationFile(url: preferences.url, keys: ["reading"], validateValue: MobileReadingPreferences.validate)
        ], defaults: defaults)
        configuration.onChange = { Task { @MainActor in preferences.reload() } }
        return configuration
    }
    static func checkIfDue(_ model: MobileLifecycleModel) {
        if AppUpdatePreferences.due(model.bundleID) { model.checkForUpdates() }
    }
}

struct MobileReadingSettings: Codable, Equatable {
    var fontSize = 17
    var contentWidth = 820
    var shortcutsEnabled = true
}

@MainActor final class MobileReadingPreferences: ObservableObject {
    let url: URL
    @Published private(set) var value = MobileReadingSettings()
    @Published private(set) var error = ""
    init(url: URL) { self.url = url; reload() }
    nonisolated static func validate(_ value: Any) throws {
        guard let object = value as? [String: Any], Set(object.keys) == ["fontSize", "contentWidth", "shortcutsEnabled"] else {
            throw AppUpdateError("阅读配置字段不完整，原配置已保留。")
        }
        let decoded = try JSONDecoder().decode(MobileReadingSettings.self, from: JSONSerialization.data(withJSONObject: object))
        guard (13...28).contains(decoded.fontSize), (320...1200).contains(decoded.contentWidth) else {
            throw AppUpdateError("字号应为 13–28，阅读宽度应为 320–1200；原配置已保留。")
        }
    }
    func save(_ next: MobileReadingSettings) throws {
        let reading = try JSONSerialization.jsonObject(with: JSONEncoder().encode(next))
        try Self.validate(reading)
        let data = try JSONSerialization.data(withJSONObject: ["reading": reading], options: [.sortedKeys])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        value = next; error = ""
    }
    func reload() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count < 65_536, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let reading = object["reading"] else {
                throw AppUpdateError("阅读配置损坏；当前设置及原文件已保留。")
            }
            try Self.validate(reading)
            value = try JSONDecoder().decode(MobileReadingSettings.self, from: JSONSerialization.data(withJSONObject: reading)); error = ""
        } catch { self.error = error.localizedDescription }
    }
}

// One fixed application shortcut. System editing/quit/navigation keys are never registered.
enum MobileReloadShortcut {
    static let key = "r"
    static let modifiers: EventModifiers = [.command, .shift]
    static func accepts(_ key: String, modifiers: EventModifiers, enabled: Bool) -> Bool {
        enabled && key == self.key && modifiers == self.modifiers
    }
    @MainActor static func perform(store: MobileStore, editorID: String, key: String = key,
                                   modifiers: EventModifiers = modifiers) async {
        guard accepts(key, modifiers: modifiers, enabled: MobileProductLifecycle.preferences.value.shortcutsEnabled) else { return }
        await store.reload(editorID: editorID)
    }
}
