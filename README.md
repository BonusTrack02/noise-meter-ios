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

The first milestone implements an end-to-end Live Activity preview:

- Start and stop the Live Activity from the app.
- Update current, average, and peak values.
- Coalesce routine updates to a three-second cadence.
- Push meaningful band changes immediately.
- Provide Lock Screen, Dynamic Island, and supplemental small-family layouts used by CarPlay.

The in-app value control is intentionally labeled as a preview. Microphone capture and calibrated sound-level processing will replace it in the next milestone.

## Run

1. Open `NoiseMeter.xcodeproj` in Xcode 27 or later.
2. Select your development team for both targets.
3. Run `NoiseMeter` on a physical iPhone that allows Live Activities.
4. Start the Live Activity and adjust the preview level.

Live Activities must be enabled for the app in iOS Settings. CarPlay decides placement and refresh timing on the Dashboard.

