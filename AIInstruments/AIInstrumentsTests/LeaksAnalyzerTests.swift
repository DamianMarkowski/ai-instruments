import Testing
import Nimble
@testable import AIInstruments

@Suite("LeaksAnalyzer Tests")
struct LeaksAnalyzerTests {

    // MARK: - Basic Analysis

    @Test("Analyzing empty binary produces no issues and perfect score")
    func emptyBinary() {
        let analyzer = makeBinaryAnalyzer()
        let leaks = LeaksAnalyzer(binaryAnalyzer: analyzer)
        let result = leaks.analyze()

        expect(result.instrument).to(equal(.leaks))
        expect(result.issues).to(beEmpty())
        expect(result.score).to(equal(100))
        expect(result.analysisTimeSeconds).to(beGreaterThanOrEqualTo(0))
    }

    // MARK: - Strong Delegate Detection

    @Test("Detects strong delegate setters without weak references")
    func strongDelegates() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_MyClass.delegate.setter:vs"),
                makeSymbol("_setDelegate:"),
            ],
            objcSelectors: ["setDelegate:", "delegate"],
            swiftTypeDescriptors: ["App.MainViewController"]
        )

        let result = LeaksAnalyzer(binaryAnalyzer: ba).analyze()
        let delegateIssues = result.issues.filter { $0.category == "Strong Delegates" }
        expect(delegateIssues).toNot(beEmpty())
    }

    @Test("No strong delegate issue when weak references are present")
    func weakDelegates() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_MyClass.delegate.setter:vs"),
                makeSymbol("_weak_delegate_ref"),
            ]
        )

        let result = LeaksAnalyzer(binaryAnalyzer: ba).analyze()
        let delegateIssues = result.issues.filter { $0.category == "Strong Delegates" }
        expect(delegateIssues).to(beEmpty())
    }

    // MARK: - Notification Observer Detection

    @Test("Detects addObserver/removeObserver imbalance")
    func notificationImbalance() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_addObserver1"),
                makeSymbol("_addObserver2"),
                makeSymbol("_addObserver3"),
                makeSymbol("_NotificationCenter_addObserver"),
            ],
            objcSelectors: ["addObserver:selector:name:object:", "addObserver:selector:name:object:"]
        )

        let result = LeaksAnalyzer(binaryAnalyzer: ba).analyze()
        let observerIssues = result.issues.filter { $0.category == "Notification Observers" }
        expect(observerIssues).toNot(beEmpty())
    }

    @Test("No notification issue when observers are balanced")
    func notificationBalanced() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_addObserver"),
                makeSymbol("_removeObserver"),
            ],
            objcSelectors: ["addObserver:selector:name:object:", "removeObserver:"]
        )

        let result = LeaksAnalyzer(binaryAnalyzer: ba).analyze()
        let observerIssues = result.issues.filter { $0.category == "Notification Observers" }
        expect(observerIssues).to(beEmpty())
    }

    // MARK: - Timer Retain Cycle Detection

    @Test("Detects timer usage with potential retain cycles")
    func timerRetainCycles() {
        let ba = makeBinaryAnalyzer(
            objcSelectors: ["scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"]
        )

        let result = LeaksAnalyzer(binaryAnalyzer: ba).analyze()
        let timerIssues = result.issues.filter { $0.category == "Timer Retain Cycles" }
        expect(timerIssues).toNot(beEmpty())
    }

    // MARK: - Circular Reference Detection

    @Test("Detects coordinator-viewcontroller pattern")
    func coordinatorPattern() {
        let ba = makeBinaryAnalyzer(
            objcClasses: ["MainViewController", "SettingsViewController"],
            swiftTypeDescriptors: ["App.AppCoordinator", "App.FlowNavigator"]
        )

        let result = LeaksAnalyzer(binaryAnalyzer: ba).analyze()
        let circularIssues = result.issues.filter { $0.category == "Circular References" }
        expect(circularIssues).toNot(beEmpty())
    }

    @Test("Detects complex object graphs with many managers/services")
    func complexObjectGraph() {
        let ba = makeBinaryAnalyzer(
            objcClasses: [
                "NetworkManager", "DataService", "CacheStore", "AuthManager"
            ]
        )

        let result = LeaksAnalyzer(binaryAnalyzer: ba).analyze()
        let circularIssues = result.issues.filter { $0.category == "Circular References" }
        expect(circularIssues).toNot(beEmpty())
    }

    // MARK: - Core Foundation Retain/Release

    @Test("Detects CF retain/release imbalance")
    func cfRetainReleaseImbalance() {
        let ba = makeBinaryAnalyzer(symbols: [
            makeSymbol("_CFRetain"), makeSymbol("_CFRetain"),
            makeSymbol("_CFRetain"), makeSymbol("_CFRetain"),
            makeSymbol("_CFRetain"),
            makeSymbol("_CFRelease"),
        ])

        let result = LeaksAnalyzer(binaryAnalyzer: ba).analyze()
        let cfIssues = result.issues.filter { $0.category == "CF Memory Management" }
        expect(cfIssues).toNot(beEmpty())
    }

    // MARK: - Closure Capture Analysis

    @Test("Detects high closure density with capture risk")
    func closureCaptureRisk() {
        var symbols: [SymbolInfo] = []
        for i in 0..<10 {
            symbols.append(makeSymbol("_block_invoke_\(i)"))
        }
        for i in 0..<10 {
            symbols.append(makeSymbol("_swift_retain_\(i)"))
            symbols.append(makeSymbol("_swift_release_\(i)"))
        }

        let ba = makeBinaryAnalyzer(symbols: symbols)
        let result = LeaksAnalyzer(binaryAnalyzer: ba).analyze()
        let closureIssues = result.issues.filter { $0.category == "Closure Captures" }
        expect(closureIssues).toNot(beEmpty())
    }

    // MARK: - Block-Based API Analysis

    @Test("Detects heavy asynchronous block usage")
    func heavyAsyncBlocks() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_URLSession"),
                makeSymbol("_dataTaskWith"),
                makeSymbol("_DispatchQueue"),
                makeSymbol("_dispatch_async"),
            ]
        )

        let result = LeaksAnalyzer(binaryAnalyzer: ba).analyze()
        let blockIssues = result.issues.filter { $0.category == "Block Captures" }
        expect(blockIssues).toNot(beEmpty())
    }

    // MARK: - Scoring

    @Test("Score decreases with more severe issues")
    func scoringPenalty() {
        let baClean = makeBinaryAnalyzer()
        let cleanResult = LeaksAnalyzer(binaryAnalyzer: baClean).analyze()
        expect(cleanResult.score).to(equal(100))

        let baDirty = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_CFRetain"), makeSymbol("_CFRetain"),
                makeSymbol("_CFRetain"), makeSymbol("_CFRetain"),
                makeSymbol("_CFRetain"),
                makeSymbol("_CFRelease"),
            ],
            objcSelectors: ["scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"]
        )
        let dirtyResult = LeaksAnalyzer(binaryAnalyzer: baDirty).analyze()
        expect(dirtyResult.score).to(beLessThan(cleanResult.score))
    }

    // MARK: - Metadata

    @Test("Result metadata contains expected keys")
    func metadata() {
        let ba = makeBinaryAnalyzer()
        let result = LeaksAnalyzer(binaryAnalyzer: ba).analyze()
        expect(result.metadata["totalSymbolsAnalyzed"]).toNot(beNil())
        expect(result.metadata["classesAnalyzed"]).toNot(beNil())
        expect(result.metadata["selectorsAnalyzed"]).toNot(beNil())
    }
}
