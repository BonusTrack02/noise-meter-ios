# Noise Meter for iOS

A modern, native iOS noise meter focused on a glanceable Live Activity that can surface in CarPlay.

## Baseline

- iOS 18+
- Swift 6 strict concurrency
- SwiftUI and Observation
- ActivityKit and WidgetKit
- Unidirectional MVI state flow
- No UIKit compatibility layer, Combine-based view models, or third-party runtime dependencies

## Current milestone

The app now includes its first on-device measurement path:

- Request microphone access only when measurement starts.
- Prefer the iPhone's built-in microphone for capture.
- Apply an A-weighting filter to PCM input and convert its RMS level to approximate dBA.
- Let users choose a Fast (0.125 second) or Stable (1 second) response for the current dBA value.
- Calculate session LAeq from time-weighted acoustic energy.
- Track and display the session minimum and maximum from the same response-smoothed levels.
- Process every audio buffer while publishing meter UI snapshots ten times per second.
- Configure background measurement from a dedicated settings screen, with Live Activity following it automatically.
- Keep an active microphone measurement running in the background, or pause and resume it without resetting session statistics.
- Update the Live Activity from real microphone readings on a coalesced cadence.
- Provide Lock Screen, Dynamic Island, and supplemental small-family layouts used by CarPlay.

The displayed dBA and LAeq values use a fixed calibration offset. They are estimates, not readings from an IEC 61672 compliant sound level meter. Device-specific microphone calibration remains future work.

## Run

1. Open `NoiseMeter.xcodeproj` in Xcode 27 or later.
2. Select your development team for both targets.
3. Run `NoiseMeter` on a physical iPhone that allows Live Activities.
4. Use the settings button to choose the measurement response and background behavior.
5. Tap **측정 시작** and allow microphone access.
6. When background measurement is enabled, the Live Activity starts automatically with the measurement.

Live Activities must be enabled for the app in iOS Settings. CarPlay decides placement and refresh timing on the Dashboard.

