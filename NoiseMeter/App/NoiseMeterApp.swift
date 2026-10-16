import SwiftUI

@main
struct NoiseMeterApp: App {
    @State private var store = MeterStore(
        liveActivity: SystemLiveActivityClient(),
        microphonePermission: SystemMicrophonePermissionClient(),
        microphoneMeter: SystemMicrophoneMeterClient()
    )

    var body: some Scene {
        WindowGroup {
            MeterView(store: store)
        }
    }
}

