import SwiftUI
import UIKit
import Combine

/// The displayed settings controller is also exercised directly by the in-process acceptor.
/// Actions use the shared lifecycle model; no configuration/sync/update engine is duplicated.
@MainActor final class MobileSettingsController: UIViewController {
    let model: MobileLifecycleModel
    let preferences: MobileReadingPreferences
    let font = UIStepper(), width = UIStepper(), shortcuts = UISwitch(), cloud = UISwitch(), automatic = UISwitch()
    let check = UIButton(type: .system), store = UIButton(type: .system), transfer = UIButton(type: .system)
    let fontLabel = UILabel(), widthLabel = UILabel(), status = UILabel(), update = UILabel(), notice = UILabel()
    let stack = UIStackView()
    var showTransfer: () -> Void = {}
    var openURL: (URL) -> Void = { UIApplication.shared.open($0) }
    private var observers: Set<AnyCancellable> = []
    init(model: MobileLifecycleModel, preferences: MobileReadingPreferences) {
        self.model = model; self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        font.minimumValue = 13; font.maximumValue = 28; font.stepValue = 1
        width.minimumValue = 320; width.maximumValue = 1200; width.stepValue = 20
        row(fontLabel, font); row(widthLabel, width)
        row(label("外接键盘快捷键"), shortcuts)
        stack.addArrangedSubview(label("⌘⇧R：重新载入并保留当前草稿。只在本 App 生效；关闭后恢复触屏菜单操作。系统复制、粘贴、撤销等保留原行为。", detail: true))
        row(label("使用 iCloud 记住阅读配置"), cloud)
        stack.addArrangedSubview(label("默认关闭；只同步字号、阅读宽度与应用快捷键开关。文稿、恢复草稿、书签和权限不随配置上传。关闭保留两端已有数据。", detail: true))
        stack.addArrangedSubview(status)
        stack.addArrangedSubview(label("已安装 \(model.version) (\(model.build)) · App Store"))
        row(label("启动时自动检查更新"), automatic)
        stack.addArrangedSubview(update)
        check.setTitle("检查更新", for: .normal); stack.addArrangedSubview(check)
        store.setTitle("前往 App Store", for: .normal); stack.addArrangedSubview(store)
        transfer.setTitle("导入、导出配置…", for: .normal); stack.addArrangedSubview(transfer)
        stack.addArrangedSubview(notice)
        [status, update, notice].forEach { $0.numberOfLines = 0; $0.font = .preferredFont(forTextStyle: .footnote); $0.textColor = .secondaryLabel }
        font.addTarget(self, action: #selector(changeFont), for: .valueChanged)
        width.addTarget(self, action: #selector(changeWidth), for: .valueChanged)
        shortcuts.addTarget(self, action: #selector(changeShortcuts), for: .valueChanged)
        cloud.addTarget(self, action: #selector(changeCloud), for: .valueChanged)
        automatic.addTarget(self, action: #selector(changeAutomatic), for: .valueChanged)
        check.addTarget(self, action: #selector(checkUpdates), for: .touchUpInside)
        store.addTarget(self, action: #selector(openStore), for: .touchUpInside)
        transfer.addTarget(self, action: #selector(openTransfer), for: .touchUpInside)
        font.accessibilityIdentifier = "folio.settings.font"; width.accessibilityIdentifier = "folio.settings.width"
        shortcuts.accessibilityIdentifier = "folio.settings.shortcuts"; cloud.accessibilityIdentifier = "configuration.iCloud"
        check.accessibilityIdentifier = "update.check"; store.accessibilityIdentifier = "update.store"
        preferences.$value.sink { [weak self] _ in Task { @MainActor in self?.refresh() } }.store(in: &observers)
        model.objectWillChange.sink { [weak self] _ in Task { @MainActor in self?.refresh() } }.store(in: &observers)
        refresh()
    }
    private func label(_ text: String, detail: Bool = false) -> UILabel {
        let label = UILabel(); label.text = text; label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: detail ? .footnote : .body)
        label.textColor = detail ? .secondaryLabel : .label
        return label
    }
    private func row(_ label: UILabel, _ control: UIView) {
        let row = UIStackView(arrangedSubviews: [label, control]); row.axis = .horizontal; row.spacing = 12; row.alignment = .center
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        stack.addArrangedSubview(row)
    }
    func refresh() {
        guard isViewLoaded else { return }
        font.value = Double(preferences.value.fontSize); width.value = Double(preferences.value.contentWidth)
        fontLabel.text = "字号 \(preferences.value.fontSize)"; widthLabel.text = "阅读宽度 \(preferences.value.contentWidth)"
        shortcuts.isOn = preferences.value.shortcutsEnabled; cloud.isOn = model.cloudEnabled
        automatic.isOn = AppUpdatePreferences.options(model.bundleID).automaticCheck
        status.text = model.configurationStatus; update.text = model.updateStatus
        check.isEnabled = !model.checking; notice.text = model.notice ?? preferences.error
    }
    private func save(_ edit: (inout MobileReadingSettings) -> Void) {
        var next = preferences.value; edit(&next)
        do { try preferences.save(next); model.configuration?.reconcile() }
        catch { model.notice = error.localizedDescription }
        refresh()
    }
    @objc func changeFont() { save { $0.fontSize = Int(font.value) } }
    @objc func changeWidth() { save { $0.contentWidth = Int(width.value) } }
    @objc func changeShortcuts() { save { $0.shortcutsEnabled = shortcuts.isOn } }
    @objc func changeCloud() { model.setCloudEnabled(cloud.isOn); refresh() }
    @objc func checkUpdates() { model.checkForUpdates(); refresh() }
    @objc func changeAutomatic() {
        do { var options = AppUpdatePreferences.options(model.bundleID); options.automaticCheck = automatic.isOn; try AppUpdatePreferences.save(options, model.bundleID) }
        catch { model.notice = error.localizedDescription }
        refresh()
    }
    @objc func openStore() { if let url = model.updateURL { openURL(url) } }
    @objc func openTransfer() { showTransfer() }
}

struct MobileSettingsPanel: View {
    @ObservedObject var model: MobileLifecycleModel
    @Environment(\.dismiss) private var dismiss
    @State private var transfer = false
    var body: some View {
        NavigationStack {
            Controls(model: model, showTransfer: { transfer = true })
                .navigationTitle("设置与更新")
                .toolbar { Button("完成") { dismiss() } }
        }.sheet(isPresented: $transfer) { AppLifecycleMobilePanel(model: model) }
    }
    private struct Controls: UIViewControllerRepresentable {
        let model: MobileLifecycleModel
        let showTransfer: () -> Void
        func makeUIViewController(context: Context) -> MobileSettingsController {
            let controller = MobileSettingsController(model: model, preferences: MobileProductLifecycle.preferences)
            controller.showTransfer = showTransfer
            return controller
        }
        func updateUIViewController(_ controller: MobileSettingsController, context: Context) { controller.refresh() }
    }
}
