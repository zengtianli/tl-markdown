import Foundation
import SwiftUI
import UIKit
import WebKit
import CryptoKit

/// Explicit test arguments select a private sandbox subtree before any product state is opened.
/// This entry is compiled in the ordinary Release product, not a replacement test app.
struct MobileBasicsContext {
    let root: URL
    let defaults: UserDefaults
    let defaultsDomain: String
    let phase: String
    let digest: String
    static let current: MobileBasicsContext? = {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--product-basics-self-test") else { return nil }
        guard args.count > index + 3 else { exit(2) }
        let token = args[index + 1], phase = args[index + 2], digest = args[index + 3]
        guard token.count == 32, token.allSatisfy(\.isHexDigit), ["exercise", "readback", "cleanup"].contains(phase), digest.count == 64, digest.allSatisfy(\.isHexDigit) else { exit(2) }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FolioBasics-" + token)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        setenv("APP_LIFECYCLE_SUPPORT_DIR", root.appendingPathComponent("sync").path, 1)
        setenv("APP_LIFECYCLE_CLOUD_DIR", root.appendingPathComponent("cloud").path, 1)
        let domain = "test.folio.basics." + token
        return MobileBasicsContext(root: root, defaults: UserDefaults(suiteName: domain)!, defaultsDomain: domain, phase: phase, digest: digest)
    }()
}

