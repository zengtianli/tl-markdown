import Foundation

// Product allowlist and release channel; shared lifecycle code owns transfer/checking.
@MainActor
enum MobileProductLifecycle {
    static var channel: MobileUpdateChannel {
        #if os(macOS)
        return .privateCloud(channel: "private")
        #else
        return .unreleased(helpURL: nil, instructions: "移动版尚未配置正式发行渠道。项目当前只有移动构建入口；签名包需通过现有真机安装流程分发，没有可查询的商店版本。")
        #endif
    }
    static let configuration: AppConfiguration? = nil
}
