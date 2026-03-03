import Foundation

/// Analyzes iOS app binaries for patterns that cause UI hangs and main thread blocking.
///
/// Detection categories:
/// - Synchronous I/O on the main thread
/// - Heavy computation patterns
/// - Complex view hierarchy indicators
/// - TableView/CollectionView optimization
/// - Auto Layout complexity
/// - Main thread synchronization primitives
/// - Image decoding on main thread
/// - Core Data main thread usage
final class HangsAnalyzer {

    private let analyzer: BinaryAnalyzer

    init(binaryAnalyzer: BinaryAnalyzer) {
        self.analyzer = binaryAnalyzer
    }

    func analyze() -> AnalysisResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        var issues: [DiagnosticIssue] = []

        issues.append(contentsOf: analyzeSynchronousIO())
        issues.append(contentsOf: analyzeHeavyComputation())
        issues.append(contentsOf: analyzeViewHierarchy())
        issues.append(contentsOf: analyzeScrollViewOptimization())
        issues.append(contentsOf: analyzeAutoLayoutComplexity())
        issues.append(contentsOf: analyzeMainThreadLocking())
        issues.append(contentsOf: analyzeMainThreadDecoding())
        issues.append(contentsOf: analyzeCoreDataMainThread())

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let score = calculateScore(issues: issues)

