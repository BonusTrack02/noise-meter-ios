import AVFAudio
import UIKit

@MainActor
protocol MicrophonePermissionClient: AnyObject {
    var authorizationStatus: MicrophonePermission { get }

    func requestAuthorization() async -> MicrophonePermission
    func openSettings() async
}

@MainActor
final class SystemMicrophonePermissionClient: MicrophonePermissionClient {
    var authorizationStatus: MicrophonePermission {
        Self.permission(from: AVAudioApplication.shared.recordPermission)
    }

    func requestAuthorization() async -> MicrophonePermission {
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        return granted ? .granted : .denied
    }

    func openSettings() async {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        await UIApplication.shared.open(settingsURL)
    }

    private static func permission(
        from permission: AVAudioApplication.recordPermission
    ) -> MicrophonePermission {
        switch permission {
        case .undetermined:
            .undetermined
        case .denied:
            .denied
        case .granted:
            .granted
        @unknown default:
            .denied
        }
    }
}
