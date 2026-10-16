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
- Sample PCM input with `AVAudioEngine` and convert RMS levels to approximate decibels.
- Apply one-second Slow smoothing to the current value while preserving raw peaks.
- Track the current, session average, and peak values.
- Update the Live Activity from real microphone readings on a coalesced cadence.
- Provide Lock Screen, Dynamic Island, and supplemental small-family layouts used by CarPlay.

The displayed value currently uses a fixed calibration offset. It is an estimate, not a calibrated dB SPL or dBA measurement. Device-specific calibration and frequency weighting remain future work.

## Run

1. Open `NoiseMeter.xcodeproj` in Xcode 27 or later.
2. Select your development team for both targets.
3. Run `NoiseMeter` on a physical iPhone that allows Live Activities.
4. Tap **측정 시작** and allow microphone access.
5. Start the Live Activity to show the current reading outside the app.

Live Activities must be enabled for the app in iOS Settings. CarPlay decides placement and refresh timing on the Dashboard.

