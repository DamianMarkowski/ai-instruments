import Foundation

/// Analyzes iOS app binaries for Swift concurrency safety issues.
///
/// Detection categories:
/// - Sendable conformance gaps
/// - Actor isolation patterns
/// - MainActor usage analysis
/// - Data race potential
/// - Unsafe concurrent access
/// - Task lifecycle management
/// - Legacy concurrency patterns
final class ConcurrencyAnalyzer {

    private let analyzer: BinaryAnalyzer

    init(binaryAnalyzer: BinaryAnalyzer) {
        self.analyzer = binaryAnalyzer
    }

    func analyze() -> AnalysisResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        var issues: [DiagnosticIssue] = []

        // First check if the app uses Swift at all
        guard analyzer.usesSwift else {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            return AnalysisResult(
                instrument: .concurrency,
                issues: [DiagnosticIssue(
                    title: "No Swift Code Detected",
                    description: "The binary does not appear to contain Swift code. Swift Concurrency analysis requires Swift.",
                    severity: .info,
                    instrument: .concurrency,
                    category: "Prerequisites",
                    recommendation: "This instrument is designed for Swift-based applications. If your app uses Objective-C exclusively, concurrency issues should be audited using traditional thread safety tools.",
                    impact: "N/A"
                )],
                summary: "Swift code not detected in binary. Concurrency analysis not applicable.",
                score: 100,
                analysisTimeSeconds: elapsed
            )
        }

        issues.append(contentsOf: analyzeSendableConformance())
        issues.append(contentsOf: analyzeActorIsolation())
        issues.append(contentsOf: analyzeMainActorUsage())
        issues.append(contentsOf: analyzeDataRacePotential())
        issues.append(contentsOf: analyzeUnsafeConcurrentAccess())
        issues.append(contentsOf: analyzeTaskManagement())
        issues.append(contentsOf: analyzeLegacyConcurrency())
        issues.append(contentsOf: analyzeAsyncAwaitPatterns())
        issues.append(contentsOf: analyzeGlobalState())

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let score = calculateScore(issues: issues)

