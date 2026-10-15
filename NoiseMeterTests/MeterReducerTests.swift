import Testing
@testable import NoiseMeter

struct MeterReducerTests {
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

