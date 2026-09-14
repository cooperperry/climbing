# AGENTS.md

Guidance for agents (and humans) working in this repository.

## What this is

A native iOS, local-first rock climbing app built with **SwiftUI** and
**SwiftData**. See `README.md` for the feature overview and file layout.

## Architecture: keep logic portable

The codebase is split so business rules stay testable without Apple SDKs:

- `Climbing/Domain/` — **Foundation-only** domain logic (outcomes, styles,
  grade-scale ranking, session-clock math). No SwiftUI/SwiftData imports. This is
  compiled and unit-tested on any platform, including Linux CI, via the root
  `Package.swift`.
- `Climbing/Models/` — SwiftData `@Model` types. **Xcode/iOS only.**
- `Climbing/Views/` — SwiftUI views. **Xcode/iOS only.**

When adding new business rules, prefer putting the pure logic in
`Climbing/Domain/` (Foundation-only) and keep `Models`/`Views` as a thin,
framework-bound layer on top. This keeps logic covered by tests that run
everywhere.

## Building and running the app (macOS + Xcode)

The app target must be built and run on **macOS with Xcode 15+** (SwiftUI +
SwiftData require the Apple SDKs and the iOS Simulator).

```bash
brew install xcodegen        # once
xcodegen generate            # creates Climbing.xcodeproj from project.yml
open Climbing.xcodeproj       # then Run (Cmd+R) on an iOS 17+ simulator
```

`Climbing.xcodeproj` is generated and git-ignored — regenerate it with
`xcodegen generate` after changing `project.yml` or adding source files.

## Testing

Two suites, run in different places:

- **Domain tests (any platform, incl. Linux/CI):**
  ```bash
  swift test
  ```
  Runs `Tests/ClimbingDomainTests` against the `Climbing/Domain` sources.

- **Model/UI tests (Xcode/macOS only):** the `ClimbingTests` target
  (`ClimbingTests/`) exercises the SwiftData models with an in-memory
  `ModelContainer`. Run via `Cmd+U` in Xcode, or:
  ```bash
  xcodebuild test -scheme Climbing -destination 'platform=iOS Simulator,name=iPhone 15'
  ```

## Cursor Cloud specific instructions

Cursor Cloud Agents run on **Linux**, which **cannot compile or run the iOS
app** — SwiftUI, SwiftData, and the iOS Simulator require macOS + Xcode.

For agents working here:

- Validate changes to the portable domain layer with `swift test` (the Linux
  environment installs Swift 6.0.3 via `.cursor/Dockerfile`).
- `Climbing/Models` and `Climbing/Views` can only be **syntax-checked** on Linux
  (`swiftc -parse <file>`); they cannot be type-checked or run here. Do not treat
  a green Linux run as proof the SwiftData/SwiftUI layer builds.
- The `ClimbingTests` (SwiftData/XCTest) target only runs in Xcode/simulator, so
  it must be verified on macOS, not in a Cloud Agent.
- Prefer adding new testable logic to `Climbing/Domain/` so it can be verified in
  this environment.
