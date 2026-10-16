import SwiftUI

struct MeterView: View {
    @Environment(\.scenePhase) private var scenePhase

    let store: MeterStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    readingCard
                    measurementControl
                    liveActivityControl
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Noise Meter")
        }
        .task {
            await store.synchronize()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }

            Task {
                await store.synchronize()
            }
        }
        .alert(
            "마이크 권한이 필요합니다",
            isPresented: Binding(
                get: { store.state.isMicrophoneSettingsAlertPresented },
                set: { isPresented in
                    guard !isPresented else { return }
                    Task { await store.send(.microphoneSettingsAlertDismissed) }
                }
            )
        ) {
            Button("취소", role: .cancel) {}
            Button("설정 열기") {
                Task { await store.send(.openApplicationSettingsButtonTapped) }
            }
        } message: {
            Text("소음 측정을 시작하려면 설정에서 마이크 접근을 허용해 주세요.")
        }
    }

    private var readingCard: some View {
        VStack(spacing: 18) {
            Label("차량 실내 소음", systemImage: "waveform")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(currentReadingText)
                    .font(.system(size: 72, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text("dB")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            Text(measurementStatusTitle)
                .font(.headline)
                .foregroundStyle(measurementStatusColor)

            HStack {
                metric(title: "평균", value: store.state.reading.average)
                Divider()
                metric(title: "최대", value: store.state.reading.peak)
            }
            .frame(height: 48)

            Text("기본 보정값을 적용한 근사치입니다.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.background, in: .rect(cornerRadius: 24))
    }

    private var measurementControl: some View {
        VStack(spacing: 12) {
            Button {
                Task { await store.send(.measurementButtonTapped) }
            } label: {
                Label(measurementButtonTitle, systemImage: measurementButtonSymbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(store.state.isMeasuring ? .red : .accentColor)
            .disabled(isMeasurementControlBusy)

            if let errorMessage = store.state.measurementErrorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var liveActivityControl: some View {
        VStack(spacing: 12) {
            Button {
                Task { await store.send(.liveActivityButtonTapped) }
            } label: {
                Label(
                    store.state.isLiveActivityRunning ? "Live Activity 종료" : "Live Activity 시작",
                    systemImage: store.state.isLiveActivityRunning ? "stop.circle.fill" : "play.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!store.state.isMeasuring && !store.state.isLiveActivityRunning)

            if let errorMessage = store.state.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func metric(title: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(metricText(value))
                .font(.title3.monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }

    private var bandColor: Color {
        switch store.state.reading.band {
        case .quiet: .green
        case .moderate: .orange
        case .loud: .red
        }
    }

    private var measurementStatusTitle: String {
        guard store.state.measurementSampleCount > 0 else {
            return store.state.isMeasuring ? "측정 중" : "대기 중"
        }
        return store.state.reading.band.title
    }

    private var measurementStatusColor: Color {
        store.state.measurementSampleCount > 0 ? bandColor : .secondary
    }

    private var measurementButtonTitle: String {
        if store.state.isRequestingMicrophonePermission {
            return "권한 확인 중"
        }
        if store.state.isStartingMeasurement {
            return "측정 준비 중"
        }
        return store.state.isMeasuring ? "측정 중지" : "측정 시작"
    }

    private var measurementButtonSymbol: String {
        if store.state.isRequestingMicrophonePermission {
            return "ellipsis"
        }
        if store.state.isStartingMeasurement {
            return "waveform"
        }
        return store.state.isMeasuring ? "stop.circle.fill" : "mic.fill"
    }

    private var isMeasurementControlBusy: Bool {
        store.state.isRequestingMicrophonePermission || store.state.isStartingMeasurement
    }

    private var currentReadingText: String {
        guard store.state.measurementSampleCount > 0 else { return "--" }
        return store.state.reading.current.formatted(
            .number.precision(.fractionLength(0))
        )
    }

    private func metricText(_ value: Double) -> String {
        guard store.state.measurementSampleCount > 0 else { return "--" }
        return value.formatted(.number.precision(.fractionLength(0)))
    }
}

#Preview {
    MeterView(
        store: MeterStore(
            liveActivity: PreviewLiveActivityClient(),
            microphonePermission: PreviewMicrophonePermissionClient(),
            microphoneMeter: PreviewMicrophoneMeterClient()
        )
    )
}

@MainActor
private final class PreviewLiveActivityClient: LiveActivityClient {
    var isRunning = false

    func start(reading: NoiseReading) async throws {
        isRunning = true
    }

    func update(reading: NoiseReading) async {}

    func end() async {
        isRunning = false
    }
}

@MainActor
private final class PreviewMicrophonePermissionClient: MicrophonePermissionClient {
    var authorizationStatus: MicrophonePermission = .undetermined

    func requestAuthorization() async -> MicrophonePermission {
        authorizationStatus = .granted
        return authorizationStatus
    }

    func openSettings() async {}
}

@MainActor
private final class PreviewMicrophoneMeterClient: MicrophoneMeterClient {
    func start() async throws -> AsyncStream<Double> {
        AsyncStream { continuation in
            continuation.yield(72)
        }
    }

    func stop() async {}
}

