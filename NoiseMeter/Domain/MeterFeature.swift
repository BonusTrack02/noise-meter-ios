import Foundation

struct NoiseMeasurementProcessor: Equatable, Sendable {
    private(set) var reading = NoiseReading.zero
    private(set) var sampleCount = 0
    private var laeqAccumulator = LAeqAccumulator()

    var measuredDuration: TimeInterval {
        laeqAccumulator.measuredDuration
    }

    @discardableResult
    mutating func process(_ sample: SoundLevelSample) -> NoiseReading? {
        guard let laeq = laeqAccumulator.add(sample) else { return nil }
        reading = reading.addingMeasurement(
            sample,
            previousSampleCount: sampleCount,
            laeq: laeq
        )
        sampleCount += 1
        return reading
    }
}

struct MeasurementDisplayCadence: Equatable, Sendable {
    static let defaultInterval: TimeInterval = 0.1

    private let interval: TimeInterval
    private var nextUpdateTime: TimeInterval = 0

    init(interval: TimeInterval = Self.defaultInterval) {
        self.interval = interval.isFinite && interval > 0
            ? interval
            : Self.defaultInterval
    }

    mutating func shouldPublish(at measuredDuration: TimeInterval) -> Bool {
        guard measuredDuration.isFinite,
              measuredDuration >= nextUpdateTime
        else {
            return false
        }

        repeat {
            nextUpdateTime += interval
        } while nextUpdateTime <= measuredDuration
        return true
    }
}

struct MeterState: Equatable, Sendable {
    var reading = NoiseReading.zero
    var measurementSampleCount = 0
    var isMeasuring = false
    var isStartingMeasurement = false
    var isStoppingMeasurement = false
    var isMeasurementStartPending = false
    var isLiveActivityRunning = false
    var microphonePermission: MicrophonePermission = .undetermined
    var isRequestingMicrophonePermission = false
    var isMicrophoneSettingsAlertPresented = false
    var measurementErrorMessage: String?
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
    case measurementStarted
    case measurementStopped
    case measurementUpdated(reading: NoiseReading, sampleCount: Int)
    case measurementFailed(String)
    case liveActivityButtonTapped
    case liveActivityStarted
    case liveActivityEnded
    case liveActivityFailed(String)
}

enum MeterEffect: Equatable, Sendable {
    case none
    case requestMicrophonePermission
    case openApplicationSettings
    case startMeasurement
    case stopMeasurement(endLiveActivity: Bool)
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
            if microphonePermission != .granted {
                let shouldStopMeasurement = state.isMeasuring || state.isStartingMeasurement
                state.isMeasuring = false
                state.isStartingMeasurement = false
                state.isStoppingMeasurement = false
                return shouldStopMeasurement
                    ? .stopMeasurement(endLiveActivity: state.isLiveActivityRunning)
                    : .none
            }
            return .none

        case .measurementButtonTapped:
            if state.isMeasuring {
                guard !state.isStoppingMeasurement else { return .none }
                state.isStoppingMeasurement = true
                return .stopMeasurement(endLiveActivity: state.isLiveActivityRunning)
            }

            guard !state.isStartingMeasurement,
                  !state.isRequestingMicrophonePermission
            else { return .none }

            state.measurementErrorMessage = nil

            switch state.microphonePermission {
            case .undetermined:
                state.isMeasurementStartPending = true
                state.isRequestingMicrophonePermission = true
                return .requestMicrophonePermission
            case .denied:
                state.isMicrophoneSettingsAlertPresented = true
                return .none
            case .granted:
                state.isStartingMeasurement = true
                return .startMeasurement
            }

        case let .microphonePermissionUpdated(permission):
            state.microphonePermission = permission
            state.isRequestingMicrophonePermission = false

            guard state.isMeasurementStartPending else { return .none }
            state.isMeasurementStartPending = false

            if permission == .granted {
                state.isStartingMeasurement = true
                return .startMeasurement
            }

            state.isMicrophoneSettingsAlertPresented = permission == .denied
            return .none

        case .microphoneSettingsAlertDismissed:
            state.isMicrophoneSettingsAlertPresented = false
            return .none

        case .openApplicationSettingsButtonTapped:
            state.isMicrophoneSettingsAlertPresented = false
            return .openApplicationSettings

        case .measurementStarted:
            state.reading = .zero
            state.measurementSampleCount = 0
            state.isStartingMeasurement = false
            state.isStoppingMeasurement = false
            state.isMeasuring = true
            return .none

        case .measurementStopped:
            state.isStartingMeasurement = false
            state.isStoppingMeasurement = false
            state.isMeasuring = false
            return .none

        case let .measurementUpdated(reading, sampleCount):
            guard state.isMeasuring else { return .none }
            state.reading = reading
            state.measurementSampleCount = sampleCount
            guard state.isLiveActivityRunning else { return .none }
            return .updateLiveActivity(state.reading)

        case let .measurementFailed(message):
            state.isStartingMeasurement = false
            state.isStoppingMeasurement = false
            state.isMeasuring = false
            state.measurementErrorMessage = message
            return .none

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

