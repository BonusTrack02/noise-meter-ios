import Foundation

struct MeterState: Equatable, Sendable {
    var reading = NoiseReading.preview
    var isLiveActivityRunning = false
    var errorMessage: String?
}

enum MeterAction: Equatable, Sendable {
    case appeared(isLiveActivityRunning: Bool)
    case previewLevelChanged(Double)
    case liveActivityButtonTapped
    case liveActivityStarted
    case liveActivityEnded
    case liveActivityFailed(String)
}

enum MeterEffect: Equatable, Sendable {
    case none
    case startLiveActivity(NoiseReading)
    case updateLiveActivity(NoiseReading)
    case endLiveActivity
}

enum MeterReducer {
    static func reduce(state: inout MeterState, action: MeterAction) -> MeterEffect {
        switch action {
        case let .appeared(isRunning):
            state.isLiveActivityRunning = isRunning
            return .none

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

