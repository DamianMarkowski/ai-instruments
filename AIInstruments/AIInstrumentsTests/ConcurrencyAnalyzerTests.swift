import Testing
import Nimble
@testable import AIInstruments

@Suite("ConcurrencyAnalyzer Tests")
struct ConcurrencyAnalyzerTests {

    // MARK: - Non-Swift Binary

    @Test("Non-Swift binary returns info-level 'No Swift Code' result")
    func nonSwiftBinary() {
        let ba = makeBinaryAnalyzer(
            symbols: [makeSymbol("_OBJC_CLASS_$_AppDelegate")],
            linkedLibraries: ["/System/Library/Frameworks/UIKit.framework/UIKit"]
        )

        let result = ConcurrencyAnalyzer(binaryAnalyzer: ba).analyze()
        expect(result.instrument).to(equal(.concurrency))
        expect(result.score).to(equal(100))
        expect(result.issues.count).to(equal(1))
        expect(result.issues.first?.title).to(contain("No Swift Code"))
    }

    // MARK: - Sendable Conformance

    @Test("Detects low Sendable adoption with high async usage")
    func lowSendableAdoption() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_swift_task_create"),
                makeSymbol("_ScT_init"),
                makeSymbol("_withCheckedContinuation"),
                makeSymbol("_async_fn"),
            ],
            linkedLibraries: ["/usr/lib/libswiftCore.dylib"]
        )

        let result = ConcurrencyAnalyzer(binaryAnalyzer: ba).analyze()
        let sendableIssues = result.issues.filter { $0.category == "Sendable Conformance" }
        expect(sendableIssues).toNot(beEmpty())
    }

    // MARK: - MainActor Usage

    @Test("Detects UI code with limited MainActor annotation")
    func limitedMainActor() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_swift_task_1"),
                makeSymbol("_ScT_2"),
                makeSymbol("_async_3"),
            ],
            objcSelectors: [
                "UIView", "UILabel", "UIButton", "UITableView"
            ],
            linkedLibraries: ["/usr/lib/libswiftCore.dylib"]
        )

        let result = ConcurrencyAnalyzer(binaryAnalyzer: ba).analyze()
        let mainActorIssues = result.issues.filter { $0.category == "MainActor Isolation" }
        expect(mainActorIssues).toNot(beEmpty())
    }

    @Test("Detects legacy main queue dispatching alongside Swift Concurrency")
    func legacyMainQueueDispatch() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_DispatchQueue.main_1"),
                makeSymbol("_DispatchQueue.main_2"),
                makeSymbol("_DispatchQueue.main_3"),
                makeSymbol("_swift_task"),
            ],
            linkedLibraries: [
                "/usr/lib/libswiftCore.dylib",
                "/usr/lib/swift/libswift_Concurrency.dylib"
            ]
        )

        let result = ConcurrencyAnalyzer(binaryAnalyzer: ba).analyze()
        let mainActorIssues = result.issues.filter { $0.category == "MainActor Isolation" }
        let legacyIssue = mainActorIssues.first { $0.title.contains("Legacy Main Queue") }
        expect(legacyIssue).toNot(beNil())
    }

    // MARK: - Data Race Potential

    @Test("Detects unprotected shared mutable state")
    func unprotectedMutableState() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_shared_instance"),
                makeSymbol("_singleton_ref"),
                makeSymbol("_static_var_setter"),
            ],
            linkedLibraries: ["/usr/lib/libswiftCore.dylib"]
        )

        let result = ConcurrencyAnalyzer(binaryAnalyzer: ba).analyze()
        let dataRaceIssues = result.issues.filter { $0.category == "Data Race Risk" }
        expect(dataRaceIssues).toNot(beEmpty())
    }

    // MARK: - Task Management

    @Test("Detects tasks without cancellation support")
    func tasksNoCancellation() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_ScT_init_1"),
                makeSymbol("_ScT_init_2"),
                makeSymbol("_swift_task_create"),
            ],
            linkedLibraries: ["/usr/lib/libswiftCore.dylib"]
        )

        let result = ConcurrencyAnalyzer(binaryAnalyzer: ba).analyze()
        let taskIssues = result.issues.filter { $0.category == "Task Management" }
        expect(taskIssues).toNot(beEmpty())
    }

    @Test("Detects frequent use of detached tasks")
    func detachedTasks() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_Task.detached_1"),
                makeSymbol("_Task.detached_2"),
            ],
            linkedLibraries: ["/usr/lib/libswiftCore.dylib"]
        )

        let result = ConcurrencyAnalyzer(binaryAnalyzer: ba).analyze()
        let detachedIssues = result.issues.filter { $0.title.contains("Detached") }
        expect(detachedIssues).toNot(beEmpty())
    }

    // MARK: - Legacy Concurrency

    @Test("Detects mixed concurrency models (GCD + Swift Concurrency)")
    func mixedConcurrency() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_dispatch_async_1"),
                makeSymbol("_dispatch_async_2"),
                makeSymbol("_DispatchQueue_main"),
                makeSymbol("_DispatchGroup_init"),
                makeSymbol("_swift_task"),
            ],
            linkedLibraries: [
                "/usr/lib/libswiftCore.dylib",
                "/usr/lib/swift/libswift_Concurrency.dylib"
            ]
        )

        let result = ConcurrencyAnalyzer(binaryAnalyzer: ba).analyze()
        let legacyIssues = result.issues.filter { $0.category == "Legacy Patterns" }
        expect(legacyIssues).toNot(beEmpty())
    }

    @Test("Detects dispatch_sync usage (deadlock risk)")
    func dispatchSync() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_dispatch_sync_1"),
                makeSymbol("_dispatch_sync_2"),
            ],
            linkedLibraries: [
                "/usr/lib/libswiftCore.dylib",
                "/usr/lib/swift/libswift_Concurrency.dylib"
            ]
        )

        let result = ConcurrencyAnalyzer(binaryAnalyzer: ba).analyze()
        let syncIssues = result.issues.filter { $0.title.contains("Synchronous Dispatch") }
        expect(syncIssues).toNot(beEmpty())
    }

    // MARK: - Async/Await Patterns

    @Test("Detects unsafe continuations usage")
    func unsafeContinuations() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_withUnsafeContinuation_1"),
                makeSymbol("_withUnsafeContinuation_2"),
            ],
            linkedLibraries: ["/usr/lib/libswiftCore.dylib"]
        )

        let result = ConcurrencyAnalyzer(binaryAnalyzer: ba).analyze()
        let asyncIssues = result.issues.filter { $0.category == "Async Patterns" }
        expect(asyncIssues).toNot(beEmpty())
    }

    // MARK: - Global State

    @Test("Detects extensive singleton pattern usage")
    func extensiveSingletons() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_MyService.shared"),
                makeSymbol("_DataStore.shared"),
            ],
            objcClasses: ["SharedManager", "CacheStore", "SingletonHelper", "AuthManager"],
            linkedLibraries: ["/usr/lib/libswiftCore.dylib"]
        )

        let result = ConcurrencyAnalyzer(binaryAnalyzer: ba).analyze()
        let globalIssues = result.issues.filter { $0.category == "Global State" }
        expect(globalIssues).toNot(beEmpty())
    }

    // MARK: - Scoring & Summary

    @Test("Clean Swift binary has high score")
    func cleanBinary() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_Sendable_conform"),
                makeSymbol("_MainActor_usage"),
            ],
            linkedLibraries: ["/usr/lib/libswiftCore.dylib"]
        )

        let result = ConcurrencyAnalyzer(binaryAnalyzer: ba).analyze()
        expect(result.score).to(beGreaterThanOrEqualTo(80))
    }

    @Test("Result metadata includes concurrency-specific fields")
    func metadata() {
        let ba = makeBinaryAnalyzer(linkedLibraries: ["/usr/lib/libswiftCore.dylib"])
        let result = ConcurrencyAnalyzer(binaryAnalyzer: ba).analyze()
        expect(result.metadata["usesSwiftConcurrency"]).toNot(beNil())
        expect(result.metadata["swiftTypeCount"]).toNot(beNil())
        expect(result.metadata["objcClassCount"]).toNot(beNil())
    }
}
