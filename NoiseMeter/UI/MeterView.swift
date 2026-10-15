import SwiftUI

struct MeterView: View {
    let store: MeterStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    readingCard
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
}

#Preview {
    MeterView(store: MeterStore(liveActivity: PreviewLiveActivityClient()))
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

