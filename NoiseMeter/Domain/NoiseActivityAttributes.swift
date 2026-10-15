import ActivityKit
import Foundation

struct NoiseActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        let currentDecibels: Int
        let averageDecibels: Int
        let peakDecibels: Int
        let band: NoiseBand
        let measuredAt: Date

        init(reading: NoiseReading, measuredAt: Date = .now) {
            currentDecibels = reading.current.roundedInt
            averageDecibels = reading.average.roundedInt
            peakDecibels = reading.peak.roundedInt
            band = reading.band
            self.measuredAt = measuredAt
        }
    }

    let sessionID: UUID
    let title: String
}

enum NoiseBand: String, Codable, Hashable, Sendable {
    case quiet
    case moderate
    case loud

    init(decibels: Double) {
        switch decibels {
        case ..<60: self = .quiet
        case ..<80: self = .moderate
        default: self = .loud
        }
    }

    var title: String {
        switch self {
        case .quiet: "낮음"
        case .moderate: "보통"
        case .loud: "높음"
        }
    }

    var symbolName: String {
        switch self {
        case .quiet: "speaker.wave.1.fill"
        case .moderate: "speaker.wave.2.fill"
        case .loud: "speaker.wave.3.fill"
        }
    }
}

struct NoiseReading: Codable, Equatable, Sendable {
    let current: Double
    let average: Double
    let peak: Double

    static let preview = NoiseReading(current: 72, average: 69, peak: 81)

    var band: NoiseBand {
        NoiseBand(decibels: current)
    }

    func updatingCurrent(to value: Double) -> NoiseReading {
        NoiseReading(
            current: value,
            average: (average * 0.8) + (value * 0.2),
            peak: max(peak, value)
        )
    }
}

private extension Double {
    var roundedInt: Int {
        Int(rounded())
    }
}

