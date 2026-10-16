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

        #expect(!state.isMeasuring)
        #expect(effect == .stopMeasurement(endLiveActivity: false))
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
            action: .measurementReceived(68)
        )

        #expect(state.reading == NoiseReading(current: 68, average: 68, peak: 68))
        #expect(state.measurementSampleCount == 1)
        #expect(effect == .none)
    }

    @Test
    func receivingMultipleMeasurementsTracksAverageAndPeak() {
        var state = MeterState(
            isMeasuring: true,
            microphonePermission: .granted
        )

        _ = MeterReducer.reduce(
            state: &state,
            action: .measurementReceived(60)
        )
        _ = MeterReducer.reduce(
            state: &state,
            action: .measurementReceived(80)
        )

        #expect(state.reading.current == 65)
        #expect(state.reading.average == 70)
        #expect(state.reading.peak == 80)
        #expect(state.measurementSampleCount == 2)
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
            action: .measurementReceived(86)
        )

        #expect(state.reading.current == 86)
        #expect(state.reading.band == .loud)
        #expect(effect == .updateLiveActivity(state.reading))
    }

    @Test
    func decibelConversionAppliesCalibrationOffset() {
        let decibels = DecibelMeterMath.approximateDecibels(rms: 0.1)

        #expect(abs(decibels - 80) < 0.001)
    }

    @Test
    func decibelConversionClampsSilenceAndOverload() {
        #expect(DecibelMeterMath.approximateDecibels(rms: 0) == 0)
        #expect(DecibelMeterMath.approximateDecibels(rms: 100) == 120)
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

