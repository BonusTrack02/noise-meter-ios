import ActivityKit
import Foundation

struct SoundLevelSample: Equatable, Sendable {
    let decibelsA: Double
    let duration: TimeInterval
}

struct NoiseActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        let currentDecibels: Int
        let laeqDecibels: Int
        let maximumDecibels: Int
        let band: NoiseBand
        let measuredAt: Date

        private enum CodingKeys: String, CodingKey {
            case currentDecibels
            case laeqDecibels
            case maximumDecibels = "peakDecibels"
            case band
            case measuredAt
        }

        init(reading: NoiseReading, measuredAt: Date = .now) {
            currentDecibels = reading.current.roundedInt
            laeqDecibels = reading.laeq.roundedInt
            maximumDecibels = reading.maximum.roundedInt
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

enum MeasurementResponse: String, Equatable, Hashable, Sendable {
    case fast
    case stable

    var timeConstant: TimeInterval {
        switch self {
        case .fast: 0.125
        case .stable: 1
        }
    }
}

struct NoiseReading: Codable, Equatable, Sendable {
    let current: Double
    let minimum: Double
    let laeq: Double
    let maximum: Double

    static let zero = NoiseReading(current: 0, minimum: 0, laeq: 0, maximum: 0)
    static let preview = NoiseReading(current: 72, minimum: 54, laeq: 69, maximum: 81)

    var band: NoiseBand {
        NoiseBand(decibels: current)
    }

    func addingMeasurement(
        _ sample: SoundLevelSample,
        previousSampleCount: Int,
        laeq: Double,
        response: MeasurementResponse = .stable
    ) -> NoiseReading {
        let boundedValue = min(max(sample.decibelsA, 0), 120)
        guard previousSampleCount > 0 else {
            return NoiseReading(
                current: boundedValue,
                minimum: boundedValue,
                laeq: laeq,
                maximum: boundedValue
            )
        }

        let slowValue = smoothedCurrent(
            toward: boundedValue,
            sampleDuration: sample.duration,
            timeConstant: response.timeConstant
        )
        return NoiseReading(
            current: slowValue,
            minimum: min(minimum, slowValue),
            laeq: laeq,
            maximum: max(maximum, slowValue)
        )
    }

    private func smoothedCurrent(
        toward value: Double,
        sampleDuration: TimeInterval,
        timeConstant: TimeInterval
    ) -> Double {
        guard sampleDuration.isFinite, sampleDuration > 0 else { return value }

        let smoothingFactor = 1 - exp(-sampleDuration / timeConstant)
        return current + (smoothingFactor * (value - current))
    }
}

struct LAeqAccumulator: Equatable, Sendable {
    private(set) var energyExposure = 0.0
    private(set) var measuredDuration: TimeInterval = 0

    mutating func add(_ sample: SoundLevelSample) -> Double? {
        guard sample.decibelsA.isFinite,
              sample.duration.isFinite,
              sample.duration > 0
        else {
            return nil
        }

        let boundedLevel = min(max(sample.decibelsA, 0), 120)
        // LAeq = 10 log10((1 / T) * integral(10^(L_A(t) / 10)) dt)
        let energy = pow(10, boundedLevel / 10)
        energyExposure += energy * sample.duration
        measuredDuration += sample.duration

        guard energyExposure.isFinite, measuredDuration > 0 else { return nil }
        return min(max(10 * log10(energyExposure / measuredDuration), 0), 120)
    }
}

private extension Double {
    var roundedInt: Int {
        Int(rounded())
    }
}