@MainActor enum MobileBasicsSelfTest {
    static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func reconcile(_ configuration: AppConfiguration) async -> Error? {
        await withCheckedContinuation { continuation in configuration.reconcile { continuation.resume(returning: $0) } }
    }
    static func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(25)
        while !predicate() {
            guard Date() < deadline else { throw AppUpdateError("实际产品动作未在 25 秒内完成。") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
    static func write(_ object: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
    static func run(context: MobileBasicsContext, store: MobileStore, model: MobileLifecycleModel) async {
        var checks: [String: Bool] = [:], facts: [String: Any] = [:]
        let root = context.root, prefs = MobileProductLifecycle.preferences, configuration = MobileProductLifecycle.configuration
        do {
            if context.phase == "cleanup" {
                if let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("update-before.json"))) as? [String: Any] {
                    for key in ["appUpdateOptions", "appUpdateState"] {
                        if let value = saved[key] { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
                    }
                    UserDefaults.standard.synchronize()
                    let restored: [String: Any] = ["appUpdateOptions", "appUpdateState"].reduce(into: [:]) { value, key in value[key] = UserDefaults.standard.object(forKey: key) }
                    checks["updates.test_preferences_restored"] = NSDictionary(dictionary: saved).isEqual(to: restored)
                } else { checks["updates.test_preferences_restored"] = false }
                context.defaults.removePersistentDomain(forName: context.defaultsDomain)
                context.defaults.synchronize()
                checks["settings.test_domain_removed"] = context.defaults.persistentDomain(forName: context.defaultsDomain)?.isEmpty ?? true
            } else if context.phase == "readback" {
                let expected = try Data(contentsOf: root.appendingPathComponent("expected.json"))
                checks["settings.persisted_readback"] = expected == (try Data(contentsOf: prefs.url)) && prefs.value.fontSize == 23
                checks["shortcuts.persisted_readback"] = prefs.value.shortcutsEnabled
                checks["updates.persisted_options"] = AppUpdatePreferences.options(model.bundleID).automaticCheck
                checks["icloud.persisted_disabled"] = !configuration.enabled
                let work = try DocumentWorkspace(directory: root)
                checks["updates.new_process_preserves_draft"] = work.snapshot.documents.contains { $0.text == "unsaved basics draft" && $0.dirty }
            } else {
                let original: [String: Any] = ["appUpdateOptions", "appUpdateState"].reduce(into: [:]) { value, key in value[key] = UserDefaults.standard.object(forKey: key) }
                try write(original, to: root.appendingPathComponent("update-before.json"))
                model.start()
                let controller = MobileSettingsController(model: model, preferences: prefs)
                controller.loadViewIfNeeded(); controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 1000)
                controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
                controller.font.value = 22; controller.font.sendActions(for: .valueChanged)
                controller.width.value = 700; controller.width.sendActions(for: .valueChanged)
                let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { controller.view.layer.render(in: $0.cgContext) }
                try image.pngData()!.write(to: root.appendingPathComponent("settings.png"))
                checks["settings.interaction"] = prefs.value.fontSize == 22 && prefs.value.contentWidth == 700 && controller.font.window == nil && controller.font.allTargets.contains(controller)
                facts["settings_view"] = ["width": controller.view.bounds.width, "height": controller.view.bounds.height, "attached_to_window": controller.view.window != nil]
                let before = try Data(contentsOf: prefs.url)
                var invalid = prefs.value; invalid.fontSize = 100
                var rejected = false
                do { try prefs.save(invalid) } catch { rejected = true }
                var rejectedImport = false
                do { try configuration.importData(Data("{\"version\":1,\"product\":\"other\",\"values\":{}}".utf8)) } catch { rejectedImport = true }
                let afterInvalid = try Data(contentsOf: prefs.url)
                checks["settings.error_preserves_data"] = rejected && rejectedImport && before == afterInvalid && prefs.value.fontSize == 22

                // Actual production WebKit settings bridge must change the rendered document's CSS.
                try store.workspace.newDocument(text: "# Reading settings\nFixture only")
                store.refresh()
                let editor = MobileEditor(store: store, document: store.active!, reading: true, editorID: "basics")
                let coordinator = editor.makeCoordinator()
                let web = editor.makeWebView(coordinator: coordinator)
                web.frame = CGRect(x: 0, y: 0, width: 390, height: 500)
                try await waitUntil { coordinator.ready }
                let rendered = try await web.evaluateJavaScript("getComputedStyle(document.documentElement).getPropertyValue('--font-size').trim()") as? String
                checks["settings.real_editor_preference"] = rendered == "22px"
                web.stopLoading(); web.configuration.userContentController.removeScriptMessageHandler(forName: "editor")
                store.unregisterEditor(scene: "basics", token: coordinator.owner)

                let file = root.appendingPathComponent("shortcut.md")
                try Data("disk original".utf8).write(to: file)
                _ = try store.workspace.open(file)
                let document = store.workspace.active!
                try store.workspace.update(id: document.id, text: "unsaved basics draft", selection: 0, scroll: 0)
                try Data("disk after reload".utf8).write(to: file)
                store.refresh()
                await MobileReloadShortcut.perform(store: store, editorID: "shortcut")
                checks["shortcuts.action_path"] = store.active?.text == "disk after reload" && store.documents.contains { $0.text == "unsaved basics draft" && $0.dirty }
                controller.shortcuts.isOn = false; controller.shortcuts.sendActions(for: .valueChanged)
                try Data("disk while disabled".utf8).write(to: file)
                await MobileReloadShortcut.perform(store: store, editorID: "shortcut")
                let disabled = store.active?.text == "disk after reload" && !prefs.value.shortcutsEnabled
                controller.shortcuts.isOn = true; controller.shortcuts.sendActions(for: .valueChanged)
                await MobileReloadShortcut.perform(store: store, editorID: "shortcut")
                checks["shortcuts.disable_restore"] = disabled && prefs.value.shortcutsEnabled && store.active?.text == "disk while disabled"
                try Data("reserved must not reload".utf8).write(to: file)
                await MobileReloadShortcut.perform(store: store, editorID: "shortcut", key: "q", modifiers: .command)
                checks["shortcuts.conflict_or_reserved_keys"] = store.active?.text == "disk while disabled" && !MobileReloadShortcut.accepts("r", modifiers: .command, enabled: true)

                // Real shared engine, isolated cloud directory and actual atomic files.
                controller.cloud.isOn = true; controller.cloud.sendActions(for: .valueChanged)
                let pushError = await reconcile(configuration)
                let cloud = root.appendingPathComponent("cloud/folio-mobile.json")
                var envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: cloud)) as! [String: Any]
                var remote = prefs.value; remote.fontSize = 24
                let remoteObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(remote))
                envelope["values"] = ["file.0.reading": remoteObject]
                try write(envelope, to: cloud)
                let pullError = await reconcile(configuration)
                prefs.reload()
                checks["icloud.push_pull"] = pushError == nil && pullError == nil && prefs.value.fontSize == 24 && model.cloudEnabled
                let goodCloud = try Data(contentsOf: cloud), goodLocal = try Data(contentsOf: prefs.url)
                try Data("{broken".utf8).write(to: cloud)
                let corruptError = await reconcile(configuration)
                let afterCorruptLocal = try Data(contentsOf: prefs.url), afterCorruptCloud = try Data(contentsOf: cloud)
                let retained = goodLocal == afterCorruptLocal && afterCorruptCloud == Data("{broken".utf8)
                try goodCloud.write(to: cloud, options: .atomic)
                let recovered = await reconcile(configuration)
                checks["icloud.conflict_or_corrupt_recovery"] = corruptError != nil && retained && recovered == nil
                let cloudDir = root.appendingPathComponent("cloud"), backupCloud = root.appendingPathComponent("cloud-offline")
                try FileManager.default.moveItem(at: cloudDir, to: backupCloud)
                try Data("unavailable".utf8).write(to: cloudDir)
                let offlineError = await reconcile(configuration)
                var local = prefs.value; local.fontSize = 23; try prefs.save(local)
                let usableLocal = prefs.value.fontSize == 23 && store.documents.contains { $0.text == "unsaved basics draft" }
                controller.cloud.isOn = false; controller.cloud.sendActions(for: .valueChanged)
                _ = await reconcile(configuration)
                try FileManager.default.removeItem(at: cloudDir); try FileManager.default.moveItem(at: backupCloud, to: cloudDir)
                let unchangedCloud = goodCloud == (try Data(contentsOf: cloud))
                checks["icloud.unavailable_local_fallback"] = offlineError != nil && usableLocal
                checks["icloud.disable_preserves_data"] = !configuration.enabled && unchangedCloud && prefs.value.fontSize == 23 && store.documents.contains { $0.text == "unsaved basics draft" }
                facts["icloud_transport"] = "shared production AppConfiguration via isolated directory; Apple KVS cross-device transport not tested"

                controller.automatic.isOn = true; controller.automatic.sendActions(for: .valueChanged)
                let dataBeforeUpdates = try Data(contentsOf: prefs.url)
                try store.workspace.persist()
                let sessionBeforeUpdates = try Data(contentsOf: root.appendingPathComponent("session.json"))
                // First query the real App Store endpoint through the product's actual model.
                // An unpublished/regional listing must report failure, never "latest".
                controller.check.sendActions(for: .touchUpInside)
                try await waitUntil { !model.checking }
                let storeState = AppUpdatePreferences.status(model.bundleID, source: .appStore(id: MobileProductLifecycle.storeID))
                let history = storeState["history"] as? [String: Any] ?? [:]
                checks["updates.real_store_check"] = history["last_attempt_at"] != nil && (model.release != nil || model.updateStatus.contains("检查未完成"))
                facts["app_store_live_status"] = model.updateStatus
                facts["app_store_live_readback"] = storeState
                // Exercise update success and unavailable/corrupt recovery with real on-disk
                // test feed I/O in the same shared engine. No network mock or replacement checker.
                let directory = try AppUpdateChecker.privateDirectory(bundleID: model.bundleID, channel: "basics")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let package = directory.appendingPathComponent("fixture.zip"), feed = directory.appendingPathComponent("release.json")
                let packageBytes = Data("isolated check-only fixture; never installed".utf8)
                try packageBytes.write(to: package)
                let manifest: [String: Any] = ["version": "99.0.0", "build": "1", "bundle_id": model.bundleID,
                    "channel": "basics", "filename": "fixture.zip", "sha256": sha(packageBytes), "size_bytes": packageBytes.count]
                try write(manifest, to: feed)
                let testModel = MobileLifecycleModel(productID: "folio-mobile", channel: .privateCloud(channel: "basics"), configuration: nil)
                let testController = MobileSettingsController(model: testModel, preferences: prefs)
                testController.loadViewIfNeeded()
                testController.check.sendActions(for: .touchUpInside)
                try await waitUntil { !testModel.checking }
                checks["updates.check_result"] = testModel.release?.version == "99.0.0" && testModel.release?.bundleID == model.bundleID && testModel.updateStatus.contains("发现新版本") && checks["updates.real_store_check"] == true
                try FileManager.default.removeItem(at: feed)
                testController.check.sendActions(for: .touchUpInside)
                try await waitUntil { !testModel.checking }
                let unavailable = testModel.release == nil && testModel.updateStatus.contains("检查未完成")
                try Data("{broken".utf8).write(to: feed)
                testController.check.sendActions(for: .touchUpInside)
                try await waitUntil { !testModel.checking }
                let corrupt = testModel.release == nil && testModel.updateStatus.contains("检查未完成")
                try write(manifest, to: feed)
                testController.check.sendActions(for: .touchUpInside)
                try await waitUntil { !testModel.checking }
                checks["updates.failure_recovery"] = unavailable && corrupt && testModel.release?.version == "99.0.0"
                var opened: URL?
                controller.openURL = { opened = $0 }; controller.store.sendActions(for: .touchUpInside)
                checks["updates.options_or_store_entry"] = AppUpdatePreferences.options(model.bundleID).automaticCheck && opened?.absoluteString == "https://apps.apple.com/app/id" + MobileProductLifecycle.storeID
                let afterUpdates = try Data(contentsOf: prefs.url), sessionAfterUpdates = try Data(contentsOf: root.appendingPathComponent("session.json"))
                checks["updates.data_preservation"] = dataBeforeUpdates == afterUpdates && sessionBeforeUpdates == sessionAfterUpdates && store.documents.contains { $0.text == "unsaved basics draft" }
                facts["test_feed_status"] = testModel.updateStatus
                try Data(contentsOf: prefs.url).write(to: root.appendingPathComponent("expected.json"), options: .atomic)
                checks["settings.detached_native_view"] = controller.view.window == nil
            }
        } catch { facts["error"] = error.localizedDescription; checks["settings.execution_completed"] = false }
        let failed = checks.filter { !$0.value }.map(\.key).sorted()
        let result: [String: Any] = ["schema_version": 1, "app_id": "folio", "spec_digest": context.digest, "phase": context.phase,
            "bundle_id": Bundle.main.bundleIdentifier ?? "", "version": model.version, "build": model.build,
            "checks": checks, "failed": failed, "facts": facts]
        try? write(result, to: root.appendingPathComponent(context.phase + ".json"))
        // The host retrieves these files, checks completeness and terminates only this simulated process.
        LaneSignal.ready("product-basics-" + context.phase)
    }
}
