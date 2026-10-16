import Foundation
import Testing
@testable import NoiseMeter

struct MeterReducerTests {
    @Test
    func appearingSynchronizesMicrophonePermission() {
        var state = MeterState()

        let effect = MeterReducer.reduce(
            state: &state,
            action: .appeared(
                isLiveActivityRunning: false,
                microphonePermission: .granted
            )
        )

        #expect(state.microphonePermission == .granted)
        #expect(effect == .none)
    }

    @Test
    func requestingUndeterminedMicrophonePermissionProducesEffect() {
        var state = MeterState(microphonePermission: .undetermined)

        let effect = MeterReducer.reduce(
            state: &state,
            action: .measurementButtonTapped
        )

        #expect(state.isRequestingMicrophonePermission)
        #expect(effect == .requestMicrophonePermission)
    }

    @Test
    func deniedMicrophonePermissionPresentsSettingsAlert() {
        var state = MeterState(microphonePermission: .denied)

        let effect = MeterReducer.reduce(
            state: &state,
            action: .measurementButtonTapped
        )

        #expect(state.isMicrophoneSettingsAlertPresented)
        #expect(effect == .none)
    }

    @Test
    func microphonePermissionResponseUpdatesState() {
        var state = MeterState(
            isMeasurementStartPending: true,
            isRequestingMicrophonePermission: true
        )

        let effect = MeterReducer.reduce(
            state: &state,
            action: .microphonePermissionUpdated(.granted)
        )

        #expect(state.microphonePermission == .granted)
        #expect(!state.isRequestingMicrophonePermission)
        #expect(state.isStartingMeasurement)
        #expect(effect == .startMeasurement)
    }

    @Test
    func denyingMicrophonePermissionPresentsSettingsAlert() {
        var state = MeterState(
            isMeasurementStartPending: true,
            isRequestingMicrophonePermission: true
        )

        let effect = MeterReducer.reduce(
            state: &state,
            action: .microphonePermissionUpdated(.denied)
        )

        #expect(!state.isRequestingMicrophonePermission)
        #expect(!state.isMeasuring)
        #expect(state.isMicrophoneSettingsAlertPresented)
        #expect(effect == .none)
    }

    @Test
    func startingMeasurementWithPermissionDoesNotRequestAgain() {
        var state = MeterState(microphonePermission: .granted)

        let effect = MeterReducer.reduce(
            state: &state,
            action: .measurementButtonTapped
        )

        #expect(state.isStartingMeasurement)
        #expect(effect == .startMeasurement)
    }

    @Test
    func stoppingMeasurementDoesNotRequestPermission() {
        var state = MeterState(
            isMeasuring: true,
            microphonePermission: .granted
        )

        let effect = MeterReducer.reduce(
            state: &state,
            action: .measurementButtonTapped
        )

        #expect(state.isMeasuring)
        #expect(state.isStoppingMeasurement)
        #expect(effect == .stopMeasurement(endLiveActivity: false))
    }

    @Test
    func repeatedStopRequestIsIgnored() {
        var state = MeterState(
            isMeasuring: true,
            isStoppingMeasurement: true,
            microphonePermission: .granted
        )

        let effect = MeterReducer.reduce(
            state: &state,
            action: .measurementButtonTapped
        )

        #expect(effect == .none)
    }

    @Test
    func stoppingMeasurementEndsRunningLiveActivity() {
        var state = MeterState(
            isMeasuring: true,
            isLiveActivityRunning: true,
            microphonePermission: .granted
        )

        let effect = MeterReducer.reduce(
            state: &state,
            action: .measurementButtonTapped
        )

        #expect(effect == .stopMeasurement(endLiveActivity: true))
    }

    @Test
    func startingMeasurementResetsPreviousReadings() {
        var state = MeterState(
            reading: .preview,
            measurementSampleCount: 10,
            isStartingMeasurement: true,
            microphonePermission: .granted
        )

        let effect = MeterReducer.reduce(
            state: &state,
            action: .measurementStarted
        )

        #expect(state.reading == .zero)
        #expect(state.measurementSampleCount == 0)
        #expect(state.isMeasuring)
        #expect(!state.isStartingMeasurement)
        #expect(effect == .none)
    }

