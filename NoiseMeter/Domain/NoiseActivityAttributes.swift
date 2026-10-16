import ActivityKit
import Foundation

struct SoundLevelSample: Equatable, Sendable {
    let decibels: Double
    let duration: TimeInterval
}

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
    private static let slowTimeConstant: TimeInterval = 1

    let current: Double
    let average: Double
    let peak: Double

    static let zero = NoiseReading(current: 0, average: 0, peak: 0)
    static let preview = NoiseReading(current: 72, average: 69, peak: 81)

    var band: NoiseBand {
        NoiseBand(decibels: current)
    }

    func addingMeasurement(
        _ sample: SoundLevelSample,
        previousSampleCount: Int
    ) -> NoiseReading {
        let boundedValue = min(max(sample.decibels, 0), 120)
        guard previousSampleCount > 0 else {
            return NoiseReading(
                current: boundedValue,
                average: boundedValue,
                peak: boundedValue
            )
        }

        return NoiseReading(
            current: smoothedCurrent(
                toward: boundedValue,
                sampleDuration: sample.duration
            ),
            average: ((average * Double(previousSampleCount)) + boundedValue)
                / Double(previousSampleCount + 1),
            peak: max(peak, boundedValue)
        )
    }

    private func smoothedCurrent(
        toward value: Double,
        sampleDuration: TimeInterval
    ) -> Double {
        guard sampleDuration.isFinite, sampleDuration > 0 else { return value }

        let smoothingFactor = 1 - exp(-sampleDuration / Self.slowTimeConstant)
        return current + (smoothingFactor * (value - current))
    }
}

private extension Double {
    var roundedInt: Int {
        Int(rounded())
    }
}

