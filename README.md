# AI Instruments

AI Instruments is a macOS app that analyzes an iOS `.app` bundle and produces an "Instruments-style" diagnostic report focused on eight profiling categories:

- Memory leaks
- Swift concurrency safety
- Memory allocations
- Energy impact
- Network usage
- UI responsiveness (hangs)
- App launch time
- File activity (disk I/O)

This repository also contains `TestApp`, an iOS app intentionally packed with issue patterns so you can validate and iterate on the analyzer.

## Repository Layout

- `AIInstruments/` - main macOS analyzer app (SwiftUI)
- `TestApp/` - iOS app used as analysis input

## What AIInstruments Does

`AIInstruments` performs static binary analysis of a provided `.app` bundle:

1. Loads app metadata (`Info.plist`, executable, linked frameworks).
2. Parses Mach-O binary data (including debug dylib slices when present).
3. Runs eight instrument analyzers:
   - `LeaksAnalyzer` - memory leak risk detection
   - `ConcurrencyAnalyzer` - Swift concurrency safety analysis
   - `AllocationsAnalyzer` - memory allocation profiling
   - `EnergyAnalyzer` - energy/battery impact analysis
   - `NetworkAnalyzer` - network usage and security analysis
   - `HangsAnalyzer` - UI responsiveness and main thread blocking
   - `StartupAnalyzer` - app launch time analysis
   - `DiskIOAnalyzer` - file activity and disk I/O analysis
4. Aggregates findings into a report with:
   - Severity-tagged issues
   - Confidence values
   - Per-instrument score
   - Overall score and grade

The app supports drag-and-drop and file picker import for `.app` bundles and allows exporting a text report.

## Instruments

### LeaksAnalyzer

Detects potential memory leaks by analyzing retain cycle patterns, delegate references, closure captures, notification observers, and timer lifecycle management.

**Detection categories:** Strong delegate references, closure/block capture cycles, NotificationCenter observer lifecycle, timer retain cycles, circular references, Core Foundation retain/release imbalance, block-based APIs, ViewController lifecycle.

### ConcurrencyAnalyzer

Analyzes Swift concurrency patterns to detect potential data races and threading issues.

**Detection categories:** Sendable conformance gaps, actor isolation, MainActor usage, data race potential, unsafe concurrent access, task lifecycle management, legacy concurrency patterns, async/await patterns, global state.

### AllocationsAnalyzer

Profiles memory allocation patterns and identifies optimization opportunities.

**Detection categories:** Large allocations, image loading without downsampling, data buffer management, autorelease pool usage, collection growth without capacity reservation, cache utilization, string allocations, memory-mapped files, binary footprint, third-party frameworks.

### EnergyAnalyzer

Identifies patterns that negatively impact battery life, mapping to Xcode's Energy Log instrument.

**Detection categories:** Continuous location tracking without significant-change alternative, excessive timer usage without tolerance, CADisplayLink without frame rate limiting, extensive background processing, network session energy configuration, animation and GPU overhead, sensor and Bluetooth usage, push notification patterns, CPU-intensive operations without appropriate QoS.

### NetworkAnalyzer

Analyzes networking patterns for security, performance, and correctness issues, mapping to Xcode's Network instrument.

**Detection categories:** URL session configuration, App Transport Security compliance (plaintext HTTP detection), certificate pinning, network response caching, background transfers, third-party networking framework duplication, WebSocket heartbeat handling, data serialization efficiency.

### HangsAnalyzer

Detects patterns that cause UI hangs and main thread blocking, mapping to Xcode's Hangs instrument.

**Detection categories:** Synchronous file I/O, synchronous network requests (critical), heavy collection processing, complex view hierarchies, scroll view optimization (prefetching, diffable data sources), Auto Layout complexity, main thread synchronization primitives, image decoding without pre-rendering, Core Data without background contexts.

### StartupAnalyzer

Analyzes factors that affect app launch time, mapping to Xcode's App Launch instrument.

**Detection categories:** Static initializer overhead (`+load`, C++ global init), linked framework count, ObjC class registration cost, binary size impact on cold launch, dynamic library loading (weak imports), Swift protocol conformance metadata, eager SDK initialization at launch, launch-time work (Core Data migration, keychain access).

### DiskIOAnalyzer

Profiles file system access patterns, mapping to Xcode's File Activity instrument.

**Detection categories:** Synchronous file read/write operations, large file handling (streaming, memory mapping), Core Data batch operations and fetch batching, SQLite WAL journal mode, file coordination for app groups, temporary file cleanup, file protection for sensitive data, logging I/O (print/NSLog vs os_log).

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
- `Analysis/EnergyAnalyzer.swift` - energy/battery impact analysis
- `Analysis/NetworkAnalyzer.swift` - network usage and security analysis
- `Analysis/HangsAnalyzer.swift` - UI responsiveness and hang detection
- `Analysis/StartupAnalyzer.swift` - app launch time analysis
- `Analysis/DiskIOAnalyzer.swift` - file activity and disk I/O analysis
- `Models/` - issue/result/report domain models
- `DI/` - dependency injection with Factory (`FactoryKit`)

## TestApp Purpose

`TestApp` is a companion iOS app that intentionally demonstrates problematic patterns from all eight categories:

- Memory leak demos (delegates, closures, notifications, timers, circular refs)
- Concurrency demos (non-Sendable, detached tasks, mixed models, unsafe continuations)
- Allocation demos (image loading, data buffers, collection growth, string churn, file I/O)
- Energy demos (continuous GPS, excessive timers, CADisplayLink, background tasks, motion sensors)
- Network demos (plaintext HTTP, no pinning, shared session only, WebSocket without heartbeat)
- Hangs demos (sync file I/O, sync network, heavy sort, deep view hierarchy, Core Data on main thread)
- Startup demos (eager singletons, multiple SDK inits, heavy AppDelegate work)
- Disk I/O demos (sync file ops, Core Data without batching, SQLite without WAL, temp file accumulation)

Use it to generate realistic `.app` inputs and verify whether AIInstruments reports expected findings.

## Typical Workflow

1. Build `TestApp` for iOS Simulator in Debug.
2. Locate the built `TestApp.app` product.
3. Launch `AIInstruments` (macOS app).
4. Drop `TestApp.app` into AIInstruments.
5. Review issues and scores for all eight instruments.
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

## Feedback and contribution

I'm always open to receiving feedback and contribution to my project so please feel free to open Pull Requests, raise Issues or reach out to me on X https://x.com/dammarkowski. Thanks!
