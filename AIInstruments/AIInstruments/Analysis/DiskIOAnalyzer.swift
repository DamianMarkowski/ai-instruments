import Foundation

/// Analyzes iOS app binaries for file system access patterns and disk I/O issues.
///
/// Detection categories:
/// - Synchronous file operations
/// - Large file handling
/// - Core Data usage patterns
/// - SQLite usage patterns
/// - File coordination
/// - Temporary file management
/// - File protection levels
/// - Logging and diagnostics I/O
final class DiskIOAnalyzer {

    private let analyzer: BinaryAnalyzer

    init(binaryAnalyzer: BinaryAnalyzer) {
        self.analyzer = binaryAnalyzer
    }

    func analyze() -> AnalysisResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        var issues: [DiagnosticIssue] = []

        issues.append(contentsOf: analyzeSynchronousFileOps())
        issues.append(contentsOf: analyzeLargeFileHandling())
        issues.append(contentsOf: analyzeCoreDataPatterns())
        issues.append(contentsOf: analyzeSQLitePatterns())
        issues.append(contentsOf: analyzeFileCoordination())
        issues.append(contentsOf: analyzeTemporaryFiles())
        issues.append(contentsOf: analyzeFileProtection())
        issues.append(contentsOf: analyzeLoggingIO())

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let score = calculateScore(issues: issues)

