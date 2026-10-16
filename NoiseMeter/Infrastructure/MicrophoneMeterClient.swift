import Accelerate
import AVFAudio

@MainActor
protocol MicrophoneMeterClient: AnyObject {
    func start() async throws -> AsyncStream<Double>
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

enum DecibelMeterMath {
    static let defaultCalibrationOffset = 100.0

    static func approximateDecibels(
        rms: Float,
        calibrationOffset: Double = defaultCalibrationOffset
    ) -> Double {
        guard rms.isFinite, rms > 0 else { return 0 }

        let decibelsFullScale = 20 * log10(Double(rms))
        return min(max(decibelsFullScale + calibrationOffset, 0), 120)
    }
}

@MainActor
final class SystemMicrophoneMeterClient: MicrophoneMeterClient {
    private let audioEngine = AVAudioEngine()
    private let audioSession = AVAudioSession.sharedInstance()
    private let calibrationOffset: Double

    private var continuation: AsyncStream<Double>.Continuation?
    private var isTapInstalled = false
    private var isSessionActive = false

    init(calibrationOffset: Double = DecibelMeterMath.defaultCalibrationOffset) {
        self.calibrationOffset = calibrationOffset
    }

    func start() async throws -> AsyncStream<Double> {
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

            let (stream, continuation) = AsyncStream<Double>.makeStream(
                bufferingPolicy: .bufferingNewest(1)
            )
            self.continuation = continuation

            let tapHandler = Self.makeTapHandler(
                continuation: continuation,
                calibrationOffset: calibrationOffset
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
        continuation: AsyncStream<Double>.Continuation,
        calibrationOffset: Double
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let rms = rootMeanSquare(of: buffer) else { return }
            continuation.yield(
                DecibelMeterMath.approximateDecibels(
                    rms: rms,
                    calibrationOffset: calibrationOffset
                )
            )
        }
    }

    private nonisolated static func rootMeanSquare(of buffer: AVAudioPCMBuffer) -> Float? {
        guard buffer.frameLength > 0,
              let channelData = buffer.floatChannelData?[0]
        else {
            return nil
        }

        var rms: Float = 0
        vDSP_rmsqv(
            channelData,
            1,
            &rms,
            vDSP_Length(buffer.frameLength)
        )
        return rms
    }
}
