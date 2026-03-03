import Testing
import Nimble
@testable import AIInstruments

@Suite("HangsAnalyzer Tests")
struct HangsAnalyzerTests {

    // MARK: - Basic Analysis

    @Test("Analyzing empty binary produces no issues and perfect score")
    func emptyBinary() {
        let ba = makeBinaryAnalyzer()
        let result = HangsAnalyzer(binaryAnalyzer: ba).analyze()

        expect(result.instrument).to(equal(.hangs))
        expect(result.issues).to(beEmpty())
        expect(result.score).to(equal(100))
        expect(result.analysisTimeSeconds).to(beGreaterThanOrEqualTo(0))
    }

    // MARK: - Synchronous I/O Detection

    @Test("Detects frequent synchronous file operations")
    func syncFileOps() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_contentsOfFile_1"),
                makeSymbol("_contentsOfFile_2"),
                makeSymbol("_dataWithContentsOfFile_1"),
                makeSymbol("_contentsOfDirectory_1"),
                makeSymbol("_contentsAtPath_1"),
                makeSymbol("_contentsOfFile_3"),
            ]
        )

        let result = HangsAnalyzer(binaryAnalyzer: ba).analyze()
        let syncIssues = result.issues.filter { $0.category == "Synchronous I/O" }
        expect(syncIssues).toNot(beEmpty())
    }

    @Test("Detects synchronous network requests as critical")
    func syncNetworkRequests() {
        let ba = makeBinaryAnalyzer(
            symbols: [makeSymbol("_sendSynchronousRequest")]
        )

        let result = HangsAnalyzer(binaryAnalyzer: ba).analyze()
        let syncNetIssues = result.issues.filter {
            $0.category == "Synchronous I/O" && $0.severity == .critical
        }
        expect(syncNetIssues).toNot(beEmpty())
    }

    // MARK: - Heavy Computation Detection

    @Test("Detects heavy collection processing")
    func heavyComputation() {
        var symbols: [SymbolInfo] = []
        for i in 0..<8 {
            symbols.append(makeSymbol("_sort(_\(i)"))
        }
        for i in 0..<5 {
            symbols.append(makeSymbol("_NSRegularExpression_\(i)"))
        }

        let ba = makeBinaryAnalyzer(symbols: symbols)
        let result = HangsAnalyzer(binaryAnalyzer: ba).analyze()
        let computeIssues = result.issues.filter { $0.category == "Heavy Computation" }
        expect(computeIssues).toNot(beEmpty())
    }

    // MARK: - View Hierarchy Detection

    @Test("Detects large number of custom view types")
    func largeViewHierarchy() {
        var classes: [String] = []
        for i in 0..<55 {
            classes.append("Custom\(i)View")
        }

        let ba = makeBinaryAnalyzer(objcClasses: classes)
        let result = HangsAnalyzer(binaryAnalyzer: ba).analyze()
        let viewIssues = result.issues.filter { $0.category == "View Hierarchy" }
        expect(viewIssues).toNot(beEmpty())
    }

    // MARK: - Scroll Performance Detection

    @Test("Detects scroll views without prefetching")
    func scrollViewNoPrefetch() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_UITableView_1"),
                makeSymbol("_UICollectionView_1"),
                makeSymbol("_UITableView_2"),
                makeSymbol("_UICollectionView_2"),
            ]
        )

        let result = HangsAnalyzer(binaryAnalyzer: ba).analyze()
        let scrollIssues = result.issues.filter { $0.category == "Scroll Performance" }
        expect(scrollIssues).toNot(beEmpty())
    }

    @Test("Detects scroll views without diffable data sources")
    func scrollViewNoDiffable() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_UITableView_1"),
                makeSymbol("_UITableView_2"),
                makeSymbol("_UITableView_3"),
                makeSymbol("_UICollectionView_1"),
                makeSymbol("_UICollectionView_2"),
                makeSymbol("_UICollectionView_3"),
            ]
        )

        let result = HangsAnalyzer(binaryAnalyzer: ba).analyze()
        let diffableIssues = result.issues.filter { $0.title.contains("Diffable") }
        expect(diffableIssues).toNot(beEmpty())
    }

    // MARK: - Main Thread Locking Detection

    @Test("Detects significant synchronization primitive usage")
    func mainThreadLocking() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_NSLock_1"),
                makeSymbol("_NSLock_2"),
                makeSymbol("_pthread_mutex_lock_1"),
                makeSymbol("_dispatch_semaphore_wait_1"),
                makeSymbol("_dispatch_sync_1"),
                makeSymbol("_os_unfair_lock_lock_1"),
            ]
        )

        let result = HangsAnalyzer(binaryAnalyzer: ba).analyze()
        let lockIssues = result.issues.filter { $0.category == "Main Thread Locking" }
        expect(lockIssues).toNot(beEmpty())
    }

    // MARK: - Image Decoding Detection

    @Test("Detects image decoding without pre-rendering")
    func imageDecodingNoPreRender() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_UIImage_1"),
                makeSymbol("_UIImage_2"),
                makeSymbol("_imageNamed_1"),
                makeSymbol("_imageWithData_1"),
                makeSymbol("_UIImage_3"),
                makeSymbol("_imageNamed_2"),
            ]
        )

        let result = HangsAnalyzer(binaryAnalyzer: ba).analyze()
        let decodeIssues = result.issues.filter { $0.category == "Main Thread Decoding" }
        expect(decodeIssues).toNot(beEmpty())
    }

    // MARK: - Core Data Detection

    @Test("Detects Core Data without background contexts")
    func coreDataNoBackground() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_NSManagedObjectContext_1"),
                makeSymbol("_NSFetchRequest_1"),
                makeSymbol("_NSPersistentContainer_1"),
                makeSymbol("_CoreData_ref"),
            ]
        )

        let result = HangsAnalyzer(binaryAnalyzer: ba).analyze()
        let cdIssues = result.issues.filter { $0.category == "Core Data" }
        expect(cdIssues).toNot(beEmpty())
    }

    @Test("No Core Data issue when background contexts are used")
    func coreDataWithBackground() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_NSManagedObjectContext_1"),
                makeSymbol("_NSFetchRequest_1"),
                makeSymbol("_NSPersistentContainer_1"),
                makeSymbol("_CoreData_ref"),
                makeSymbol("_newBackgroundContext"),
            ]
        )

        let result = HangsAnalyzer(binaryAnalyzer: ba).analyze()
        let cdIssues = result.issues.filter { $0.category == "Core Data" }
        expect(cdIssues).to(beEmpty())
    }

    // MARK: - Scoring

    @Test("Score decreases with critical issues")
    func scoringPenalty() {
        let cleanBa = makeBinaryAnalyzer()
        let cleanResult = HangsAnalyzer(binaryAnalyzer: cleanBa).analyze()
        expect(cleanResult.score).to(equal(100))

        let dirtyBa = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_sendSynchronousRequest"),
                makeSymbol("_NSManagedObjectContext_1"),
                makeSymbol("_NSFetchRequest_1"),
                makeSymbol("_NSPersistentContainer_1"),
                makeSymbol("_CoreData_ref"),
            ]
        )
        let dirtyResult = HangsAnalyzer(binaryAnalyzer: dirtyBa).analyze()
        expect(dirtyResult.score).to(beLessThan(cleanResult.score))
    }

    // MARK: - Metadata

    @Test("Result metadata contains expected keys")
    func metadata() {
        let ba = makeBinaryAnalyzer()
        let result = HangsAnalyzer(binaryAnalyzer: ba).analyze()
        expect(result.metadata["viewControllerCount"]).toNot(beNil())
        expect(result.metadata["syncIOPatterns"]).toNot(beNil())
        expect(result.metadata["lockPatterns"]).toNot(beNil())
    }
}
