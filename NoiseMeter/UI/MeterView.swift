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
                    previewControl
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
                Text(store.state.reading.current, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 72, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text("dB")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            Text(store.state.reading.band.title)
                .font(.headline)
                .foregroundStyle(bandColor)

            HStack {
                metric(title: "평균", value: store.state.reading.average)
                Divider()
                metric(title: "최대", value: store.state.reading.peak)
            }
            .frame(height: 48)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.background, in: .rect(cornerRadius: 24))
    }

    private var previewControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Live Activity 미리보기 값")
                    .font(.headline)
                Spacer()
                Text(store.state.reading.current, format: .number.precision(.fractionLength(0)))
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { store.state.reading.current },
                    set: { value in
                        Task { await store.send(.previewLevelChanged(value)) }
                    }
                ),
                in: 30...110,
                step: 1
            )

            Text("마이크 측정 엔진을 연결하기 전까지 ActivityKit 표시와 갱신을 검증하기 위한 개발용 입력입니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.background, in: .rect(cornerRadius: 20))
    }

    private var measurementControl: some View {
        Button {
            Task { await store.send(.measurementButtonTapped) }
        } label: {
            Label(measurementButtonTitle, systemImage: measurementButtonSymbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(store.state.isMeasuring ? .red : .accentColor)
        .disabled(store.state.isRequestingMicrophonePermission)
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
            Text(value, format: .number.precision(.fractionLength(0)))
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

    private var measurementButtonTitle: String {
        if store.state.isRequestingMicrophonePermission {
            return "권한 확인 중"
        }
        return store.state.isMeasuring ? "측정 중지" : "측정 시작"
    }

    private var measurementButtonSymbol: String {
        if store.state.isRequestingMicrophonePermission {
            return "ellipsis"
        }
        return store.state.isMeasuring ? "stop.circle.fill" : "mic.fill"
    }
}

#Preview {
    MeterView(
        store: MeterStore(
            liveActivity: PreviewLiveActivityClient(),
            microphonePermission: PreviewMicrophonePermissionClient()
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