        return AnalysisResult(
            instrument: .diskIO,
            issues: issues.sorted { $0.severity < $1.severity },
            summary: generateSummary(issues: issues, score: score),
            score: score,
            analysisTimeSeconds: elapsed,
            metadata: [
                "fileOperationPatterns": "\(analyzer.countAllEvidence(matchingAny: ["FileManager", "FileHandle", "contentsOfFile"]))",
                "coreDataUsage": "\(analyzer.countAllEvidence(matchingAny: ["NSManagedObjectContext", "CoreData"]))",
                "sqliteUsage": "\(analyzer.countAllEvidence(matchingAny: ["sqlite3", "GRDB", "FMDB"]))"
            ]
        )
    }

    // MARK: - Synchronous File Operations

    private func analyzeSynchronousFileOps() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let syncReadCount = analyzer.countAllEvidence(matchingAny: [
            "contentsOfFile", "dataWithContentsOfFile",
            "stringWithContentsOfFile", "contentsAtPath",
            "contentsOfDirectory"
        ])

        let syncWriteCount = analyzer.countAllEvidence(matchingAny: [
            "writeToFile", "write(toFile:", "atomically",
            "createFile(atPath:", "createDirectory"
        ])

        let asyncIOCount = analyzer.countAllEvidence(matchingAny: [
            "DispatchIO", "readDataToEndOfFile", "readabilityHandler",
            "writeabilityHandler"
        ])

        let totalSyncIO = syncReadCount + syncWriteCount

        if totalSyncIO > 5 && asyncIOCount == 0 {
            issues.append(DiagnosticIssue(
                title: "Synchronous File I/O Without Async Alternatives",
                description: "Found \(totalSyncIO) synchronous file operation(s) (\(syncReadCount) reads, \(syncWriteCount) writes) but no asynchronous I/O patterns. Sync I/O blocks the calling thread.",
                severity: .warning,
                instrument: .diskIO,
                category: "Synchronous I/O",
                recommendation: "Use `DispatchIO` or perform file operations on background queues. For reading, use `Data(contentsOf:options:.mappedIfSafe)` for large files. For writing, dispatch to `DispatchQueue.global()` and use `Data.write(to:options:.atomic)`.",
                impact: "Synchronous file I/O blocks the calling thread until the operation completes. On the main thread, this causes UI hangs. On background threads, it wastes thread pool resources.",
                confidence: analyzer.confidenceScore(evidenceCount: totalSyncIO, lowThreshold: 3, highThreshold: 15),
                details: [
                    .init(key: "Sync Read Ops", value: "\(syncReadCount)"),
                    .init(key: "Sync Write Ops", value: "\(syncWriteCount)"),
                    .init(key: "Async I/O Patterns", value: "\(asyncIOCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Large File Handling

    private func analyzeLargeFileHandling() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let fileHandleCount = analyzer.countAllEvidence(matchingAny: [
            "FileHandle", "NSFileHandle"
        ])

        let streamCount = analyzer.countAllEvidence(matchingAny: [
            "InputStream", "OutputStream", "NSInputStream",
            "NSOutputStream", "Stream"
        ])

        let mmapCount = analyzer.countAllEvidence(matchingAny: [
            "mmap", "mappedIfSafe", "alwaysMapped"
        ])

        let fullReadCount = analyzer.countAllEvidence(matchingAny: [
            "contentsOfFile", "dataWithContentsOfFile"
        ])

        if fullReadCount > 3 && mmapCount == 0 && streamCount == 0 {
            issues.append(DiagnosticIssue(
                title: "Full File Reads Without Streaming or Mapping",
                description: "Found \(fullReadCount) full-file read pattern(s) but no streaming or memory-mapped I/O. Reading entire files into memory is inefficient for large files.",
                severity: .info,
                instrument: .diskIO,
                category: "Large File Handling",
                recommendation: "For large files (>1MB), use `Data(contentsOf:options:.mappedIfSafe)` for read-only access. For sequential processing, use `InputStream` to read in chunks. For random access, use `FileHandle.seek(toFileOffset:)`.",
                impact: "Reading an entire file into memory creates a memory spike equal to the file size. For files larger than available memory, this can cause the app to be terminated.",
                confidence: 0.5,
                details: [
                    .init(key: "Full File Reads", value: "\(fullReadCount)"),
                    .init(key: "Stream I/O", value: "\(streamCount)"),
                    .init(key: "Memory-Mapped I/O", value: "\(mmapCount)"),
                    .init(key: "FileHandle Usage", value: "\(fileHandleCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Core Data Patterns

    private func analyzeCoreDataPatterns() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let coreDataCount = analyzer.countAllEvidence(matchingAny: [
            "NSManagedObjectContext", "NSFetchRequest",
            "NSPersistentContainer", "NSPersistentStore"
        ])

        let batchOpCount = analyzer.countAllEvidence(matchingAny: [
            "NSBatchDeleteRequest", "NSBatchUpdateRequest",
            "NSBatchInsertRequest"
        ])

        let fetchBatchCount = analyzer.countAllEvidence(matchingAny: [
            "fetchBatchSize", "fetchLimit"
        ])

        let faultingCount = analyzer.countAllEvidence(matchingAny: [
            "returnsObjectsAsFaults", "relationshipKeyPathsForPrefetching"
        ])

        if coreDataCount > 5 && batchOpCount == 0 {
            issues.append(DiagnosticIssue(
                title: "Core Data Without Batch Operations",
                description: "Found \(coreDataCount) Core Data pattern(s) but no batch operation usage. Batch operations (insert, update, delete) are significantly faster for large datasets.",
                severity: .info,
                instrument: .diskIO,
                category: "Core Data",
                recommendation: "Use `NSBatchInsertRequest` for bulk inserts, `NSBatchUpdateRequest` for bulk updates, and `NSBatchDeleteRequest` for bulk deletes. Batch operations execute directly in the SQL layer, bypassing the object graph.",
                impact: "Without batch operations, inserting/updating/deleting thousands of objects requires loading each into memory and processing individually, which can be 10-100x slower than batch operations.",
                confidence: 0.55,
                details: [
                    .init(key: "Core Data Patterns", value: "\(coreDataCount)"),
                    .init(key: "Batch Operations", value: "\(batchOpCount)"),
                    .init(key: "Fetch Batching", value: "\(fetchBatchCount)"),
                    .init(key: "Faulting Config", value: "\(faultingCount)")
                ]
            ))
        }

        if coreDataCount > 3 && fetchBatchCount == 0 {
            issues.append(DiagnosticIssue(
                title: "Core Data Fetches Without Batch Size",
                description: "Found Core Data usage but no `fetchBatchSize` configuration. Without batch sizing, fetch requests load all matching objects into memory at once.",
                severity: .suggestion,
                instrument: .diskIO,
                category: "Core Data",
                recommendation: "Set `fetchRequest.fetchBatchSize` to a reasonable value (20-50) to enable incremental loading. This is especially important for fetches that power table/collection views.",
                impact: "Unbatched fetches load all objects into memory simultaneously, causing memory spikes proportional to result set size. Batch sizing enables on-demand loading as objects are accessed.",
                confidence: 0.5,
                details: [
                    .init(key: "Core Data Patterns", value: "\(coreDataCount)"),
                    .init(key: "Fetch Batch Config", value: "\(fetchBatchCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - SQLite Patterns

    private func analyzeSQLitePatterns() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let sqliteCount = analyzer.countAllEvidence(matchingAny: [
            "sqlite3", "sqlite3_open", "sqlite3_exec",
            "GRDB", "FMDB", "FMDatabase", "SQLite"
        ])

        let walCount = analyzer.countAllEvidence(matchingAny: [
            "journal_mode", "WAL", "wal"
        ])

        let transactionCount = analyzer.countAllEvidence(matchingAny: [
            "BEGIN TRANSACTION", "COMMIT", "beginTransaction",
            "beginDeferredTransaction", "sqlite3_exec"
        ])

        if sqliteCount > 3 && walCount == 0 {
            issues.append(DiagnosticIssue(
                title: "SQLite Without WAL Journal Mode",
                description: "Found \(sqliteCount) SQLite pattern(s) but no WAL (Write-Ahead Logging) configuration. WAL mode enables concurrent reads during writes and improves performance.",
                severity: .suggestion,
                instrument: .diskIO,
                category: "SQLite",
                recommendation: "Enable WAL journal mode with `PRAGMA journal_mode=WAL`. WAL allows concurrent read access during writes and reduces disk I/O by batching write operations.",
                impact: "Without WAL, SQLite uses rollback journal mode which locks the entire database during writes, blocking all concurrent readers. WAL enables true concurrent read/write access.",
                confidence: 0.5,
                details: [
                    .init(key: "SQLite Patterns", value: "\(sqliteCount)"),
                    .init(key: "WAL Config", value: "\(walCount)"),
                    .init(key: "Transaction Patterns", value: "\(transactionCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - File Coordination

    private func analyzeFileCoordination() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let fileCoordinatorCount = analyzer.countAllEvidence(matchingAny: [
            "NSFileCoordinator", "NSFilePresenter",
            "coordinateReadingItem", "coordinateWritingItem"
        ])

        let appGroupCount = analyzer.countAllEvidence(matchingAny: [
            "containerURL(forSecurityApplicationGroupIdentifier:",
            "appGroup", "group.", "sharedContainer"
        ])

        if appGroupCount > 0 && fileCoordinatorCount == 0 {
            issues.append(DiagnosticIssue(
                title: "App Group File Access Without Coordination",
                description: "Found \(appGroupCount) app group/shared container pattern(s) but no `NSFileCoordinator` usage. Shared files accessed by app extensions require coordination to prevent data corruption.",
                severity: .warning,
                instrument: .diskIO,
                category: "File Coordination",
                recommendation: "Use `NSFileCoordinator` when reading/writing files in shared app group containers. This prevents data corruption when the main app and extensions access the same files simultaneously.",
                impact: "Without file coordination, simultaneous access from the main app and extensions can cause data corruption, partial reads, or crashes.",
                confidence: 0.55,
                details: [
                    .init(key: "App Group Patterns", value: "\(appGroupCount)"),
                    .init(key: "File Coordinator Usage", value: "\(fileCoordinatorCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Temporary File Management

    private func analyzeTemporaryFiles() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let tmpCount = analyzer.countAllEvidence(matchingAny: [
            "temporaryDirectory", "NSTemporaryDirectory",
            "tmp", "tempFile", "tmpFile"
        ])

        let cleanupCount = analyzer.countAllEvidence(matchingAny: [
            "removeItem", "removeFile", "deleteFile"
        ])

        let cacheDirCount = analyzer.countAllEvidence(matchingAny: [
            "cachesDirectory", "NSCachesDirectory", "Caches"
        ])

        if tmpCount > 3 && cleanupCount == 0 {
            issues.append(DiagnosticIssue(
                title: "Temporary Files Without Explicit Cleanup",
                description: "Found \(tmpCount) temporary file pattern(s) but no file deletion calls. Accumulated temporary files waste disk space and may trigger system cleanup delays.",
                severity: .suggestion,
                instrument: .diskIO,
                category: "Temporary Files",
                recommendation: "Clean up temporary files after use with `FileManager.removeItem(at:)`. For cache files, use the Caches directory which the system can purge under storage pressure. Implement periodic cleanup for long-running apps.",
                impact: "Accumulated temporary files consume disk space and can slow down directory enumeration. The system eventually purges the temp directory, but this may happen at inconvenient times.",
                confidence: 0.45,
                details: [
                    .init(key: "Temp File Patterns", value: "\(tmpCount)"),
                    .init(key: "Cleanup Patterns", value: "\(cleanupCount)"),
                    .init(key: "Cache Dir Usage", value: "\(cacheDirCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - File Protection Analysis

    private func analyzeFileProtection() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let fileProtectionCount = analyzer.countAllEvidence(matchingAny: [
            "FileProtectionType", "NSFileProtection",
            "completeFileProtection", "completeUnlessOpen",
            "completeUntilFirstUserAuthentication"
        ])

        let sensitiveDataCount = analyzer.countAllEvidence(matchingAny: [
            "Keychain", "SecItem", "password", "token",
            "credential", "biometric"
        ])

        let fileWriteCount = analyzer.countAllEvidence(matchingAny: [
            "write(toFile:", "writeToFile", "createFile"
        ])

        if sensitiveDataCount > 2 && fileProtectionCount == 0 && fileWriteCount > 0 {
            issues.append(DiagnosticIssue(
                title: "Sensitive Data Without File Protection",
                description: "Found \(sensitiveDataCount) sensitive data pattern(s) and \(fileWriteCount) file write(s) but no file protection configuration. Files without explicit protection may be accessible when the device is locked.",
                severity: .warning,
                instrument: .diskIO,
                category: "File Protection",
                recommendation: "Set `.completeFileProtection` on files containing sensitive data. Use `Data.write(to:options:.completeFileProtection)` or set file attributes with `FileManager.setAttributes`. Store credentials in the Keychain instead of files.",
                impact: "Without file protection, data files are accessible even when the device is locked. This is a security risk for sensitive user data if the device is lost or stolen.",
                confidence: 0.55,
                details: [
                    .init(key: "Sensitive Data Patterns", value: "\(sensitiveDataCount)"),
                    .init(key: "File Protection Config", value: "\(fileProtectionCount)"),
                    .init(key: "File Write Ops", value: "\(fileWriteCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Logging I/O Analysis

    private func analyzeLoggingIO() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let printCount = analyzer.countAllEvidence(matchingAny: [
            "NSLog", "print(", "debugPrint("
        ])

        let osLogCount = analyzer.countAllEvidence(matchingAny: [
            "os_log", "Logger", "OSLog"
        ])

        let fileLogCount = analyzer.countAllEvidence(matchingAny: [
            "CocoaLumberjack", "SwiftyBeaver", "DDLog",
            "logToFile", "FileLogger"
        ])

        if printCount > 20 && osLogCount == 0 {
            issues.append(DiagnosticIssue(
                title: "Heavy print/NSLog Without os_log",
                description: "Found \(printCount) print/NSLog pattern(s) but no os_log/Logger usage. print and NSLog perform synchronous I/O and are slower than the unified logging system.",
                severity: .info,
                instrument: .diskIO,
                category: "Logging I/O",
                recommendation: "Migrate from `print`/`NSLog` to `os.Logger` or `os_log`. The unified logging system is significantly faster, supports log levels, and integrates with Console.app for filtering. Use `#if DEBUG` to strip verbose logging in release builds.",
                impact: "Each print/NSLog call performs synchronous I/O to stderr. In tight loops or high-frequency code paths, this can cause measurable performance degradation.",
                confidence: 0.5,
                details: [
                    .init(key: "print/NSLog Calls", value: "\(printCount)"),
                    .init(key: "os_log/Logger Usage", value: "\(osLogCount)"),
                    .init(key: "File Logging Libs", value: "\(fileLogCount)")
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
            return "No significant file I/O issues detected. Your app appears to handle disk operations efficiently."
        }

        let critical = issues.filter { $0.severity == .critical }.count
        let warnings = issues.filter { $0.severity == .warning }.count

        if critical > 0 {
            return "Found \(critical) critical and \(warnings) warning-level file I/O issue(s). These patterns may cause data corruption or significant performance degradation."
        } else if warnings > 0 {
            return "Found \(warnings) warning-level file I/O pattern(s) that may affect performance or data safety. Review recommended."
        } else {
            return "Found \(issues.count) file I/O finding(s). These are patterns worth reviewing to improve disk operation efficiency."
        }
    }
}