    @Test
    func receivingMeasurementUpdatesReading() {
        var state = MeterState(
            isMeasuring: true,
            microphonePermission: .granted
        )

        let effect = MeterReducer.reduce(
            state: &state,
            action: .measurementUpdated(
                reading: NoiseReading(
                    current: 68,
                    minimum: 62,
                    laeq: 68,
                    peak: 74
                ),
                sampleCount: 1
            )
        )

        #expect(
            state.reading == NoiseReading(
                current: 68,
                minimum: 62,
                laeq: 68,
                peak: 74
            )
        )
        #expect(state.measurementSampleCount == 1)
        #expect(effect == .none)
    }

    @Test
    func processingMultipleMeasurementsTracksMinimumLAeqAndPeak() throws {
        var processor = NoiseMeasurementProcessor()

        _ = processor.process(
            SoundLevelSample(decibelsA: 60, duration: 0.1)
        )
        let updatedReading = processor.process(
            SoundLevelSample(decibelsA: 80, duration: 1)
        )
        let reading = try #require(updatedReading)

        let expectedCurrent = 60 + ((1 - exp(-1.0)) * 20)
        let expectedLAeq = 10 * log10(
            ((pow(10, 6) * 0.1) + (pow(10, 8) * 1)) / 1.1
        )
        #expect(abs(reading.current - expectedCurrent) < 0.001)
        #expect(reading.minimum == 60)
        #expect(abs(reading.laeq - expectedLAeq) < 0.001)
        #expect(reading.peak == 80)
        #expect(processor.sampleCount == 2)
        #expect(abs(processor.measuredDuration - 1.1) < 0.001)
    }

    @Test
    func openingSettingsProducesEffect() {
        var state = MeterState(isMicrophoneSettingsAlertPresented: true)

        let effect = MeterReducer.reduce(
            state: &state,
            action: .openApplicationSettingsButtonTapped
        )

        #expect(!state.isMicrophoneSettingsAlertPresented)
        #expect(effect == .openApplicationSettings)
    }

    @Test
    func startingLiveActivityUsesCurrentReading() {
        var state = MeterState()

        let effect = MeterReducer.reduce(
            state: &state,
            action: .liveActivityButtonTapped
        )

        #expect(effect == .startLiveActivity(.zero))
    }

    @Test
    func aRunningActivityReceivesUpdatedReading() {
        var state = MeterState(
            isMeasuring: true,
            isLiveActivityRunning: true,
            microphonePermission: .granted
        )

        let effect = MeterReducer.reduce(
            state: &state,
            action: .measurementUpdated(
                reading: NoiseReading(
                    current: 86,
                    minimum: 64,
                    laeq: 82,
                    peak: 90
                ),
                sampleCount: 12
            )
        )

        #expect(state.reading.current == 86)
        #expect(state.reading.band == .loud)
        #expect(effect == .updateLiveActivity(state.reading))
    }

    @Test
    func displayCadencePublishesTenTimesPerSecond() {
        var cadence = MeasurementDisplayCadence()

        let firstBuffer = cadence.shouldPublish(at: 0.085)
        let beforeOneTenth = cadence.shouldPublish(at: 0.099)
        let firstTenth = cadence.shouldPublish(at: 0.17)
        let beforeTwoTenths = cadence.shouldPublish(at: 0.199)
        let twoTenths = cadence.shouldPublish(at: 0.256)
        let beforeThreeTenths = cadence.shouldPublish(at: 0.299)
        let threeTenths = cadence.shouldPublish(at: 0.341)

        #expect(firstBuffer)
        #expect(!beforeOneTenth)
        #expect(firstTenth)
        #expect(!beforeTwoTenths)
        #expect(twoTenths)
        #expect(!beforeThreeTenths)
        #expect(threeTenths)
    }

    @Test
    func decibelConversionAppliesCalibrationOffset() {
        let decibels = SoundLevelMath.approximateDecibelsA(weightedRMS: 0.1)

        #expect(abs(decibels - 80) < 0.001)
    }

    @Test
    func decibelConversionClampsSilenceAndOverload() {
        #expect(SoundLevelMath.approximateDecibelsA(weightedRMS: 0) == 0)
        #expect(SoundLevelMath.approximateDecibelsA(weightedRMS: 100) == 120)
    }

    @Test
    func laeqUsesLogarithmicEnergyAverage() throws {
        var accumulator = LAeqAccumulator()

        _ = accumulator.add(SoundLevelSample(decibelsA: 60, duration: 1))
        let updatedLAeq = accumulator.add(
            SoundLevelSample(decibelsA: 80, duration: 1)
        )
        let laeq = try #require(updatedLAeq)

        #expect(abs(laeq - 77.032_913_78) < 0.001)
    }

    @Test
    func aWeightingMatchesReferenceResponseAtCommonFrequencies() throws {
        for sampleRate in [44_100.0, 48_000.0] {
            let filter = try #require(AWeightingFilter(sampleRate: sampleRate))

            #expect(abs(filter.gainDecibels(at: 1_000, sampleRate: sampleRate)) < 0.01)
            #expect(
                abs(filter.gainDecibels(at: 100, sampleRate: sampleRate) + 19.1) < 0.2
            )
            #expect(
                abs(filter.gainDecibels(at: 4_000, sampleRate: sampleRate) - 1.0) < 0.4
            )
        }
    }

    @Test
    func aWeightingProcessesLowFrequencyPCM() throws {
        let sampleRate = 48_000.0
        let frequency = 100.0
        var filter = try #require(AWeightingFilter(sampleRate: sampleRate))
        var inputPower = 0.0
        var outputPower = 0.0

        for frame in 0..<96_000 {
            let sample = Float(
                sin(2 * Double.pi * frequency * Double(frame) / sampleRate)
            )
            let output = filter.process(sample)

            guard frame >= 48_000 else { continue }
            inputPower += Double(sample * sample)
            outputPower += Double(output * output)
        }

        let measuredGain = 10 * log10(outputPower / inputPower)
        #expect(abs(measuredGain + 19.1) < 0.2)
    }

    @Test
    func stoppingLiveActivityProducesEndEffect() {
        var state = MeterState(isLiveActivityRunning: true)

        let effect = MeterReducer.reduce(
            state: &state,
            action: .liveActivityButtonTapped
        )

        #expect(effect == .endLiveActivity)
    }
}

