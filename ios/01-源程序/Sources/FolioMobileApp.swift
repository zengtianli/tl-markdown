import SwiftUI

@main struct FolioMobileApp: App {
    @StateObject private var store = MobileStore()
    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .appLifecycleMobile(productID: "folio-mobile", channel: MobileProductLifecycle.channel, configuration: MobileProductLifecycle.configuration)
                .task { LaneSignal.applyOrientation(); LaneSignal.applyWindowFrame() }
        }
        #if os(visionOS)
        .defaultSize(width: 1000, height: 760)
        #endif
    }
}