        return AnalysisResult(
            instrument: .hangs,
            issues: issues.sorted { $0.severity < $1.severity },
            summary: generateSummary(issues: issues, score: score),
            score: score,
            analysisTimeSeconds: elapsed,
            metadata: [
                "viewControllerCount": "\(analyzer.findAllViewControllerClasses().count)",
                "syncIOPatterns": "\(analyzer.countAllEvidence(matchingAny: ["contentsOfFile", "dataWithContentsOfFile", "NSData"]))",
                "lockPatterns": "\(analyzer.countAllEvidence(matchingAny: ["NSLock", "pthread_mutex", "os_unfair_lock", "dispatch_sync"]))"
            ]
        )
    }

    // MARK: - Synchronous I/O Analysis

    private func analyzeSynchronousIO() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let syncFileCount = analyzer.countAllEvidence(matchingAny: [
            "contentsOfFile", "dataWithContentsOfFile",
            "stringWithContentsOfFile", "contentsOfDirectory",
            "attributesOfItem", "contentsAtPath"
        ])

        let syncNetworkCount = analyzer.countAllEvidence(matchingAny: [
            "sendSynchronousRequest", "dataWithContentsOfURL",
            "stringWithContentsOfURL", "contentsOfURL"
        ])

        let syncUserDefaultsCount = analyzer.countAllEvidence(matchingAny: [
            "synchronize", "UserDefaults"
        ])

        if syncFileCount > 5 {
            issues.append(DiagnosticIssue(
                title: "Frequent Synchronous File Operations",
                description: "Found \(syncFileCount) synchronous file I/O pattern(s). Synchronous file operations on the main thread block the UI until the disk read/write completes.",
                severity: .warning,
                instrument: .hangs,
                category: "Synchronous I/O",
                recommendation: "Move file operations to a background queue using `DispatchQueue.global().async` or Swift Concurrency. For UserDefaults, avoid calling `synchronize()` explicitly—the system syncs automatically.",
                impact: "Synchronous disk I/O on the main thread causes UI hangs proportional to file size and disk speed. On older devices or with large files, this can easily exceed the 250ms hang threshold.",
                confidence: analyzer.confidenceScore(evidenceCount: syncFileCount, lowThreshold: 3, highThreshold: 15),
                details: [
                    .init(key: "Sync File Ops", value: "\(syncFileCount)"),
                    .init(key: "Sync Network Ops", value: "\(syncNetworkCount)"),
                    .init(key: "UserDefaults Sync", value: "\(syncUserDefaultsCount)")
                ]
            ))
        }

        if syncNetworkCount > 0 {
            issues.append(DiagnosticIssue(
                title: "Synchronous Network Requests Detected",
                description: "Found \(syncNetworkCount) synchronous network request pattern(s). Synchronous network calls block the calling thread until the response arrives, which can take seconds.",
                severity: .critical,
                instrument: .hangs,
                category: "Synchronous I/O",
                recommendation: "Replace all synchronous network requests with asynchronous alternatives using `URLSession.dataTask` or async/await. Synchronous network requests are never appropriate on the main thread.",
                impact: "Synchronous network requests block the main thread for the entire request duration (potentially seconds). This causes the app to appear frozen and may trigger the watchdog termination (0x8BADF00D).",
                confidence: 0.85,
                details: [
                    .init(key: "Sync Network Ops", value: "\(syncNetworkCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Heavy Computation Analysis

    private func analyzeHeavyComputation() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let sortCount = analyzer.countAllEvidence(matchingAny: [
            "sort(", "sorted(", "sortDescriptors", "NSSortDescriptor"
        ])

        let filterMapCount = analyzer.countAllEvidence(matchingAny: [
            "filter(", "map(", "flatMap(", "compactMap(",
            "reduce(", "NSPredicate", "filteredArrayUsingPredicate"
        ])

        let regexCount = analyzer.countAllEvidence(matchingAny: [
            "NSRegularExpression", "regularExpression",
            "Regex", "matches(in:"
        ])

        let totalHeavyOps = sortCount + regexCount

        if totalHeavyOps > 10 {
            issues.append(DiagnosticIssue(
                title: "Heavy Collection Processing Detected",
                description: "Found \(totalHeavyOps) potentially expensive operation(s) (\(sortCount) sorts, \(regexCount) regex matches). If executed on the main thread with large datasets, these can cause hangs.",
                severity: .info,
                instrument: .hangs,
                category: "Heavy Computation",
                recommendation: "Move expensive collection operations to background queues, especially when operating on datasets larger than a few hundred items. Use `Task.detached(priority: .userInitiated)` for async processing.",
                impact: "Sorting, filtering, and regex matching have O(n log n) or worse complexity. On the main thread with thousands of items, these operations can exceed the hang threshold.",
                confidence: 0.5,
                details: [
                    .init(key: "Sort Operations", value: "\(sortCount)"),
                    .init(key: "Filter/Map Operations", value: "\(filterMapCount)"),
                    .init(key: "Regex Operations", value: "\(regexCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - View Hierarchy Analysis

    private func analyzeViewHierarchy() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let viewControllers = analyzer.findAllViewControllerClasses()
        let viewClasses = analyzer.allClassNames.filter {
            $0.hasSuffix("View") || $0.hasSuffix("Cell") || $0.hasSuffix("Button")
        }

        let stackViewCount = analyzer.countAllEvidence(matchingAny: [
            "UIStackView", "stackView"
        ])

        if viewClasses.count > 50 {
            issues.append(DiagnosticIssue(
                title: "Large Number of Custom View Types",
                description: "Found \(viewClasses.count) custom view/cell classes. A large number of custom views can indicate deep or complex view hierarchies that are expensive to lay out.",
                severity: viewClasses.count > 100 ? .warning : .info,
                instrument: .hangs,
                category: "View Hierarchy",
                recommendation: "Flatten view hierarchies where possible. Replace nested UIStackViews with manual layout or UICollectionViewCompositionalLayout. Use Instruments' View Hierarchy debugger to identify the deepest branches.",
                impact: "Deep view hierarchies cause exponential layout computation. Each layout pass traverses the entire hierarchy, and nested stack views compound this effect.",
                confidence: 0.45,
                relatedSymbols: Array(viewClasses.prefix(10)),
                details: [
                    .init(key: "Custom View Types", value: "\(viewClasses.count)"),
                    .init(key: "View Controllers", value: "\(viewControllers.count)"),
                    .init(key: "Stack Views", value: "\(stackViewCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - ScrollView Optimization Analysis

    private func analyzeScrollViewOptimization() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let tableViewCount = analyzer.countAllEvidence(matchingAny: [
            "UITableView", "tableView"
        ])

        let collectionViewCount = analyzer.countAllEvidence(matchingAny: [
            "UICollectionView", "collectionView"
        ])

        let prefetchCount = analyzer.countAllEvidence(matchingAny: [
            "prefetchDataSource", "UITableViewDataSourcePrefetching",
            "UICollectionViewDataSourcePrefetching", "prefetchItems",
            "prefetchRows"
        ])

        let cellRegistrationCount = analyzer.countAllEvidence(matchingAny: [
            "dequeueReusableCell", "register(", "cellForRow",
            "cellForItem"
        ])

        let totalScrollViews = tableViewCount + collectionViewCount

        if totalScrollViews > 3 && prefetchCount == 0 {
            issues.append(DiagnosticIssue(
                title: "Scroll Views Without Prefetching",
                description: "Found \(totalScrollViews) table/collection view pattern(s) but no prefetching implementation. Prefetching allows data loading to start before cells become visible.",
                severity: .info,
                instrument: .hangs,
                category: "Scroll Performance",
                recommendation: "Implement `UITableViewDataSourcePrefetching` or `UICollectionViewDataSourcePrefetching` to begin loading data (especially images and network content) before cells scroll into view.",
                impact: "Without prefetching, data loading starts only when cells become visible, causing frame drops during fast scrolling as the main thread waits for content.",
                confidence: 0.5,
                details: [
                    .init(key: "Table Views", value: "\(tableViewCount)"),
                    .init(key: "Collection Views", value: "\(collectionViewCount)"),
                    .init(key: "Prefetch Patterns", value: "\(prefetchCount)"),
                    .init(key: "Cell Registrations", value: "\(cellRegistrationCount)")
                ]
            ))
        }

        let diffableCount = analyzer.countAllEvidence(matchingAny: [
            "UICollectionViewDiffableDataSource",
            "UITableViewDiffableDataSource",
            "NSDiffableDataSourceSnapshot"
        ])

        if totalScrollViews > 5 && diffableCount == 0 {
            issues.append(DiagnosticIssue(
                title: "Scroll Views Without Diffable Data Sources",
                description: "Found \(totalScrollViews) table/collection view patterns but no diffable data source usage. Diffable data sources compute minimal diffs for animated updates.",
                severity: .suggestion,
                instrument: .hangs,
                category: "Scroll Performance",
                recommendation: "Adopt `UICollectionViewDiffableDataSource` or `UITableViewDiffableDataSource` for efficient, animated updates. Diffable data sources compute the minimum set of changes needed, avoiding full reloads.",
                impact: "Calling `reloadData()` discards all cell state and forces a complete re-render. Diffable data sources only update changed cells, improving both performance and animation quality.",
                confidence: 0.4,
                details: [
                    .init(key: "Scroll Views", value: "\(totalScrollViews)"),
                    .init(key: "Diffable Data Sources", value: "\(diffableCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Auto Layout Complexity Analysis

    private func analyzeAutoLayoutComplexity() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let constraintCount = analyzer.countAllEvidence(matchingAny: [
            "NSLayoutConstraint", "constraintEqualToAnchor",
            "addConstraint", "activateConstraints",
            "translatesAutoresizingMaskIntoConstraints"
        ])

        let priorityCount = analyzer.countAllEvidence(matchingAny: [
            "layoutPriority", "setContentHuggingPriority",
            "setContentCompressionResistancePriority", "UILayoutPriority"
        ])

        let intrinsicSizeCount = analyzer.countAllEvidence(matchingAny: [
            "intrinsicContentSize", "invalidateIntrinsicContentSize",
            "systemLayoutSizeFitting"
        ])

        if constraintCount > 20 && priorityCount > 5 {
            issues.append(DiagnosticIssue(
                title: "Complex Auto Layout Configuration",
                description: "Found \(constraintCount) constraint operations with \(priorityCount) priority adjustments. Complex constraint systems with many priority levels increase layout computation time.",
                severity: .info,
                instrument: .hangs,
                category: "Auto Layout",
                recommendation: "Simplify constraint hierarchies by using stack views for linear layouts or switching to manual frame calculation in performance-critical cells. Avoid breaking and re-creating constraints dynamically—toggle `isActive` instead.",
                impact: "Auto Layout's constraint solver has super-linear complexity. Each additional constraint and priority level increases the time for each layout pass, particularly noticeable in table/collection view cells.",
                confidence: 0.45,
                details: [
                    .init(key: "Constraint Operations", value: "\(constraintCount)"),
                    .init(key: "Priority Adjustments", value: "\(priorityCount)"),
                    .init(key: "Intrinsic Size Calls", value: "\(intrinsicSizeCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Main Thread Locking Analysis

    private func analyzeMainThreadLocking() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let lockCount = analyzer.countAllEvidence(matchingAny: [
            "NSLock", "NSRecursiveLock", "pthread_mutex_lock",
            "os_unfair_lock_lock"
        ])

        let semaphoreCount = analyzer.countAllEvidence(matchingAny: [
            "dispatch_semaphore_wait", "DispatchSemaphore"
        ])

        let syncDispatchCount = analyzer.countAllEvidence(matchingAny: [
            "dispatch_sync"
        ])

        let totalLockOps = lockCount + semaphoreCount + syncDispatchCount

        if totalLockOps > 5 {
            issues.append(DiagnosticIssue(
                title: "Significant Synchronization Primitive Usage",
                description: "Found \(totalLockOps) lock/semaphore/sync dispatch pattern(s). If any of these are used on the main thread, they can cause hangs while waiting for background work.",
                severity: .info,
                instrument: .hangs,
                category: "Main Thread Locking",
                recommendation: "Avoid locks, semaphores, and `dispatch_sync` on the main thread. Use async patterns instead: `DispatchQueue.async`, async/await, or Combine publishers to deliver results to the main thread without blocking.",
                impact: "Locks and semaphores on the main thread block the UI until the lock is acquired or the semaphore is signaled. This is a common source of user-visible hangs.",
                confidence: 0.55,
                details: [
                    .init(key: "Lock Operations", value: "\(lockCount)"),
                    .init(key: "Semaphore Waits", value: "\(semaphoreCount)"),
                    .init(key: "Sync Dispatches", value: "\(syncDispatchCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Main Thread Decoding Analysis

    private func analyzeMainThreadDecoding() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let imageDecodeCount = analyzer.countAllEvidence(matchingAny: [
            "UIImage", "imageNamed", "imageWithData",
            "CGImageSourceCreateImageAtIndex"
        ])

        let jsonDecodeCount = analyzer.countAllEvidence(matchingAny: [
            "JSONDecoder", "JSONSerialization", "jsonObject"
        ])

        let prepareForDisplayCount = analyzer.countAllEvidence(matchingAny: [
            "preparingForDisplay", "prepareForDisplay",
            "byPreparingForDisplay"
        ])

        if imageDecodeCount > 5 && prepareForDisplayCount == 0 {
            issues.append(DiagnosticIssue(
                title: "Image Decoding Without Pre-rendering",
                description: "Found \(imageDecodeCount) image loading patterns but no `preparingForDisplay` usage. Images are decoded on first display, which can cause frame drops.",
                severity: .info,
                instrument: .hangs,
                category: "Main Thread Decoding",
                recommendation: "Use `UIImage.preparingForDisplay()` or `byPreparingForDisplay()` to decode images on a background thread before they're needed for display. This moves the decode cost off the main thread.",
                impact: "Image decoding on the main thread during scrolling causes frame drops proportional to image size. A single large image decode can cause a 50-100ms hang.",
                confidence: 0.5,
                details: [
                    .init(key: "Image Load Patterns", value: "\(imageDecodeCount)"),
                    .init(key: "Pre-render Patterns", value: "\(prepareForDisplayCount)"),
                    .init(key: "JSON Decode Patterns", value: "\(jsonDecodeCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Core Data Main Thread Analysis

    private func analyzeCoreDataMainThread() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let coreDataCount = analyzer.countAllEvidence(matchingAny: [
            "NSManagedObjectContext", "NSFetchRequest",
            "NSPersistentContainer", "CoreData"
        ])

        let bgContextCount = analyzer.countAllEvidence(matchingAny: [
            "newBackgroundContext", "performBackgroundTask",
            "NSPrivateQueueConcurrencyType"
        ])

        let fetchBatchCount = analyzer.countAllEvidence(matchingAny: [
            "fetchBatchSize", "fetchLimit",
            "NSFetchedResultsController"
        ])

        if coreDataCount > 3 && bgContextCount == 0 {
            issues.append(DiagnosticIssue(
                title: "Core Data Without Background Contexts",
                description: "Found \(coreDataCount) Core Data pattern(s) but no background context usage. Core Data operations on the main context block the UI during fetches and saves.",
                severity: .warning,
                instrument: .hangs,
                category: "Core Data",
                recommendation: "Use `container.newBackgroundContext()` or `container.performBackgroundTask` for write operations and heavy fetches. Use `NSFetchedResultsController` for efficiently powering table/collection views with Core Data.",
                impact: "Core Data fetch requests on the main thread block the UI for the duration of the SQLite query. Large datasets or complex predicates can cause multi-second hangs.",
                confidence: analyzer.confidenceScore(evidenceCount: coreDataCount, lowThreshold: 2, highThreshold: 10),
                details: [
                    .init(key: "Core Data Patterns", value: "\(coreDataCount)"),
                    .init(key: "Background Contexts", value: "\(bgContextCount)"),
                    .init(key: "Fetch Batching", value: "\(fetchBatchCount)")
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
            return "No significant hang risk patterns detected. Your app appears to handle main thread work efficiently."
        }

        let critical = issues.filter { $0.severity == .critical }.count
        let warnings = issues.filter { $0.severity == .warning }.count

        if critical > 0 {
            return "Found \(critical) critical and \(warnings) warning-level hang risk pattern(s). These patterns are likely to cause visible UI freezes and should be addressed immediately."
        } else if warnings > 0 {
            return "Found \(warnings) warning-level hang risk pattern(s) that may cause intermittent UI freezes. Review recommended to improve responsiveness."
        } else {
            return "Found \(issues.count) hang-related finding(s). These are patterns worth reviewing to improve UI responsiveness."
        }
    }
}
