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
        var state = MeterState(isRequestingMicrophonePermission: true)

        let effect = MeterReducer.reduce(
            state: &state,
            action: .microphonePermissionUpdated(.granted)
        )

        #expect(state.microphonePermission == .granted)
        #expect(!state.isRequestingMicrophonePermission)
        #expect(state.isMeasuring)
        #expect(effect == .none)
    }

    @Test
    func denyingMicrophonePermissionPresentsSettingsAlert() {
        var state = MeterState(isRequestingMicrophonePermission: true)

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

        #expect(state.isMeasuring)
        #expect(effect == .none)
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
        #expect(effect == .none)
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

        #expect(effect == .startLiveActivity(.preview))
    }

    @Test
    func aRunningActivityReceivesUpdatedReading() {
        var state = MeterState(isLiveActivityRunning: true)

        let effect = MeterReducer.reduce(
            state: &state,
            action: .previewLevelChanged(86)
        )

        #expect(state.reading.current == 86)
        #expect(state.reading.band == .loud)
        #expect(effect == .updateLiveActivity(state.reading))
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

