# AI Instruments

AI Instruments is a macOS app that analyzes an iOS `.app` bundle and produces an "Instruments-style" diagnostic report focused on:

- Memory leaks
- Swift concurrency safety
- Memory allocations

This repository also contains `TestApp`, an iOS app intentionally packed with issue patterns so you can validate and iterate on the analyzer.

## Repository Layout

- `AIInstruments/` - main macOS analyzer app (SwiftUI)
- `TestApp/` - iOS app used as analysis input

## What AIInstruments Does

`AIInstruments` performs static binary analysis of a provided `.app` bundle:

1. Loads app metadata (`Info.plist`, executable, linked frameworks).
2. Parses Mach-O binary data (including debug dylib slices when present).
3. Runs three instrument analyzers:
   - `LeaksAnalyzer`
   - `ConcurrencyAnalyzer`
   - `AllocationsAnalyzer`
4. Aggregates findings into a report with:
   - Severity-tagged issues
   - Confidence values
   - Per-instrument score
   - Overall score and grade

The app supports drag-and-drop and file picker import for `.app` bundles and allows exporting a text report.

## What "AI-driven" Means Here

The current implementation is an intelligent, rule-based analyzer over symbols, selectors, strings, sections, and linked libraries extracted from Mach-O binaries.

It is not a runtime profiler replacement for Apple Instruments. Instead, it is a fast static analysis assistant that can highlight likely risk patterns before runtime testing.

## AIInstruments Architecture

Key modules:

- `Analysis/AnalysisEngine.swift` - analysis pipeline orchestration
- `Analysis/MachOParser.swift` - Mach-O/fat binary parsing
- `Analysis/BinaryAnalyzer.swift` - shared evidence and pattern helpers
- `Analysis/LeaksAnalyzer.swift` - leak risk detection
- `Analysis/ConcurrencyAnalyzer.swift` - Swift concurrency risk detection
- `Analysis/AllocationsAnalyzer.swift` - allocation and memory footprint risks
- `Models/` - issue/result/report domain models
- `DI/` - dependency injection with Factory (`FactoryKit`)

## TestApp Purpose

`TestApp` is a companion iOS app that intentionally demonstrates problematic patterns from the same three categories:

- Memory leak demos (delegates, closures, notifications, timers, circular refs)
- Concurrency demos (non-Sendable, detached tasks, mixed models, unsafe continuations)
- Allocation demos (image loading, data buffers, collection growth, string churn, file I/O)

Use it to generate realistic `.app` inputs and verify whether AIInstruments reports expected findings.

## Typical Workflow

1. Build `TestApp` for iOS Simulator in Debug.
2. Locate the built `TestApp.app` product.
3. Launch `AIInstruments` (macOS app).
4. Drop `TestApp.app` into AIInstruments.
5. Review issues and scores for Leaks, Swift Concurrency, and Allocations.
6. Export report if needed.

## Getting a `.app` from TestApp

From Xcode:

- Open `TestApp/TestApp.xcodeproj`
- Select a Simulator destination
- Build (`Cmd+B`)
- In Products, right-click `TestApp.app` -> "Show in Finder"

From command line (example):

```bash
cd TestApp
xcodebuild -project "TestApp.xcodeproj" -scheme "TestApp" -configuration Debug -destination "platform=iOS Simulator,name=iPhone 16"
```

Then find the app under DerivedData `Build/Products/Debug-iphonesimulator/TestApp.app`.

## Running AIInstruments

- Open `AIInstruments/AIInstruments.xcodeproj`
- Run the `AIInstruments` scheme on macOS
- Import a `.app` bundle via drag-and-drop or "Browse Files"

## Tests

`AIInstruments` includes unit tests for parser, analyzers, models, and analysis engine under `AIInstruments/AIInstrumentsTests/`.

Run from command line:

```bash
cd AIInstruments
xcodebuild test -project "AIInstruments.xcodeproj" -scheme "AIInstruments" -destination "platform=macOS" -only-testing:AIInstrumentsTests
```

## Notes and Limitations

- Input format: `.app` bundles (no `.ipa` required).
- Analysis quality depends on symbol/string availability in the binary.
- Encrypted App Store binaries are not analyzable until decrypted.
- Findings are risk indicators, not guaranteed runtime bugs.
