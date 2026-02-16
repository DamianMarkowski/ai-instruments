import Foundation

/// Analyzes iOS app binaries for potential memory leak patterns.
///
/// Detection categories:
/// - Strong delegate references (missing `weak`)
/// - Closure/block capture cycles
/// - NotificationCenter observer lifecycle
/// - Timer retain cycles
/// - Circular reference chains
/// - Core Foundation retain/release imbalance
final class LeaksAnalyzer {

    private let analyzer: BinaryAnalyzer

    init(binaryAnalyzer: BinaryAnalyzer) {
        self.analyzer = binaryAnalyzer
    }

    func analyze() -> AnalysisResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        var issues: [DiagnosticIssue] = []

        issues.append(contentsOf: analyzeStrongDelegates())
        issues.append(contentsOf: analyzeClosureCaptures())
        issues.append(contentsOf: analyzeNotificationObservers())
        issues.append(contentsOf: analyzeTimerRetainCycles())
        issues.append(contentsOf: analyzeCircularReferences())
        issues.append(contentsOf: analyzeCoreFoundationRetain())
        issues.append(contentsOf: analyzeBlockBasedAPIs())
        issues.append(contentsOf: analyzeViewControllerLifecycle())

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let score = calculateScore(issues: issues)

        return AnalysisResult(
            instrument: .leaks,
            issues: issues.sorted { $0.severity < $1.severity },
            summary: generateSummary(issues: issues, score: score),
            score: score,
            analysisTimeSeconds: elapsed,
            metadata: [
                "totalSymbolsAnalyzed": "\(analyzer.machOInfo.symbols.count)",
                "classesAnalyzed": "\(analyzer.allClassNames.count)",
                "selectorsAnalyzed": "\(analyzer.machOInfo.objcSelectors.count)",
                "delegatePatterns": "\(analyzer.findSymbols(matching: "delegate").count)"
            ]
        )
    }

    // MARK: - Strong Delegate Analysis

    private func analyzeStrongDelegates() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        // Look for delegate properties that may not be weak
        let delegateSymbols = analyzer.findSymbols(matchingAny: [
            "delegate", "Delegate", "dataSource", "DataSource"
        ])

        // Also check ObjC selectors for delegate-related patterns
        let delegateSelectors = analyzer.findSelectors(matchingAny: [
            "setDelegate", "setDataSource", "delegate", "dataSource"
        ])

        // Find setters for delegate properties:
        //   ObjC style: contains "set" + "Delegate"/"dataSource"
        //   Swift style: symbol ends with "vs" (setter) or "vM" (modify accessor)
        let delegateSetters = delegateSymbols.filter { sym in
            let name = sym.name
            let hasDelegateKey = name.contains("Delegate") || name.contains("delegate") ||
                name.contains("DataSource") || name.contains("dataSource")
            guard hasDelegateKey else { return false }
            return name.contains("set") || name.hasSuffix("vs") || name.hasSuffix("vM")
        }

        // ObjC setter selectors (e.g. "setDelegate:")
        let delegateSetterSelectors = delegateSelectors.filter {
            $0.lowercased().hasPrefix("set")
        }

        // Check if there are corresponding weak references
        let weakSymbols = analyzer.findSymbols(matchingAny: ["weak", ".weak_"])

        let potentiallyStrongDelegates = delegateSetters.filter { _ in
            !weakSymbols.contains { $0.name.contains("delegate") || $0.name.contains("Delegate") }
        }

        let totalEvidence = potentiallyStrongDelegates.count + delegateSetterSelectors.count

        if totalEvidence > 0 {
            let viewControllers = analyzer.findAllViewControllerClasses()
            let isInVC = !viewControllers.isEmpty

            issues.append(DiagnosticIssue(
                title: "Potential Strong Delegate References",
                description: "Found \(totalEvidence) delegate/dataSource property setter(s) that may use strong references. Strong delegate references are a common source of retain cycles.",
                severity: isInVC ? .warning : .info,
                instrument: .leaks,
                category: "Strong Delegates",
                recommendation: "Ensure all delegate and dataSource properties are declared as `weak`. Use `weak var delegate: SomeProtocol?` to prevent retain cycles between objects and their delegates.",
                impact: "Strong delegate references create mutual strong references between an object and its delegate, preventing both from being deallocated.",
                confidence: analyzer.confidenceScore(evidenceCount: totalEvidence, lowThreshold: 1, highThreshold: 5),
                relatedSymbols: Array(potentiallyStrongDelegates.prefix(10).map(\.name)),
                details: [
                    .init(key: "Delegate Setters Found", value: "\(totalEvidence)"),
                    .init(key: "View Controllers", value: "\(viewControllers.count)"),
                    .init(key: "Risk Level", value: isInVC ? "High - ViewController involvement" : "Medium")
                ]
            ))
        }

        return issues
    }

    // MARK: - Closure Capture Analysis

    private func analyzeClosureCaptures() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        // Look for block/closure-related symbols
        let blockSymbols = analyzer.findSymbols(matchingAny: [
            "block_invoke", "block_copy", "block_destroy",
            "__copy_helper_block", "__destroy_helper_block"
        ])

        // Swift closures in mangled names use "fU" (closure), "fU_" (closure #1),
        // "fU0_" (closure #2), etc. Also check for demangled "closure #" patterns.
        let closureSymbols = analyzer.findSymbols(matchingAny: [
            "closure #", "implicit closure"
        ])

        // Also detect Swift closures by their mangled signature (fU indicates a closure)
        let swiftClosures = analyzer.machOInfo.symbols.filter {
            $0.name.contains("fU_") || $0.name.contains("fU0_") || $0.name.contains("fU1_")
        }

        let totalClosures = blockSymbols.count + closureSymbols.count + swiftClosures.count

        if totalClosures > 5 {
            // Look for closures that reference self patterns
            let selfCaptures = analyzer.findSymbols(matchingAny: [
                "objectdestroy", "swift_release", "swift_retain"
            ])

            let captureRisk = selfCaptures.count > totalClosures / 2

            if captureRisk {
                issues.append(DiagnosticIssue(
                    title: "High Closure Density with Capture Risk",
                    description: "Found \(totalClosures) closures/blocks with significant retain/release traffic (\(selfCaptures.count) reference operations). This pattern suggests closures that capture `self` strongly.",
                    severity: .warning,
                    instrument: .leaks,
                    category: "Closure Captures",
                    recommendation: "Review closures for strong self captures. Use `[weak self]` or `[unowned self]` capture lists in closures that are stored as properties or passed to long-lived operations (e.g., completion handlers, observation blocks).",
                    impact: "Closures that strongly capture `self` while also being stored by `self` (directly or indirectly) create retain cycles that prevent deallocation.",
                    confidence: 0.65,
                    relatedSymbols: Array(blockSymbols.prefix(5).map(\.name) + closureSymbols.prefix(5).map(\.name)),
                    details: [
                        .init(key: "ObjC Blocks", value: "\(blockSymbols.count)"),
                        .init(key: "Swift Closures", value: "\(closureSymbols.count)"),
                        .init(key: "Reference Operations", value: "\(selfCaptures.count)")
                    ]
                ))
            }
        }

        // Check for escaping closures stored in properties
        let escapingPatterns = analyzer.findSymbols(matchingAny: [
            "withoutActuallyEscaping", "escaping"
        ])

        if escapingPatterns.count > 5 {
            issues.append(DiagnosticIssue(
                title: "Escaping Closures Detected",
                description: "Found \(escapingPatterns.count) escaping closure patterns. Escaping closures that capture `self` are a frequent source of retain cycles.",
                severity: .info,
                instrument: .leaks,
                category: "Closure Captures",
                recommendation: "Verify that all escaping closures use `[weak self]` capture lists unless the closure's lifetime is guaranteed to be shorter than the captured object's lifetime.",
                impact: "Escaping closures outlive the function call scope and can retain captured objects indefinitely.",
                confidence: 0.55,
                relatedSymbols: Array(escapingPatterns.prefix(5).map(\.name))
            ))
        }

        return issues
    }

    // MARK: - Notification Observer Analysis

    private func analyzeNotificationObservers() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        // Search both symbols and ObjC selectors for observer patterns
        let addObserverSymbols = analyzer.findSymbols(matchingAny: [
            "addObserver", "addObserverForName", "NotificationCenter"
        ])
        let addObserverSelectors = analyzer.findSelectors(matchingAny: [
            "addObserver"
        ])
        let totalAdd = addObserverSymbols.count + addObserverSelectors.count

        let removeObserverSymbols = analyzer.findSymbols(matchingAny: [
            "removeObserver"
        ])
        let removeObserverSelectors = analyzer.findSelectors(matchingAny: [
            "removeObserver"
        ])
        let totalRemove = removeObserverSymbols.count + removeObserverSelectors.count

        if totalAdd > totalRemove {
            let imbalance = totalAdd - totalRemove

            issues.append(DiagnosticIssue(
                title: "NotificationCenter Observer Imbalance",
                description: "Found \(totalAdd) addObserver calls but only \(totalRemove) removeObserver calls. This suggests \(imbalance) observer(s) may not be properly cleaned up.",
                severity: imbalance > 3 ? .warning : .info,
                instrument: .leaks,
                category: "Notification Observers",
                recommendation: "Ensure every NotificationCenter.addObserver has a corresponding removeObserver, typically in deinit or viewWillDisappear. Consider using the block-based API with `NotificationCenter.default.addObserver(forName:object:queue:using:)` and storing the returned token for later removal.",
                impact: "Orphaned notification observers can prevent objects from being deallocated and may cause crashes when notifications are posted to deallocated objects.",
                confidence: analyzer.confidenceScore(evidenceCount: imbalance, lowThreshold: 1, highThreshold: 5),
                relatedSymbols: Array(addObserverSymbols.prefix(5).map(\.name)),
                details: [
                    .init(key: "addObserver Calls", value: "\(totalAdd)"),
                    .init(key: "removeObserver Calls", value: "\(totalRemove)"),
                    .init(key: "Imbalance", value: "\(imbalance)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Timer Retain Cycle Analysis

    private func analyzeTimerRetainCycles() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        // Search symbols for timer patterns
        let timerSymbols = analyzer.findSymbols(matchingAny: [
            "scheduledTimer", "NSTimer", "timerWithTimeInterval",
            "scheduledTimerWithTimeInterval"
        ])

        // Also search ObjC selectors (Swift calls to Timer/NSTimer generate selectors)
        let timerSelectors = analyzer.findSelectors(matchingAny: [
            "scheduledTimer", "timerWithTimeInterval"
        ])

        let totalTimer = timerSymbols.count + timerSelectors.count

        let invalidateSymbols = analyzer.findSymbols(matchingAny: [
            "invalidate"
        ])
        let invalidateSelectors = analyzer.findSelectors(matchingAny: [
            "invalidate"
        ])
        let totalInvalidate = invalidateSymbols.count + invalidateSelectors.count

        if totalTimer > 0 {
            let repeatingTimerRisk = totalTimer > totalInvalidate

            issues.append(DiagnosticIssue(
                title: "Timer Usage Detected - Potential Retain Cycle",
                description: "Found \(totalTimer) timer creation pattern(s). NSTimer/Timer strongly retains its target, which can create retain cycles if the target also retains the timer.",
                severity: repeatingTimerRisk ? .warning : .suggestion,
                instrument: .leaks,
                category: "Timer Retain Cycles",
                recommendation: "Use `Timer.scheduledTimer(withTimeInterval:repeats:block:)` with `[weak self]` capture, or use a proxy/wrapper pattern. Always invalidate timers in the appropriate lifecycle method (e.g., `viewWillDisappear` for view controllers).",
                impact: "Timer retain cycles are one of the most common memory leaks in iOS apps. The timer retains its target, and if the target retains the timer, neither can be deallocated.",
                confidence: 0.7,
                relatedSymbols: Array(timerSymbols.prefix(5).map(\.name)),
                details: [
                    .init(key: "Timer Creations", value: "\(totalTimer)"),
                    .init(key: "Invalidate Calls", value: "\(totalInvalidate)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Circular Reference Analysis

    private func analyzeCircularReferences() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        // Use combined ObjC + Swift class names to cover pure Swift classes too
        let classes = analyzer.allClassNames
        let viewControllers = analyzer.findAllViewControllerClasses()

        // Check for coordinator/router patterns (common retain cycle source)
        let coordinators = classes.filter {
            $0.contains("Coordinator") || $0.contains("Router") || $0.contains("Navigator")
        }

        if !coordinators.isEmpty && !viewControllers.isEmpty {
            issues.append(DiagnosticIssue(
                title: "Coordinator-ViewController Pattern Detected",
                description: "Found \(coordinators.count) coordinator/router class(es) alongside \(viewControllers.count) view controller(s). This architecture pattern can introduce retain cycles if coordinators and view controllers hold strong references to each other.",
                severity: .info,
                instrument: .leaks,
                category: "Circular References",
                recommendation: "Ensure view controllers hold `weak` references to their coordinators. The coordinator should own (strongly retain) its child view controllers, while view controllers should use `weak` delegate references back to the coordinator.",
                impact: "Coordinator patterns where both the coordinator and view controller strongly reference each other prevent the entire navigation chain from being deallocated.",
                confidence: 0.6,
                relatedSymbols: Array((coordinators + viewControllers).prefix(10)),
                details: [
                    .init(key: "Coordinators/Routers", value: "\(coordinators.count)"),
                    .init(key: "View Controllers", value: "\(viewControllers.count)")
                ]
            ))
        }

        // Check for parent-child class patterns
        let managers = classes.filter {
            $0.contains("Manager") || $0.contains("Service") || $0.contains("Store")
        }

        if managers.count > 3 {
            issues.append(DiagnosticIssue(
                title: "Complex Object Graph Detected",
                description: "Found \(managers.count) manager/service/store classes. Complex object graphs with many interconnected services increase the risk of retain cycles.",
                severity: .suggestion,
                instrument: .leaks,
                category: "Circular References",
                recommendation: "Audit the ownership relationships between manager/service classes. Use dependency injection with `weak` references for cross-cutting concerns. Consider using a dependency injection container to manage object lifecycles.",
                impact: "Complex object graphs make it harder to reason about ownership and can hide retain cycles that only manifest under specific navigation paths.",
                confidence: 0.45,
                relatedSymbols: Array(managers.prefix(10))
            ))
        }

        return issues
    }

    // MARK: - Core Foundation Analysis

    private func analyzeCoreFoundationRetain() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let cfRetainSymbols = analyzer.findSymbols(matchingAny: [
            "CFRetain", "CGColorRetain", "CGPathRetain", "CGContextRetain"
        ])

        let cfReleaseSymbols = analyzer.findSymbols(matchingAny: [
            "CFRelease", "CGColorRelease", "CGPathRelease", "CGContextRelease"
        ])

        if cfRetainSymbols.count > cfReleaseSymbols.count + 2 {
            let imbalance = cfRetainSymbols.count - cfReleaseSymbols.count

            issues.append(DiagnosticIssue(
                title: "Core Foundation Retain/Release Imbalance",
                description: "Found \(cfRetainSymbols.count) CF retain operations but only \(cfReleaseSymbols.count) CF release operations. Core Foundation objects require manual memory management.",
                severity: .warning,
                instrument: .leaks,
                category: "CF Memory Management",
                recommendation: "Ensure every CFRetain has a matching CFRelease. Consider using `withExtendedLifetime` or transferring CF objects to ARC-managed Swift types as soon as possible using `takeRetainedValue()` or `takeUnretainedValue()`.",
                impact: "Core Foundation objects are not managed by ARC. Unbalanced retains will leak memory that cannot be reclaimed.",
                confidence: analyzer.confidenceScore(evidenceCount: imbalance),
                relatedSymbols: Array(cfRetainSymbols.prefix(5).map(\.name)),
                details: [
                    .init(key: "CF Retains", value: "\(cfRetainSymbols.count)"),
                    .init(key: "CF Releases", value: "\(cfReleaseSymbols.count)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Block-Based API Analysis

    private func analyzeBlockBasedAPIs() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        // Check for UIView animation blocks (common capture site) - search symbols + selectors
        let animationBlocks = analyzer.countAllEvidence(matchingAny: [
            "animateWithDuration", "UIViewPropertyAnimator"
        ])

        let networkBlocks = analyzer.countAllEvidence(matchingAny: [
            "dataTaskWith", "URLSession", "downloadTaskWith", "uploadTaskWith"
        ])

        let gcdBlocks = analyzer.countAllEvidence(matchingAny: [
            "dispatch_async", "dispatch_after", "DispatchQueue"
        ])

        let totalAsyncBlocks = animationBlocks + networkBlocks + gcdBlocks

        if totalAsyncBlocks > 3 {
            issues.append(DiagnosticIssue(
                title: "Heavy Asynchronous Block Usage",
                description: "Found extensive use of asynchronous APIs (\(totalAsyncBlocks) patterns): \(animationBlocks) animations, \(networkBlocks) network operations, \(gcdBlocks) GCD dispatches. Each async block is a potential capture site.",
                severity: .suggestion,
                instrument: .leaks,
                category: "Block Captures",
                recommendation: "Review completion handlers and async blocks for strong self captures. Use `[weak self]` in long-running operations. For short-lived operations (animations), strong captures are generally safe.",
                impact: "Asynchronous blocks that capture `self` keep the object alive until the operation completes, which may not be the desired behavior for dismissed view controllers or cancelled operations.",
                confidence: 0.5,
                details: [
                    .init(key: "Animation Blocks", value: "\(animationBlocks)"),
                    .init(key: "Network Blocks", value: "\(networkBlocks)"),
                    .init(key: "GCD Blocks", value: "\(gcdBlocks)")
                ]
            ))
        }

        return issues
    }

    // MARK: - ViewController Lifecycle Analysis

    private func analyzeViewControllerLifecycle() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let viewControllers = analyzer.findAllViewControllerClasses()
        let deinitSymbols = analyzer.findSymbols(matchingAny: ["deinit", "__deallocating_deinit"])

        if !viewControllers.isEmpty {
            let vcDeinits = deinitSymbols.filter { sym in
                viewControllers.contains { vc in sym.name.contains(vc) }
            }

            let vcWithoutDeinit = viewControllers.count - vcDeinits.count

            if vcWithoutDeinit > 0 && viewControllers.count > 2 {
                issues.append(DiagnosticIssue(
                    title: "View Controllers Without Explicit Cleanup",
                    description: "Found \(viewControllers.count) view controller(s) but deinit patterns were detected for only \(vcDeinits.count). The remaining \(vcWithoutDeinit) may lack explicit cleanup code in deinit.",
                    severity: .suggestion,
                    instrument: .leaks,
                    category: "ViewController Lifecycle",
                    recommendation: "Add deinit methods to view controllers to clean up observers, timers, and delegates. Even if cleanup isn't needed, a deinit with a print/log statement helps detect retain cycles during development.",
                    impact: "Without explicit cleanup in deinit, resources like notification observers and timers may not be released, and retain cycles become harder to detect.",
                    confidence: 0.5,
                    relatedSymbols: Array(viewControllers.prefix(10)),
                    details: [
                        .init(key: "Total View Controllers", value: "\(viewControllers.count)"),
                        .init(key: "With deinit", value: "\(vcDeinits.count)"),
                        .init(key: "Without deinit", value: "\(vcWithoutDeinit)")
                    ]
                ))
            }
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
            return "No potential memory leak patterns detected. Your app appears to follow good memory management practices."
        }

        let critical = issues.filter { $0.severity == .critical }.count
        let warnings = issues.filter { $0.severity == .warning }.count

        if critical > 0 {
            return "Found \(critical) critical and \(warnings) warning-level potential memory leak pattern(s). Immediate attention recommended to prevent memory growth and app termination."
        } else if warnings > 0 {
            return "Found \(warnings) warning-level potential memory leak pattern(s). Review recommended to ensure proper memory management and prevent leaks in production."
        } else {
            return "Found \(issues.count) informational finding(s) related to memory management. These are low-risk patterns worth reviewing for best practices."
        }
    }
}