        return AnalysisResult(
            instrument: .concurrency,
            issues: issues.sorted { $0.severity < $1.severity },
            summary: generateSummary(issues: issues, score: score),
            score: score,
            analysisTimeSeconds: elapsed,
            metadata: [
                "usesSwiftConcurrency": "\(analyzer.usesSwiftConcurrency)",
                "swiftTypeCount": "\(analyzer.swiftTypeCount)",
                "objcClassCount": "\(analyzer.objcClassCount)"
            ]
        )
    }

    // MARK: - Sendable Conformance Analysis

    private func analyzeSendableConformance() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let sendableSymbols = analyzer.findSymbols(matchingAny: [
            "Sendable", "sendable", "UnsafeSendable", "@Sendable"
        ])

        let asyncSymbols = analyzer.findSymbols(matchingAny: [
            "async", "Task", "TaskGroup", "withCheckedContinuation",
            "withUnsafeContinuation", "AsyncSequence", "AsyncStream"
        ])

        let totalTypes = analyzer.swiftTypeCount + analyzer.objcClassCount

        if asyncSymbols.count > 5 && sendableSymbols.count < asyncSymbols.count / 3 {
            issues.append(DiagnosticIssue(
                title: "Low Sendable Adoption with High Async Usage",
                description: "Found \(asyncSymbols.count) async/concurrency patterns but only \(sendableSymbols.count) Sendable conformance(s). Types passed across concurrency boundaries should conform to Sendable.",
                severity: .warning,
                instrument: .concurrency,
                category: "Sendable Conformance",
                recommendation: "Audit types that cross concurrency boundaries and add `Sendable` conformance. Use value types (structs/enums) which are implicitly Sendable, or mark classes as `final class` with `@unchecked Sendable` if thread safety is manually managed.",
                impact: "Non-Sendable types passed across concurrency boundaries can cause data races. Swift 6 will enforce Sendable checking, making this a future compatibility issue.",
                confidence: analyzer.confidenceScore(evidenceCount: asyncSymbols.count, lowThreshold: 5, highThreshold: 20),
                relatedSymbols: Array(asyncSymbols.prefix(8).map(\.name)),
                details: [
                    .init(key: "Async Patterns", value: "\(asyncSymbols.count)"),
                    .init(key: "Sendable Conformances", value: "\(sendableSymbols.count)"),
                    .init(key: "Total Types", value: "\(totalTypes)")
                ]
            ))
        }

        // Check for @unchecked Sendable (potential safety gaps)
        let uncheckedSendable = analyzer.findSymbols(matchingAny: ["UnsafeSendable", "uncheckedSendable"])

        if uncheckedSendable.count > 3 {
            issues.append(DiagnosticIssue(
                title: "Frequent @unchecked Sendable Usage",
                description: "Found \(uncheckedSendable.count) uses of @unchecked Sendable. This bypasses the compiler's data race safety checks.",
                severity: .warning,
                instrument: .concurrency,
                category: "Sendable Conformance",
                recommendation: "Review each `@unchecked Sendable` conformance to ensure thread safety is properly managed. Consider refactoring to use value types or actors instead of manually managing thread safety.",
                impact: "@unchecked Sendable tells the compiler to trust that the type is thread-safe, but bugs in the manual synchronization won't be caught at compile time.",
                confidence: 0.75,
                relatedSymbols: Array(uncheckedSendable.prefix(5).map(\.name))
            ))
        }

        return issues
    }

    // MARK: - Actor Isolation Analysis

    private func analyzeActorIsolation() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let actorSymbols = analyzer.findSymbols(matchingAny: [
            "actor ", "Actor", "isolated", "nonisolated"
        ])

        let globalActors = analyzer.findSymbols(matchingAny: [
            "GlobalActor", "globalActor"
        ])

        let mutableState = analyzer.findSymbols(matchingAny: [
            "modify", "setter", "set."
        ])

        if actorSymbols.count > 0 && mutableState.count > actorSymbols.count * 5 {
            issues.append(DiagnosticIssue(
                title: "Limited Actor Adoption for Mutable State",
                description: "Found \(actorSymbols.count) actor-related symbol(s) but \(mutableState.count) mutable state operations. Consider protecting more shared mutable state with actors.",
                severity: .info,
                instrument: .concurrency,
                category: "Actor Isolation",
                recommendation: "Identify shared mutable state that is accessed from multiple concurrency domains and encapsulate it in actors. Actors provide compile-time data race safety guarantees.",
                impact: "Mutable state not protected by actors or other synchronization mechanisms is susceptible to data races in concurrent code.",
                confidence: 0.5,
                relatedSymbols: Array(actorSymbols.prefix(5).map(\.name)),
                details: [
                    .init(key: "Actor Symbols", value: "\(actorSymbols.count)"),
                    .init(key: "Mutable State Ops", value: "\(mutableState.count)"),
                    .init(key: "Global Actors", value: "\(globalActors.count)")
                ]
            ))
        }

        return issues
    }

    // MARK: - MainActor Usage Analysis

    private func analyzeMainActorUsage() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let mainActorSymbols = analyzer.findSymbols(matchingAny: [
            "MainActor", "mainActor", "@MainActor"
        ])

        let uiSymbols = analyzer.findSymbols(matchingAny: [
            "UIView", "UILabel", "UIButton", "UITableView", "UICollectionView",
            "UITextField", "UITextView", "UIImageView", "UIStackView",
            "SwiftUI", "View.body", "some View"
        ])

        let viewControllers = analyzer.findViewControllerClasses()

        let asyncSymbols = analyzer.findSymbols(matchingAny: [
            "async", "Task {", "Task.init", "withCheckedContinuation"
        ])

        if uiSymbols.count > 10 && mainActorSymbols.count < 3 && asyncSymbols.count > 5 {
            issues.append(DiagnosticIssue(
                title: "UI Code with Limited @MainActor Annotation",
                description: "Found \(uiSymbols.count) UI-related symbols and \(asyncSymbols.count) async patterns, but only \(mainActorSymbols.count) @MainActor annotations. UI updates from async contexts require MainActor isolation.",
                severity: .warning,
                instrument: .concurrency,
                category: "MainActor Isolation",
                recommendation: "Annotate view controllers and UI-updating classes with `@MainActor`. Use `@MainActor` on methods that update the UI. When calling UI code from async contexts, use `await MainActor.run { }` or `@MainActor` closures.",
                impact: "UI updates performed off the main thread cause undefined behavior, visual glitches, and crashes. @MainActor provides compile-time enforcement of main thread access.",
                confidence: analyzer.confidenceScore(evidenceCount: asyncSymbols.count, lowThreshold: 3, highThreshold: 15),
                relatedSymbols: Array(mainActorSymbols.prefix(3).map(\.name) + viewControllers.prefix(5)),
                details: [
                    .init(key: "UI Symbols", value: "\(uiSymbols.count)"),
                    .init(key: "@MainActor Uses", value: "\(mainActorSymbols.count)"),
                    .init(key: "Async Patterns", value: "\(asyncSymbols.count)"),
                    .init(key: "View Controllers", value: "\(viewControllers.count)")
                ]
            ))
        }

        // Check for DispatchQueue.main.async (legacy pattern)
        let mainQueueDispatches = analyzer.findSymbols(matchingAny: [
            "DispatchQueue.main", "dispatch_get_main_queue"
        ])

        if mainQueueDispatches.count > 5 && analyzer.usesSwiftConcurrency {
            issues.append(DiagnosticIssue(
                title: "Legacy Main Queue Dispatching with Swift Concurrency",
                description: "Found \(mainQueueDispatches.count) DispatchQueue.main usage(s) alongside Swift Concurrency. Mixing legacy and modern concurrency patterns can lead to subtle issues.",
                severity: .info,
                instrument: .concurrency,
                category: "MainActor Isolation",
                recommendation: "Migrate from `DispatchQueue.main.async { }` to `@MainActor` annotations or `MainActor.run { }`. This provides better integration with Swift's structured concurrency model.",
                impact: "Mixing GCD and Swift Concurrency can cause unexpected ordering issues and makes the concurrency model harder to reason about.",
                confidence: 0.6,
                relatedSymbols: Array(mainQueueDispatches.prefix(5).map(\.name))
            ))
        }

        return issues
    }

    // MARK: - Data Race Potential Analysis

    private func analyzeDataRacePotential() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        // Look for global/static mutable state
        let globalVars = analyzer.findSymbols(matchingAny: [
            "global_var", "static_var", "shared", "singleton", "instance"
        ])

        let staticMembers = analyzer.machOInfo.symbols.filter {
            ($0.name.contains("static") || $0.name.contains("Static")) &&
            ($0.name.contains("var") || $0.name.contains("modify") || $0.name.contains("setter"))
        }

        let lockSymbols = analyzer.findSymbols(matchingAny: [
            "NSLock", "NSRecursiveLock", "os_unfair_lock", "pthread_mutex",
            "DispatchSemaphore", "OSAllocatedUnfairLock"
        ])

        let totalMutableGlobals = globalVars.count + staticMembers.count

        if totalMutableGlobals > 5 && lockSymbols.count < totalMutableGlobals / 3 {
            issues.append(DiagnosticIssue(
                title: "Potentially Unprotected Shared Mutable State",
                description: "Found \(totalMutableGlobals) global/static mutable state pattern(s) but only \(lockSymbols.count) synchronization primitive(s). Shared mutable state without synchronization causes data races.",
                severity: .warning,
                instrument: .concurrency,
                category: "Data Race Risk",
                recommendation: "Protect shared mutable state with actors, locks, or other synchronization primitives. Prefer actors for new code. For existing code, use `OSAllocatedUnfairLock` (iOS 16+) or `NSLock` to synchronize access.",
                impact: "Data races cause non-deterministic behavior, memory corruption, and crashes that are extremely difficult to reproduce and debug.",
                confidence: 0.6,
                relatedSymbols: Array((globalVars + staticMembers).prefix(8).map(\.name)),
                details: [
                    .init(key: "Global/Static Mutable State", value: "\(totalMutableGlobals)"),
                    .init(key: "Synchronization Primitives", value: "\(lockSymbols.count)"),
                    .init(key: "Protection Ratio", value: lockSymbols.count > 0 ? "\(totalMutableGlobals / lockSymbols.count):1" : "None")
                ]
            ))
        }

        return issues
    }

    // MARK: - Unsafe Concurrent Access

    private func analyzeUnsafeConcurrentAccess() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let unsafeSymbols = analyzer.findSymbols(matchingAny: [
            "UnsafeMutablePointer", "UnsafeMutableRawPointer",
            "UnsafeMutableBufferPointer", "UnsafeRawPointer",
            "UnsafeMutableRawBufferPointer", "Unmanaged",
            "unsafeBitCast", "withUnsafeMutablePointer"
        ])

        if unsafeSymbols.count > 5 {
            issues.append(DiagnosticIssue(
                title: "Unsafe Pointer Usage in Concurrent Context",
                description: "Found \(unsafeSymbols.count) unsafe pointer/memory operation(s). Unsafe operations bypass Swift's safety guarantees and are especially dangerous in concurrent code.",
                severity: unsafeSymbols.count > 15 ? .warning : .info,
                instrument: .concurrency,
                category: "Unsafe Access",
                recommendation: "Minimize unsafe pointer usage. When necessary, ensure all unsafe pointer access is properly synchronized. Consider using `withUnsafeBufferPointer` scoped access instead of storing pointers.",
                impact: "Unsafe pointer operations in concurrent code can cause memory corruption, use-after-free bugs, and data races that are invisible to the compiler.",
                confidence: 0.55,
                relatedSymbols: Array(unsafeSymbols.prefix(8).map(\.name)),
                details: [
                    .init(key: "Unsafe Operations", value: "\(unsafeSymbols.count)")
                ]
            ))
        }

        // Check for Unmanaged usage
        let unmanagedSymbols = analyzer.findSymbols(matching: "Unmanaged")

        if unmanagedSymbols.count > 2 {
            issues.append(DiagnosticIssue(
                title: "Unmanaged Memory References",
                description: "Found \(unmanagedSymbols.count) Unmanaged reference(s). These bypass ARC and require manual memory management, increasing the risk of leaks and use-after-free in concurrent code.",
                severity: .info,
                instrument: .concurrency,
                category: "Unsafe Access",
                recommendation: "Replace Unmanaged references with proper ARC-managed references where possible. If Unmanaged is required for C interop, ensure the lifecycle is clearly documented and synchronization is in place.",
                impact: "Unmanaged references can lead to use-after-free or double-free bugs, especially when objects are accessed from multiple threads.",
                confidence: 0.6,
                relatedSymbols: Array(unmanagedSymbols.prefix(5).map(\.name))
            ))
        }

        return issues
    }

    // MARK: - Task Management Analysis

    private func analyzeTaskManagement() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let taskCreations = analyzer.findSymbols(matchingAny: [
            "Task.init", "Task {", "Task.detached", "TaskGroup",
            "withTaskGroup", "withThrowingTaskGroup"
        ])

        let taskCancellations = analyzer.findSymbols(matchingAny: [
            "cancel()", "Task.cancel", "isCancelled", "checkCancellation",
            "withTaskCancellationHandler"
        ])

        if taskCreations.count > 5 && taskCancellations.count == 0 {
            issues.append(DiagnosticIssue(
                title: "Tasks Without Cancellation Support",
                description: "Found \(taskCreations.count) task creation(s) but no cancellation handling. Long-running tasks should support cooperative cancellation.",
                severity: .info,
                instrument: .concurrency,
                category: "Task Management",
                recommendation: "Implement cancellation checking in long-running tasks using `Task.checkCancellation()` or `Task.isCancelled`. Store task handles and cancel them when the owning context is dismissed or deallocated.",
                impact: "Tasks without cancellation support continue running even after the initiating context (e.g., view controller) is dismissed, wasting resources and potentially causing unexpected side effects.",
                confidence: 0.6,
                relatedSymbols: Array(taskCreations.prefix(5).map(\.name)),
                details: [
                    .init(key: "Task Creations", value: "\(taskCreations.count)"),
                    .init(key: "Cancellation Handlers", value: "\(taskCancellations.count)")
                ]
            ))
        }

        // Check for Task.detached (often misused)
        let detachedTasks = analyzer.findSymbols(matching: "detached")

        if detachedTasks.count > 3 {
            issues.append(DiagnosticIssue(
                title: "Frequent Use of Detached Tasks",
                description: "Found \(detachedTasks.count) detached task pattern(s). Detached tasks don't inherit the parent task's priority, local values, or actor context.",
                severity: .info,
                instrument: .concurrency,
                category: "Task Management",
                recommendation: "Prefer unstructured `Task { }` over `Task.detached { }` unless you specifically need to escape the current actor context. Detached tasks lose structured concurrency benefits including automatic cancellation propagation.",
                impact: "Detached tasks run independently of the parent task, making it harder to reason about execution order, cancellation, and error propagation.",
                confidence: 0.65,
                relatedSymbols: Array(detachedTasks.prefix(5).map(\.name))
            ))
        }

        return issues
    }

    // MARK: - Legacy Concurrency Patterns

    private func analyzeLegacyConcurrency() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let gcdSymbols = analyzer.findSymbols(matchingAny: [
            "dispatch_async", "dispatch_sync", "dispatch_barrier",
            "dispatch_group", "dispatch_semaphore",
            "DispatchQueue.global", "DispatchQueue.async", "DispatchGroup"
        ])

        let threadSymbols = analyzer.findSymbols(matchingAny: [
            "NSThread", "Thread.init", "pthread_create", "detachNewThread"
        ])

        if (gcdSymbols.count > 10 || threadSymbols.count > 2) && analyzer.usesSwiftConcurrency {
            issues.append(DiagnosticIssue(
                title: "Mixed Concurrency Models",
                description: "Found \(gcdSymbols.count) GCD patterns and \(threadSymbols.count) thread patterns alongside Swift Concurrency. Mixing concurrency models increases complexity and bug risk.",
                severity: .warning,
                instrument: .concurrency,
                category: "Legacy Patterns",
                recommendation: "Gradually migrate from GCD and raw threads to Swift Concurrency (async/await, actors, task groups). Use `withCheckedContinuation` to bridge legacy async APIs to async/await.",
                impact: "Mixed concurrency models make it harder to reason about thread safety, increase the risk of priority inversions, and prevent the runtime from optimizing task scheduling.",
                confidence: 0.65,
                relatedSymbols: Array((gcdSymbols + threadSymbols).prefix(8).map(\.name)),
                details: [
                    .init(key: "GCD Patterns", value: "\(gcdSymbols.count)"),
                    .init(key: "Thread Patterns", value: "\(threadSymbols.count)"),
                    .init(key: "Uses Swift Concurrency", value: "\(analyzer.usesSwiftConcurrency)")
                ]
            ))
        }

        // Check for dispatch_sync (deadlock risk)
        let syncDispatches = analyzer.findSymbols(matchingAny: ["dispatch_sync", "DispatchQueue.sync"])

        if syncDispatches.count > 3 {
            issues.append(DiagnosticIssue(
                title: "Synchronous Dispatch Usage (Deadlock Risk)",
                description: "Found \(syncDispatches.count) synchronous dispatch call(s). sync dispatch to the current queue causes deadlocks.",
                severity: .warning,
                instrument: .concurrency,
                category: "Legacy Patterns",
                recommendation: "Replace `DispatchQueue.sync` with `async` where possible. If synchronous access is needed, use actors or locks instead. Never call `sync` on the current queue.",
                impact: "Synchronous dispatches can cause deadlocks when dispatching to the current queue, and can cause priority inversions when dispatching to lower-priority queues.",
                confidence: 0.7,
                relatedSymbols: Array(syncDispatches.prefix(5).map(\.name))
            ))
        }

        return issues
    }

    // MARK: - Async/Await Pattern Analysis

    private func analyzeAsyncAwaitPatterns() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let continuationSymbols = analyzer.findSymbols(matchingAny: [
            "withCheckedContinuation", "withCheckedThrowingContinuation",
            "withUnsafeContinuation", "withUnsafeThrowingContinuation"
        ])

        let unsafeContinuations = analyzer.findSymbols(matchingAny: [
            "withUnsafeContinuation", "withUnsafeThrowingContinuation"
        ])

        if unsafeContinuations.count > 3 {
            issues.append(DiagnosticIssue(
                title: "Unsafe Continuations Usage",
                description: "Found \(unsafeContinuations.count) unsafe continuation(s). Unlike checked continuations, unsafe continuations don't detect misuse at runtime.",
                severity: .info,
                instrument: .concurrency,
                category: "Async Patterns",
                recommendation: "Prefer `withCheckedContinuation` and `withCheckedThrowingContinuation` during development. Unsafe continuations provide no runtime protection against being resumed multiple times or never resumed.",
                impact: "Unsafe continuations that are resumed more than once cause undefined behavior. Continuations that are never resumed leak the enclosing task forever.",
                confidence: 0.7,
                relatedSymbols: Array(unsafeContinuations.prefix(5).map(\.name)),
                details: [
                    .init(key: "Total Continuations", value: "\(continuationSymbols.count)"),
                    .init(key: "Unsafe Continuations", value: "\(unsafeContinuations.count)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Global State Analysis

    private func analyzeGlobalState() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        // Check for singleton patterns
        let singletonPatterns = analyzer.findSymbols(matchingAny: [
            ".shared", "sharedInstance", "default", "singleton"
        ])

        let singletonClasses = Set(singletonPatterns.compactMap { symbol -> String? in
            let components = symbol.name.split(separator: ".")
            return components.count >= 2 ? String(components[0]) : nil
        })

        if singletonClasses.count > 5 {
            issues.append(DiagnosticIssue(
                title: "Extensive Singleton Pattern Usage",
                description: "Found approximately \(singletonClasses.count) singleton/shared instance patterns. Singletons are global mutable state and require careful thread-safety considerations.",
                severity: .info,
                instrument: .concurrency,
                category: "Global State",
                recommendation: "Consider migrating singletons to actors for thread-safe global state. If singletons must remain classes, ensure all mutable properties are protected with synchronization. Consider using dependency injection to reduce singleton reliance.",
                impact: "Singletons accessed from multiple threads without synchronization are a primary source of data races. They also make testing and reasoning about code more difficult.",
                confidence: 0.55,
                relatedSymbols: Array(singletonClasses.prefix(8)),
                details: [
                    .init(key: "Singleton Patterns", value: "\(singletonClasses.count)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Scoring

    private func calculateScore(issues: [DiagnosticIssue]) -> Int {
        let totalPenalty = issues.reduce(0) { $0 + $1.severity.weight }
        return max(0, 100 - totalPenalty)
    }

    private func generateSummary(issues: [DiagnosticIssue], score: Int) -> String {
        if issues.isEmpty {
            return "No Swift Concurrency issues detected. Your app appears to follow good concurrency practices."
        }

        let critical = issues.filter { $0.severity == .critical }.count
        let warnings = issues.filter { $0.severity == .warning }.count

        if critical > 0 {
            return "Found \(critical) critical and \(warnings) warning-level concurrency issue(s). These patterns have high data race potential and should be addressed immediately."
        } else if warnings > 0 {
            return "Found \(warnings) warning-level concurrency pattern(s) that may lead to data races or threading issues. Review recommended for Swift 6 compatibility."
        } else {
            return "Found \(issues.count) informational concurrency finding(s). These are patterns worth reviewing to improve concurrency safety and prepare for stricter Swift 6 checking."
        }
    }
}
