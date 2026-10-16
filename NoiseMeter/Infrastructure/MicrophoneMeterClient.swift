import AVFAudio

@MainActor
protocol MicrophoneMeterClient: AnyObject {
    func start() async throws -> AsyncStream<SoundLevelSample>
    func stop() async
}

enum MicrophoneMeterError: LocalizedError {
    case builtInMicrophoneUnavailable
    case invalidInputFormat
    case activationFailed

    var errorDescription: String? {
        switch self {
        case .builtInMicrophoneUnavailable:
            "휴대폰 내장 마이크를 사용할 수 없습니다."
        case .invalidInputFormat:
            "마이크 입력 형식을 불러올 수 없습니다."
        case .activationFailed:
            "오디오 세션을 활성화할 수 없습니다."
        }
    }
}

enum SoundLevelMath {
    static let defaultCalibrationOffset = 100.0

    static func approximateDecibelsA(
        weightedRMS: Float,
        calibrationOffset: Double = defaultCalibrationOffset
    ) -> Double {
        guard weightedRMS.isFinite, weightedRMS > 0 else { return 0 }

        let decibelsFullScale = 20 * log10(Double(weightedRMS))
        return min(max(decibelsFullScale + calibrationOffset, 0), 120)
    }
}

struct AWeightingFilter: Sendable {
    // The IEC A-frequency response is represented as three analog second-order
    // sections, then mapped to the active PCM sample rate with a bilinear transform.
    private static let referenceFrequency = 1_000.0
    private static let cornerFrequencies = (
        low: 20.598_997,
        lowerMiddle: 107.652_65,
        upperMiddle: 737.862_23,
        high: 12_194.217
    )

    private var lowFrequencyHighPass: BiquadFilter
    private var middleFrequencyHighPass: BiquadFilter
    private var highFrequencyLowPass: BiquadFilter

    init?(sampleRate: Double) {
        let corners = Self.cornerFrequencies
        guard sampleRate.isFinite,
              sampleRate > 2 * corners.high,
              sampleRate > 2 * Self.referenceFrequency
        else {
            return nil
        }

        let low = Self.prewarpedAngularFrequency(corners.low, sampleRate: sampleRate)
        let lowerMiddle = Self.prewarpedAngularFrequency(
            corners.lowerMiddle,
            sampleRate: sampleRate
        )
        let upperMiddle = Self.prewarpedAngularFrequency(
            corners.upperMiddle,
            sampleRate: sampleRate
        )
        let high = Self.prewarpedAngularFrequency(corners.high, sampleRate: sampleRate)

        lowFrequencyHighPass = BiquadFilter(
            coefficients: BiquadCoefficients.bilinearTransform(
                numeratorQuadratic: 1,
                numeratorLinear: 0,
                numeratorConstant: 0,
                denominatorLinear: 2 * low,
                denominatorConstant: low * low,
                sampleRate: sampleRate
            ).normalized(
                at: Self.referenceFrequency,
                sampleRate: sampleRate
            )
        )
        middleFrequencyHighPass = BiquadFilter(
            coefficients: BiquadCoefficients.bilinearTransform(
                numeratorQuadratic: 1,
                numeratorLinear: 0,
                numeratorConstant: 0,
                denominatorLinear: lowerMiddle + upperMiddle,
                denominatorConstant: lowerMiddle * upperMiddle,
                sampleRate: sampleRate
            ).normalized(
                at: Self.referenceFrequency,
                sampleRate: sampleRate
            )
        )
        highFrequencyLowPass = BiquadFilter(
            coefficients: BiquadCoefficients.bilinearTransform(
                numeratorQuadratic: 0,
                numeratorLinear: 0,
                numeratorConstant: 1,
                denominatorLinear: 2 * high,
                denominatorConstant: high * high,
                sampleRate: sampleRate
            ).normalized(
                at: Self.referenceFrequency,
                sampleRate: sampleRate
            )
        )
    }

    mutating func process(_ sample: Float) -> Float {
        let lowPassed = lowFrequencyHighPass.process(Double(sample))
        let middlePassed = middleFrequencyHighPass.process(lowPassed)
        return Float(highFrequencyLowPass.process(middlePassed))
    }

