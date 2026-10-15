import Foundation

struct MeterState: Equatable, Sendable {
    var reading = NoiseReading.preview
    var isMeasuring = false
    var isLiveActivityRunning = false
    var microphonePermission: MicrophonePermission = .undetermined
    var isRequestingMicrophonePermission = false
    var isMicrophoneSettingsAlertPresented = false
    var errorMessage: String?
}

enum MicrophonePermission: Equatable, Sendable {
    case undetermined
    case denied
    case granted
}

enum MeterAction: Equatable, Sendable {
    case appeared(
        isLiveActivityRunning: Bool,
        microphonePermission: MicrophonePermission
    )
    case measurementButtonTapped
    case microphonePermissionUpdated(MicrophonePermission)
    case microphoneSettingsAlertDismissed
    case openApplicationSettingsButtonTapped
    case previewLevelChanged(Double)
    case liveActivityButtonTapped
    case liveActivityStarted
    case liveActivityEnded
    case liveActivityFailed(String)
}

enum MeterEffect: Equatable, Sendable {
    case none
    case requestMicrophonePermission
    case openApplicationSettings
    case startLiveActivity(NoiseReading)
    case updateLiveActivity(NoiseReading)
    case endLiveActivity
}

enum MeterReducer {
    static func reduce(state: inout MeterState, action: MeterAction) -> MeterEffect {
        switch action {
        case let .appeared(isRunning, microphonePermission):
            state.isLiveActivityRunning = isRunning
            state.microphonePermission = microphonePermission
            state.isRequestingMicrophonePermission = false
            if microphonePermission != .granted {
                state.isMeasuring = false
            }
            return .none

        case .measurementButtonTapped:
            if state.isMeasuring {
                state.isMeasuring = false
                return .none
            }

            switch state.microphonePermission {
            case .undetermined:
                state.isRequestingMicrophonePermission = true
                return .requestMicrophonePermission
            case .denied:
                state.isMicrophoneSettingsAlertPresented = true
                return .none
            case .granted:
                state.isMeasuring = true
                return .none
            }

        case let .microphonePermissionUpdated(permission):
            state.microphonePermission = permission
            state.isRequestingMicrophonePermission = false
            state.isMeasuring = permission == .granted
            state.isMicrophoneSettingsAlertPresented = permission == .denied
            return .none

        case .microphoneSettingsAlertDismissed:
            state.isMicrophoneSettingsAlertPresented = false
            return .none

        case .openApplicationSettingsButtonTapped:
            state.isMicrophoneSettingsAlertPresented = false
            return .openApplicationSettings

        case let .previewLevelChanged(value):
            let previousBand = state.reading.band
            state.reading = state.reading.updatingCurrent(to: value)
            guard state.isLiveActivityRunning else { return .none }

            // The client coalesces routine updates and sends band changes immediately.
            if previousBand != state.reading.band {
                return .updateLiveActivity(state.reading)
            }
            return .updateLiveActivity(state.reading)

        case .liveActivityButtonTapped:
            state.errorMessage = nil
            return state.isLiveActivityRunning
                ? .endLiveActivity
                : .startLiveActivity(state.reading)

        case .liveActivityStarted:
            state.isLiveActivityRunning = true
            return .none

        case .liveActivityEnded:
            state.isLiveActivityRunning = false
            return .none

        case let .liveActivityFailed(message):
            state.errorMessage = message
            return .none
        }
    }
}

