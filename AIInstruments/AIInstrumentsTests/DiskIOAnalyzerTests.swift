import Testing
import Nimble
@testable import AIInstruments

@Suite("DiskIOAnalyzer Tests")
struct DiskIOAnalyzerTests {

    // MARK: - Basic Analysis

    @Test("Analyzing empty binary produces no issues and perfect score")
    func emptyBinary() {
        let ba = makeBinaryAnalyzer()
        let result = DiskIOAnalyzer(binaryAnalyzer: ba).analyze()

        expect(result.instrument).to(equal(.diskIO))
        expect(result.issues).to(beEmpty())
        expect(result.score).to(equal(100))
        expect(result.analysisTimeSeconds).to(beGreaterThanOrEqualTo(0))
    }

    // MARK: - Synchronous I/O Detection

    @Test("Detects synchronous file I/O without async alternatives")
    func syncFileIO() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_contentsOfFile_1"),
                makeSymbol("_contentsOfFile_2"),
                makeSymbol("_dataWithContentsOfFile_1"),
                makeSymbol("_writeToFile_1"),
                makeSymbol("_writeToFile_2"),
                makeSymbol("_contentsOfDirectory_1"),
            ]
        )

        let result = DiskIOAnalyzer(binaryAnalyzer: ba).analyze()
        let syncIssues = result.issues.filter { $0.category == "Synchronous I/O" }
        expect(syncIssues).toNot(beEmpty())
    }

    @Test("No sync I/O issue when async alternatives are present")
    func asyncFileIO() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_contentsOfFile_1"),
                makeSymbol("_contentsOfFile_2"),
                makeSymbol("_contentsOfFile_3"),
                makeSymbol("_writeToFile_1"),
                makeSymbol("_writeToFile_2"),
                makeSymbol("_writeToFile_3"),
                makeSymbol("_DispatchIO_read"),
            ]
        )

        let result = DiskIOAnalyzer(binaryAnalyzer: ba).analyze()
        let syncIssues = result.issues.filter { $0.category == "Synchronous I/O" }
        expect(syncIssues).to(beEmpty())
    }

    // MARK: - Large File Handling Detection

    @Test("Detects full file reads without streaming or mapping")
    func fullFileReads() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_contentsOfFile_1"),
                makeSymbol("_contentsOfFile_2"),
                makeSymbol("_dataWithContentsOfFile_1"),
                makeSymbol("_contentsOfFile_3"),
            ]
        )

        let result = DiskIOAnalyzer(binaryAnalyzer: ba).analyze()
        let fileIssues = result.issues.filter { $0.category == "Large File Handling" }
        expect(fileIssues).toNot(beEmpty())
    }

    // MARK: - Core Data Detection

    @Test("Detects Core Data without batch operations")
    func coreDataNoBatch() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_NSManagedObjectContext_1"),
                makeSymbol("_NSFetchRequest_1"),
                makeSymbol("_NSPersistentContainer_1"),
                makeSymbol("_NSManagedObjectContext_2"),
                makeSymbol("_NSFetchRequest_2"),
                makeSymbol("_NSPersistentStore_1"),
            ]
        )

        let result = DiskIOAnalyzer(binaryAnalyzer: ba).analyze()
        let cdIssues = result.issues.filter { $0.category == "Core Data" }
        expect(cdIssues).toNot(beEmpty())
    }

    @Test("Detects Core Data fetches without batch size")
    func coreDataNoBatchSize() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_NSManagedObjectContext_1"),
                makeSymbol("_NSFetchRequest_1"),
                makeSymbol("_NSPersistentContainer_1"),
                makeSymbol("_CoreData_ref"),
            ]
        )

        let result = DiskIOAnalyzer(binaryAnalyzer: ba).analyze()
        let batchIssues = result.issues.filter { $0.title.contains("Batch Size") }
        expect(batchIssues).toNot(beEmpty())
    }

    // MARK: - SQLite Detection

    @Test("Detects SQLite without WAL journal mode")
    func sqliteNoWAL() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_sqlite3_open"),
                makeSymbol("_sqlite3_exec"),
                makeSymbol("_sqlite3_ref"),
                makeSymbol("_FMDB_ref"),
            ]
        )

        let result = DiskIOAnalyzer(binaryAnalyzer: ba).analyze()
        let sqlIssues = result.issues.filter { $0.category == "SQLite" }
        expect(sqlIssues).toNot(beEmpty())
    }

    // MARK: - File Coordination Detection

    @Test("Detects app group file access without coordination")
    func appGroupNoCoordination() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_containerURL(forSecurityApplicationGroupIdentifier:"),
                makeSymbol("_appGroup_ref"),
            ]
        )

        let result = DiskIOAnalyzer(binaryAnalyzer: ba).analyze()
        let coordIssues = result.issues.filter { $0.category == "File Coordination" }
        expect(coordIssues).toNot(beEmpty())
    }

    @Test("No coordination issue when NSFileCoordinator is used")
    func appGroupWithCoordination() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_appGroup_ref"),
                makeSymbol("_NSFileCoordinator_init"),
            ]
        )

        let result = DiskIOAnalyzer(binaryAnalyzer: ba).analyze()
        let coordIssues = result.issues.filter { $0.category == "File Coordination" }
        expect(coordIssues).to(beEmpty())
    }

    // MARK: - Temporary File Detection

    @Test("Detects temporary files without cleanup")
    func tempFilesNoCleanup() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_temporaryDirectory_1"),
                makeSymbol("_NSTemporaryDirectory_1"),
                makeSymbol("_tmpFile_1"),
                makeSymbol("_tempFile_1"),
            ]
        )

        let result = DiskIOAnalyzer(binaryAnalyzer: ba).analyze()
        let tmpIssues = result.issues.filter { $0.category == "Temporary Files" }
        expect(tmpIssues).toNot(beEmpty())
    }

    // MARK: - File Protection Detection

    @Test("Detects sensitive data without file protection")
    func sensitiveDataNoProtection() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_password_field"),
                makeSymbol("_token_store"),
                makeSymbol("_credential_manager"),
                makeSymbol("_writeToFile_1"),
            ]
        )

        let result = DiskIOAnalyzer(binaryAnalyzer: ba).analyze()
        let protIssues = result.issues.filter { $0.category == "File Protection" }
        expect(protIssues).toNot(beEmpty())
    }

    // MARK: - Logging I/O Detection

    @Test("Detects heavy print/NSLog without os_log")
    func heavyPrintLogging() {
        var symbols: [SymbolInfo] = []
        for i in 0..<15 {
            symbols.append(makeSymbol("_NSLog_call_\(i)"))
        }
        for i in 0..<8 {
            symbols.append(makeSymbol("_print(_\(i)"))
        }

        let ba = makeBinaryAnalyzer(symbols: symbols)
        let result = DiskIOAnalyzer(binaryAnalyzer: ba).analyze()
        let logIssues = result.issues.filter { $0.category == "Logging I/O" }
        expect(logIssues).toNot(beEmpty())
    }

    // MARK: - Scoring

    @Test("Score decreases with more severe issues")
    func scoringPenalty() {
        let cleanBa = makeBinaryAnalyzer()
        let cleanResult = DiskIOAnalyzer(binaryAnalyzer: cleanBa).analyze()
        expect(cleanResult.score).to(equal(100))

        let dirtyBa = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_contentsOfFile_1"),
                makeSymbol("_contentsOfFile_2"),
                makeSymbol("_contentsOfFile_3"),
                makeSymbol("_writeToFile_1"),
                makeSymbol("_writeToFile_2"),
                makeSymbol("_writeToFile_3"),
                makeSymbol("_appGroup_ref"),
                makeSymbol("_password_field"),
                makeSymbol("_token_store"),
                makeSymbol("_credential_manager"),
                makeSymbol("_writeToFile_4"),
            ]
        )
        let dirtyResult = DiskIOAnalyzer(binaryAnalyzer: dirtyBa).analyze()
        expect(dirtyResult.score).to(beLessThan(cleanResult.score))
    }

    // MARK: - Metadata

    @Test("Result metadata contains expected keys")
    func metadata() {
        let ba = makeBinaryAnalyzer()
        let result = DiskIOAnalyzer(binaryAnalyzer: ba).analyze()
        expect(result.metadata["fileOperationPatterns"]).toNot(beNil())
        expect(result.metadata["coreDataUsage"]).toNot(beNil())
        expect(result.metadata["sqliteUsage"]).toNot(beNil())
    }
}