    func gainDecibels(at frequency: Double, sampleRate: Double) -> Double {
        let magnitude = lowFrequencyHighPass.magnitude(
            at: frequency,
            sampleRate: sampleRate
        ) * middleFrequencyHighPass.magnitude(
            at: frequency,
            sampleRate: sampleRate
        ) * highFrequencyLowPass.magnitude(
            at: frequency,
            sampleRate: sampleRate
        )
        guard magnitude.isFinite, magnitude > 0 else { return -.infinity }
        return 20 * log10(magnitude)
    }

    private static func prewarpedAngularFrequency(
        _ frequency: Double,
        sampleRate: Double
    ) -> Double {
        2 * sampleRate * tan(.pi * frequency / sampleRate)
    }
}

private struct BiquadCoefficients: Sendable {
    let b0: Double
    let b1: Double
    let b2: Double
    let a1: Double
    let a2: Double

    static func bilinearTransform(
        numeratorQuadratic: Double,
        numeratorLinear: Double,
        numeratorConstant: Double,
        denominatorLinear: Double,
        denominatorConstant: Double,
        sampleRate: Double
    ) -> BiquadCoefficients {
        let transform = 2 * sampleRate
        let squaredTransform = transform * transform
        let denominatorScale = squaredTransform
            + (denominatorLinear * transform)
            + denominatorConstant

        return BiquadCoefficients(
            b0: (
                numeratorQuadratic * squaredTransform
                    + numeratorLinear * transform
                    + numeratorConstant
            ) / denominatorScale,
            b1: (
                -2 * numeratorQuadratic * squaredTransform
                    + 2 * numeratorConstant
            ) / denominatorScale,
            b2: (
                numeratorQuadratic * squaredTransform
                    - numeratorLinear * transform
                    + numeratorConstant
            ) / denominatorScale,
            a1: (-2 * squaredTransform + 2 * denominatorConstant)
                / denominatorScale,
            a2: (
                squaredTransform
                    - denominatorLinear * transform
                    + denominatorConstant
            ) / denominatorScale
        )
    }

    func normalized(at frequency: Double, sampleRate: Double) -> BiquadCoefficients {
        let gain = magnitude(at: frequency, sampleRate: sampleRate)
        guard gain.isFinite, gain > 0 else { return self }

        return BiquadCoefficients(
            b0: b0 / gain,
            b1: b1 / gain,
            b2: b2 / gain,
            a1: a1,
            a2: a2
        )
    }

    func magnitude(at frequency: Double, sampleRate: Double) -> Double {
        guard frequency.isFinite,
              frequency > 0,
              frequency < sampleRate / 2
        else {
            return 0
        }

        let angle = 2 * Double.pi * frequency / sampleRate
        let numeratorReal = b0 + (b1 * cos(angle)) + (b2 * cos(2 * angle))
        let numeratorImaginary = -(b1 * sin(angle)) - (b2 * sin(2 * angle))
        let denominatorReal = 1 + (a1 * cos(angle)) + (a2 * cos(2 * angle))
        let denominatorImaginary = -(a1 * sin(angle)) - (a2 * sin(2 * angle))
        let numeratorPower = (numeratorReal * numeratorReal)
            + (numeratorImaginary * numeratorImaginary)
        let denominatorPower = (denominatorReal * denominatorReal)
            + (denominatorImaginary * denominatorImaginary)
        guard denominatorPower > 0 else { return 0 }
        return sqrt(numeratorPower / denominatorPower)
    }
}

private struct BiquadFilter: Sendable {
    private let coefficients: BiquadCoefficients
    private var delay1 = 0.0
    private var delay2 = 0.0

    init(coefficients: BiquadCoefficients) {
        self.coefficients = coefficients
    }

    mutating func process(_ sample: Double) -> Double {
        let output = (coefficients.b0 * sample) + delay1
        delay1 = (coefficients.b1 * sample) - (coefficients.a1 * output) + delay2
        delay2 = (coefficients.b2 * sample) - (coefficients.a2 * output)
        return output
    }

    func magnitude(at frequency: Double, sampleRate: Double) -> Double {
        coefficients.magnitude(at: frequency, sampleRate: sampleRate)
    }
}

private final class AWeightedRMSProcessor: @unchecked Sendable {
    private var filter: AWeightingFilter

    init?(sampleRate: Double) {
        guard let filter = AWeightingFilter(sampleRate: sampleRate) else { return nil }
        self.filter = filter
    }

