import ActivityKit
import Foundation
import Observation

@MainActor
protocol LiveActivityClient: AnyObject {
    var isRunning: Bool { get }

    func start(reading: NoiseReading) async throws
    func update(reading: NoiseReading) async
    func end() async
}

@MainActor
final class SystemLiveActivityClient: LiveActivityClient {
    private let updateInterval: Duration
    private let clock = ContinuousClock()

    private var activityID: String?
    private var lastUpdate: ContinuousClock.Instant?
    private var lastBand: NoiseBand?
    private var pendingReading: NoiseReading?
    private var pendingUpdateTask: Task<Void, Never>?

    init(updateInterval: Duration = .seconds(3)) {
        self.updateInterval = updateInterval
        activityID = Activity<NoiseActivityAttributes>.activities.first?.id
    }

    var isRunning: Bool {
        activityID != nil
    }

    func start(reading: NoiseReading) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw LiveActivityError.disabled
        }

        if let activityID {
            if await Self.updateActivity(id: activityID, reading: reading) {
                lastUpdate = clock.now
                lastBand = reading.band
                return
            }

            self.activityID = nil
        }

        let attributes = NoiseActivityAttributes(
            sessionID: UUID(),
            title: "차량 실내 소음"
        )

        let activity = try Activity.request(
            attributes: attributes,
            content: content(for: reading),
            pushType: nil
        )
        activityID = activity.id
        lastUpdate = clock.now
        lastBand = reading.band
    }

    func update(reading: NoiseReading) async {
        guard activityID != nil else { return }

        let bandChanged = lastBand != reading.band
        let canUpdateNow = lastUpdate.map {
            $0.duration(to: clock.now) >= updateInterval
        } ?? true

        if bandChanged || canUpdateNow {
            pendingUpdateTask?.cancel()
            pendingUpdateTask = nil
            pendingReading = nil
            await flush(reading)
            return
        }

        pendingReading = reading
        guard pendingUpdateTask == nil else { return }

        let elapsed = lastUpdate?.duration(to: clock.now) ?? .zero
        let remainingDelay = updateInterval - elapsed

        pendingUpdateTask = Task { [weak self] in
            try? await Task.sleep(for: remainingDelay)
            guard !Task.isCancelled else { return }
            await self?.flushPendingReading()
        }
    }

    func end() async {
        pendingUpdateTask?.cancel()
        pendingUpdateTask = nil
        pendingReading = nil

        guard let activityID else { return }
        await Self.endActivity(id: activityID)

        self.activityID = nil
        lastUpdate = nil
        lastBand = nil
    }

    private func flushPendingReading() async {
        pendingUpdateTask = nil
        guard let pendingReading else { return }
        self.pendingReading = nil
        await flush(pendingReading)
    }

    private func flush(_ reading: NoiseReading) async {
        guard let activityID else { return }
        guard await Self.updateActivity(id: activityID, reading: reading) else {
            self.activityID = nil
            lastUpdate = nil
            lastBand = nil
            return
        }

        lastUpdate = clock.now
        lastBand = reading.band
    }

    private nonisolated static func updateActivity(
        id: String,
        reading: NoiseReading
    ) async -> Bool {
        guard let activity = Activity<NoiseActivityAttributes>.activities.first(where: { $0.id == id }) else {
            return false
        }

        let content = ActivityContent(
            state: NoiseActivityAttributes.ContentState(reading: reading),
            staleDate: .now.addingTimeInterval(10)
        )
        await activity.update(content)
        return true
    }

    private nonisolated static func endActivity(id: String) async {
        guard let activity = Activity<NoiseActivityAttributes>.activities.first(where: { $0.id == id }) else {
            return
        }

        await activity.end(nil, dismissalPolicy: .immediate)
    }

    private func content(for reading: NoiseReading) -> ActivityContent<NoiseActivityAttributes.ContentState> {
        ActivityContent(
            state: .init(reading: reading),
            staleDate: .now.addingTimeInterval(10)
        )
    }
}

enum LiveActivityError: LocalizedError {
    case disabled

    var errorDescription: String? {
        switch self {
        case .disabled:
            "설정에서 이 앱의 Live Activity를 허용해 주세요."
        }
    }
}

@MainActor
@Observable
final class MeterStore {
    private(set) var state = MeterState()

    private let liveActivity: any LiveActivityClient
    private let microphonePermission: any MicrophonePermissionClient
    private let microphoneMeter: any MicrophoneMeterClient
    private var measurementTask: Task<Void, Never>?

    init(
        liveActivity: any LiveActivityClient,
        microphonePermission: any MicrophonePermissionClient,
        microphoneMeter: any MicrophoneMeterClient
    ) {
        self.liveActivity = liveActivity
        self.microphonePermission = microphonePermission
        self.microphoneMeter = microphoneMeter
    }

    func send(_ action: MeterAction) async {
        let effect = MeterReducer.reduce(state: &state, action: action)

        switch effect {
        case .none:
            break

        case .requestMicrophonePermission:
            let permission = await microphonePermission.requestAuthorization()
            await send(.microphonePermissionUpdated(permission))

        case .openApplicationSettings:
            await microphonePermission.openSettings()

        case .startMeasurement:
            do {
                let measurements = try await microphoneMeter.start()
                await send(.measurementStarted)

                measurementTask?.cancel()
                measurementTask = Task { [weak self] in
                    for await decibels in measurements {
                        guard !Task.isCancelled else { break }
                        await self?.send(.measurementReceived(decibels))
                    }

                    guard !Task.isCancelled else { return }
                    await self?.send(.measurementStopped)
                }
            } catch {
                await microphoneMeter.stop()
                await send(.measurementFailed(error.localizedDescription))
            }

        case let .stopMeasurement(endLiveActivity):
            measurementTask?.cancel()
            measurementTask = nil
            await microphoneMeter.stop()
            await send(.measurementStopped)

            if endLiveActivity {
                await liveActivity.end()
                await send(.liveActivityEnded)
            }

        case let .startLiveActivity(reading):
            do {
                try await liveActivity.start(reading: reading)
                await send(.liveActivityStarted)
            } catch {
                await send(.liveActivityFailed(error.localizedDescription))
            }

        case let .updateLiveActivity(reading):
            await liveActivity.update(reading: reading)

        case .endLiveActivity:
            await liveActivity.end()
            await send(.liveActivityEnded)
        }
    }

    func synchronize() async {
        await send(
            .appeared(
                isLiveActivityRunning: liveActivity.isRunning,
                microphonePermission: microphonePermission.authorizationStatus
            )
        )
    }
}

