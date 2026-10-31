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
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Noise Meter")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView(store: store)
                    } label: {
                        Label("설정", systemImage: "gearshape")
                    }
                }
            }
        }
        .task {
            await store.synchronize()
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task {
                await handleScenePhase(newPhase)
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
                Text("dBA")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            Text(measurementStatusTitle)
                .font(.headline)
                .foregroundStyle(measurementStatusColor)

            HStack {
                metric(title: "최소 dBA", value: store.state.reading.minimum)
                Divider()
                metric(title: "LAeq", value: store.state.reading.laeq)
                Divider()
                metric(title: "최대 dBA", value: store.state.reading.maximum)
            }
            .frame(height: 48)

            Text("기본 보정값을 적용한 추정 dBA/LAeq입니다.")
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
        if store.state.isStoppingMeasurement {
            return "측정 종료 중"
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
        store.state.isRequestingMicrophonePermission
            || store.state.isStartingMeasurement
            || store.state.isStoppingMeasurement
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

    private func handleScenePhase(_ phase: ScenePhase) async {
        switch phase {
        case .active:
            await store.synchronize()
            await store.send(.appLifecyclePhaseChanged(.active))
        case .inactive:
            await store.send(.appLifecyclePhaseChanged(.inactive))
        case .background:
            await store.send(.appLifecyclePhaseChanged(.background))
        @unknown default:
            await store.send(.appLifecyclePhaseChanged(.inactive))
        }
    }
}

private struct SettingsView: View {
    let store: MeterStore

    var body: some View {
        Form {
            Section {
                Picker(
                    "측정 반응",
                    selection: Binding(
                        get: {
                            store.state.preferences.measurementResponse
                        },
                        set: { response in
                            Task {
                                await store.send(
                                    .measurementResponseChanged(response)
                                )
                            }
                        }
                    )
                ) {
                    Text("빠르게").tag(MeasurementResponse.fast)
                    Text("안정적으로").tag(MeasurementResponse.stable)
                }
                .pickerStyle(.segmented)
                .disabled(store.state.isMeasurementConfigurationLocked)
            } header: {
                Text("측정 반응")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(measurementResponseDescription)
                    if store.state.isMeasurementConfigurationLocked {
                        Text("측정 중에는 변경할 수 없습니다.")
                    }
                }
            }

            Section {
                Toggle(
                    "백그라운드 측정",
                    isOn: Binding(
                        get: {
                            store.state.preferences.isBackgroundMeasurementEnabled
                        },
                        set: { isEnabled in
                            Task {
                                await store.send(
                                    .backgroundMeasurementPreferenceChanged(isEnabled)
                                )
                            }
                        }
                    )
                )
                .disabled(store.state.isMeasurementConfigurationLocked)
            } footer: {
                Text(
                    store.state.isMeasurementConfigurationLocked
                        ? "측정 중에는 변경할 수 없습니다. 측정을 중지한 뒤 변경해 주세요."
                        : "켜면 측정 시작과 함께 Live Activity가 실행되고 백그라운드에서도 측정을 계속합니다."
                )
            }
        }
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var measurementResponseDescription: String {
        switch store.state.preferences.measurementResponse {
        case .fast:
            "갑작스러운 소음 변화를 빠르게 보여줍니다. 값이 자주 움직일 수 있습니다."
        case .stable:
            "짧은 소음 변화를 부드럽게 반영해 값이 덜 흔들립니다."
        }
    }
}

#Preview {
    MeterView(
        store: MeterStore(
            liveActivity: PreviewLiveActivityClient(),
            microphonePermission: PreviewMicrophonePermissionClient(),
            microphoneMeter: PreviewMicrophoneMeterClient(),
            preferences: PreviewMeterPreferencesClient()
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
    func start() async throws -> AsyncStream<SoundLevelSample> {
        AsyncStream { continuation in
            continuation.yield(
                SoundLevelSample(decibelsA: 72, duration: 1)
            )
        }
    }

    func stop() async {}
}

@MainActor
private final class PreviewMeterPreferencesClient: MeterPreferencesClient {
    private var preferences = MeterPreferences.default

    func load() -> MeterPreferences {
        preferences
    }

    func save(_ preferences: MeterPreferences) {
        self.preferences = preferences
    }
}