    func rootMeanSquare(of buffer: AVAudioPCMBuffer) -> Float? {
        guard buffer.frameLength > 0,
              let channelData = buffer.floatChannelData?[0]
        else {
            return nil
        }

        let frameCount = Int(buffer.frameLength)
        let stride = buffer.stride
        var sumOfSquares = 0.0

        for frame in 0..<frameCount {
            let weightedSample = Double(filter.process(channelData[frame * stride]))
            sumOfSquares += weightedSample * weightedSample
        }

        guard sumOfSquares.isFinite else { return nil }
        return Float(sqrt(sumOfSquares / Double(frameCount)))
    }
}

@MainActor
final class SystemMicrophoneMeterClient: MicrophoneMeterClient {
    private let audioEngine = AVAudioEngine()
    private let audioSession = AVAudioSession.sharedInstance()
    private let calibrationOffset: Double

    private var continuation: AsyncStream<SoundLevelSample>.Continuation?
    private var isTapInstalled = false
    private var isSessionActive = false

    init(calibrationOffset: Double = SoundLevelMath.defaultCalibrationOffset) {
        self.calibrationOffset = calibrationOffset
    }

    func start() async throws -> AsyncStream<SoundLevelSample> {
        await stop()

        do {
            try audioSession.setCategory(.record, mode: .measurement)
            try await activateAudioSession()

            guard let builtInMicrophone = audioSession.availableInputs?.first(where: {
                $0.portType == .builtInMic
            }) else {
                throw MicrophoneMeterError.builtInMicrophoneUnavailable
            }
            try audioSession.setPreferredInput(builtInMicrophone)

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw MicrophoneMeterError.invalidInputFormat
            }
            guard let rmsProcessor = AWeightedRMSProcessor(
                sampleRate: format.sampleRate
            ) else {
                throw MicrophoneMeterError.invalidInputFormat
            }

            let (stream, continuation) = AsyncStream<SoundLevelSample>.makeStream(
                bufferingPolicy: .unbounded
            )
            self.continuation = continuation

            let tapHandler = Self.makeTapHandler(
                continuation: continuation,
                calibrationOffset: calibrationOffset,
                rmsProcessor: rmsProcessor
            )
            inputNode.installTap(
                onBus: 0,
                bufferSize: 4_096,
                format: format,
                block: tapHandler
            )
            isTapInstalled = true

            audioEngine.prepare()
            try audioEngine.start()
            return stream
        } catch {
            await stop()
            throw error
        }
    }

    func stop() async {
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }

        audioEngine.stop()
        audioEngine.reset()
        continuation?.finish()
        continuation = nil
        await deactivateAudioSession()
    }

    private func activateAudioSession() async throws {
        if #available(iOS 27.0, *) {
            let activated = try await audioSession.activate(options: [])
            guard activated else { throw MicrophoneMeterError.activationFailed }
        } else {
            try await Self.activateAudioSessionLegacy()
        }
        isSessionActive = true
    }

    private func deactivateAudioSession() async {
        guard isSessionActive else { return }
        isSessionActive = false

        if #available(iOS 27.0, *) {
            _ = try? await audioSession.deactivate(
                options: [.notifyOthersOnDeactivation]
            )
        } else {
            await Self.deactivateAudioSessionLegacy()
        }
    }

    private nonisolated static func activateAudioSessionLegacy() async throws {
        try await Task.detached(priority: .userInitiated) {
            try AVAudioSession.sharedInstance().setActive(true)
        }.value
    }

    private nonisolated static func deactivateAudioSessionLegacy() async {
        _ = try? await Task.detached(priority: .userInitiated) {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }.value
    }

    // AVAudioEngine invokes tap handlers on a real-time audio queue. Creating
    // this closure outside MainActor isolation prevents a Swift 6 executor
    // precondition failure when the first microphone buffer arrives.
    private nonisolated static func makeTapHandler(
        continuation: AsyncStream<SoundLevelSample>.Continuation,
        calibrationOffset: Double,
        rmsProcessor: AWeightedRMSProcessor
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let rms = rmsProcessor.rootMeanSquare(of: buffer) else { return }
            let duration = Double(buffer.frameLength) / buffer.format.sampleRate
            continuation.yield(
                SoundLevelSample(
                    decibelsA: SoundLevelMath.approximateDecibelsA(
                        weightedRMS: rms,
                        calibrationOffset: calibrationOffset
                    ),
                    duration: duration
                )
            )
        }
    }
}
