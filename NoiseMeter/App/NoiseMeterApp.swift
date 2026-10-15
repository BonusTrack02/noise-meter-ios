import SwiftUI

@main
struct NoiseMeterApp: App {
    @State private var store = MeterStore(
        liveActivity: SystemLiveActivityClient()
    )

    var body: some Scene {
        WindowGroup {
            MeterView(store: store)
        }
    }
}

