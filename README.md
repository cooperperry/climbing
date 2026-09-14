# Climbing

A native iOS, local-first rock climbing app built with **SwiftUI** and **SwiftData**.
Track climbing sessions with a live timer and log climbs (grade, attempts,
outcome, style) with quick-tap controls.

> This is the foundational data + UI layer: the SwiftData models and the primary
> `SessionView`.

## Requirements

- iOS 17+ / Xcode 15+ (SwiftData and the SwiftUI APIs used here require them)
- The app target must be built and run on **macOS with Xcode** — SwiftUI and
  SwiftData are Apple-platform frameworks and cannot be compiled on Linux.

## Project layout

```
Climbing/
  ClimbingApp.swift        App entry; configures the SwiftData ModelContainer
  ContentView.swift        Root view hosting SessionView
  Domain/                  Foundation-only domain logic (portable, unit-tested)
    ClimbOutcome.swift      Flash / Send / Project / Attempt
    ClimbStyle.swift        Crimp / Sloper / Overhang / ...
    GradeScaleTemplate.swift Ordered grade scales + ranking helpers
    SessionClock.swift      Elapsed-time math + H:MM:SS formatting
  Models/                  SwiftData @Model types (require Xcode)
    CustomGradeScale.swift  User-defined grading scales (V-scale, gym circuits)
    ClimbingSession.swift   Session start/end/duration + logs
    ClimbLog.swift          A single logged climb
  Views/
    SessionView.swift      Live session timer + quick-tap logging
Package.swift              SwiftPM harness that unit-tests Climbing/Domain on Linux/CI
Tests/ClimbingDomainTests/ XCTest suites for the domain layer
```

### Why the split?

The `Climbing/Domain` files depend only on `Foundation`, so the business rules
(grade ordering, outcome semantics, session-timer math) are unit tested on any
platform — including this repo's Linux CI. The SwiftData models and SwiftUI
views layer the Apple frameworks on top of that tested core.

## Building the app (Xcode / macOS)

1. Create a new iOS App project in Xcode (SwiftUI lifecycle, SwiftData enabled),
   or add these sources to an existing app target.
2. Add all files under `Climbing/` to the app target. They compile as a single
   module, so the models and views use the `Domain` types directly (no import).
3. Build and run on the iOS Simulator or a device.

On first launch the app seeds a default V-scale, then you can start a session and
log climbs.

## Running the domain tests (Linux / macOS)

The root SwiftPM package compiles the *same* `Climbing/Domain` sources and runs
their tests without Xcode:

```bash
swift test
```

This is what the Cloud Agent environment (`.cursor/environment.json`, Swift
Docker image) runs to validate the domain layer on every change.
