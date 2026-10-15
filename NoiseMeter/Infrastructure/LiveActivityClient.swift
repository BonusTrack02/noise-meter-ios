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

    private var activity: Activity<NoiseActivityAttributes>?
    private var lastUpdate: ContinuousClock.Instant?
    private var lastBand: NoiseBand?
    private var pendingReading: NoiseReading?
    private var pendingUpdateTask: Task<Void, Never>?

    init(updateInterval: Duration = .seconds(3)) {
        self.updateInterval = updateInterval
        activity = Activity<NoiseActivityAttributes>.activities.first
    }

    var isRunning: Bool {
        activity != nil
    }

    func start(reading: NoiseReading) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw LiveActivityError.disabled
        }

        if let activity {
            await activity.update(content(for: reading))
            return
        }

        let attributes = NoiseActivityAttributes(
            sessionID: UUID(),
            title: "차량 실내 소음"
        )

        activity = try Activity.request(
            attributes: attributes,
            content: content(for: reading),
            pushType: nil
        )
        lastUpdate = clock.now
        lastBand = reading.band
    }

    func update(reading: NoiseReading) async {
        guard activity != nil else { return }

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

        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)

        self.activity = nil
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
        guard let activity else { return }
        await activity.update(content(for: reading))
        lastUpdate = clock.now
        lastBand = reading.band
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

    init(liveActivity: any LiveActivityClient) {
        self.liveActivity = liveActivity
    }

    func send(_ action: MeterAction) async {
        let effect = MeterReducer.reduce(state: &state, action: action)

        switch effect {
        case .none:
            break

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
        await send(.appeared(isLiveActivityRunning: liveActivity.isRunning))
    }
}

