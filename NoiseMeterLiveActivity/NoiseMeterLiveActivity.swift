import ActivityKit
import SwiftUI
import WidgetKit

struct NoiseMeterLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NoiseActivityAttributes.self) { context in
            NoiseActivityView(context: context)
                .activityBackgroundTint(Color(.secondarySystemBackground))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.band.title, systemImage: context.state.band.symbolName)
                        .foregroundStyle(bandColor(for: context.state.band))
                }

                DynamicIslandExpandedRegion(.trailing) {
                    decibelText(context.state.currentDecibels, font: .title2)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("평균 \(context.state.averageDecibels) dB")
                        Spacer()
                        Text("최대 \(context.state.peakDecibels) dB")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: context.state.band.symbolName)
                    .foregroundStyle(bandColor(for: context.state.band))
            } compactTrailing: {
                Text("\(context.state.currentDecibels)")
                    .monospacedDigit()
            } minimal: {
                Image(systemName: context.state.band.symbolName)
                    .foregroundStyle(bandColor(for: context.state.band))
            }
            .keylineTint(bandColor(for: context.state.band))
        }
        .supplementalActivityFamilies([.small])
    }

    private func decibelText(_ value: Int, font: Font) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(value)")
                .font(font.monospacedDigit().weight(.semibold))
            Text("dB")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func bandColor(for band: NoiseBand) -> Color {
        switch band {
        case .quiet: .green
        case .moderate: .orange
        case .loud: .red
        }
    }
}

private struct NoiseActivityView: View {
    let context: ActivityViewContext<NoiseActivityAttributes>

    @Environment(\.activityFamily) private var activityFamily

    var body: some View {
        if activityFamily == .small {
            compactCard
        } else {
            lockScreenCard
        }
    }

    private var compactCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Label("실내 소음", systemImage: "mic.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(context.state.currentDecibels)")
                        .font(.title.bold().monospacedDigit())
                    Text("dB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            Label(context.state.band.title, systemImage: context.state.band.symbolName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(bandColor)
        }
        .padding()
    }

    private var lockScreenCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label(context.attributes.title, systemImage: "mic.fill")
                    .font(.headline)
                Spacer()
                Label(context.state.band.title, systemImage: context.state.band.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(bandColor)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(context.state.currentDecibels)")
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                Text("dB")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("평균 \(context.state.averageDecibels) dB")
                    Text("최대 \(context.state.peakDecibels) dB")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var bandColor: Color {
        switch context.state.band {
        case .quiet: .green
        case .moderate: .orange
        case .loud: .red
        }
    }
}

#Preview("Lock Screen", as: .content, using: NoiseActivityAttributes(sessionID: UUID(), title: "차량 실내 소음")) {
    NoiseMeterLiveActivity()
} contentStates: {
    NoiseActivityAttributes.ContentState(reading: .preview)
}

#Preview("Dynamic Island", as: .dynamicIsland(.expanded), using: NoiseActivityAttributes(sessionID: UUID(), title: "차량 실내 소음")) {
    NoiseMeterLiveActivity()
} contentStates: {
    NoiseActivityAttributes.ContentState(reading: .preview)
}

