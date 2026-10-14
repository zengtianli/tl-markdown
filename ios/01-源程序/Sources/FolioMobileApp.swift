import SwiftUI

@main struct FolioMobileApp: App {
    @StateObject private var store = MobileStore()
    @StateObject private var lifecycle = MobileLifecycleModel(productID: "folio-mobile", channel: MobileProductLifecycle.channel,
        configuration: MobileProductLifecycle.configuration)
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            if let context = MobileBasicsContext.current {
                Color.clear.task { await MobileBasicsSelfTest.run(context: context, store: store, model: lifecycle) }
            } else {
                ContentView(store: store)
                    .environmentObject(lifecycle)
                    .task { lifecycle.start(); MobileProductLifecycle.checkIfDue(lifecycle); LaneSignal.applyOrientation(); LaneSignal.applyWindowFrame() }
                    .onChange(of: phase) { _, next in if next == .active { MobileProductLifecycle.checkIfDue(lifecycle) } }
            }
        }
        #if os(visionOS)
        .defaultSize(width: 1000, height: 760)
        #endif
    }
}
