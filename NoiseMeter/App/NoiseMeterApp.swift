import SwiftUI

@main
struct NoiseMeterApp: App {
    @State private var store = MeterStore(
        liveActivity: SystemLiveActivityClient(),
        microphonePermission: SystemMicrophonePermissionClient()
    )

    var body: some Scene {
        WindowGroup {
            MeterView(store: store)
        }
    }
}

