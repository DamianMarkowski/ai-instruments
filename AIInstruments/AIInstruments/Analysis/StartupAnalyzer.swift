import Foundation

/// Analyzes iOS app binaries for patterns that affect app launch time.
///
/// Detection categories:
/// - Static initializer overhead
/// - Linked framework count
/// - ObjC class registration cost
/// - Binary size impact
/// - Dynamic library loading
/// - Swift type metadata
/// - Eager initialization patterns
/// - Launch-time work
final class StartupAnalyzer {

    private let analyzer: BinaryAnalyzer
    private let binarySize: Int

    init(binaryAnalyzer: BinaryAnalyzer, binarySize: Int) {
        self.analyzer = binaryAnalyzer
        self.binarySize = binarySize
    }

    func analyze() -> AnalysisResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        var issues: [DiagnosticIssue] = []

        issues.append(contentsOf: analyzeStaticInitializers())
        issues.append(contentsOf: analyzeLinkedFrameworks())
        issues.append(contentsOf: analyzeObjCClassCount())
        issues.append(contentsOf: analyzeBinarySizeImpact())
        issues.append(contentsOf: analyzeDynamicLibraries())
        issues.append(contentsOf: analyzeSwiftMetadata())
        issues.append(contentsOf: analyzeEagerInitialization())
        issues.append(contentsOf: analyzeLaunchTimeWork())

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let score = calculateScore(issues: issues)

        let binarySizeMB = String(format: "%.1f", Double(binarySize) / 1_048_576)

        return AnalysisResult(
            instrument: .startup,
            issues: issues.sorted { $0.severity < $1.severity },
            summary: generateSummary(issues: issues, score: score),
            score: score,
            analysisTimeSeconds: elapsed,
            metadata: [
                "binarySizeMB": binarySizeMB,
                "linkedLibraryCount": "\(analyzer.machOInfo.linkedLibraries.count)",
                "objcClassCount": "\(analyzer.objcClassCount)",
                "swiftTypeCount": "\(analyzer.swiftTypeCount)"
            ]
        )
    }

    // MARK: - Static Initializer Analysis

    private func analyzeStaticInitializers() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let staticInitCount = analyzer.findSymbols(matchingAny: [
            "__mod_init_func", "static_init", "_GLOBAL__sub_I",
            "__cxx_global_var_init", "globalinit_"
        ]).count

        let loadMethodCount = analyzer.countAllEvidence(matchingAny: [
            "+[", "initialize", "load"
        ])

        let objcLoadSelectors = analyzer.findSelectors(matchingAny: ["load"])

        let totalInitializers = staticInitCount + objcLoadSelectors.count

        if totalInitializers > 5 {
            issues.append(DiagnosticIssue(
                title: "Significant Static Initializer Count",
                description: "Found \(totalInitializers) static initializer(s). Each static initializer runs before `main()` is called, directly adding to pre-main launch time.",
                severity: totalInitializers > 20 ? .warning : .info,
                instrument: .startup,
                category: "Static Initializers",
                recommendation: "Minimize `+[NSObject load]` implementations and C++ static constructors. Move initialization to `+[NSObject initialize]` (lazy, once) or app launch code. For Swift, avoid complex stored property initializers on types with static instances.",
                impact: "Static initializers run synchronously before `main()`. Each adds measurable time to pre-main launch. Apps with many static initializers can have 100-500ms of pre-main overhead.",
                confidence: analyzer.confidenceScore(evidenceCount: totalInitializers, lowThreshold: 3, highThreshold: 20),
                details: [
                    .init(key: "Static Init Functions", value: "\(staticInitCount)"),
                    .init(key: "+load Selectors", value: "\(objcLoadSelectors.count)"),
                    .init(key: "Load Method Refs", value: "\(loadMethodCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Linked Framework Analysis

    private func analyzeLinkedFrameworks() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let totalLibraries = analyzer.machOInfo.linkedLibraries.count
        let embeddedFrameworks = analyzer.embeddedFrameworks()
        let systemFrameworks = analyzer.systemFrameworks()

        if totalLibraries > 50 {
            issues.append(DiagnosticIssue(
                title: "High Number of Linked Libraries",
                description: "The binary links \(totalLibraries) libraries (\(embeddedFrameworks.count) embedded, \(systemFrameworks.count) system). Each library requires dyld to resolve symbols at launch.",
                severity: totalLibraries > 100 ? .warning : .info,
                instrument: .startup,
                category: "Linked Frameworks",
                recommendation: "Reduce the number of linked dynamic frameworks. Convert infrequently used dynamic frameworks to static libraries. Use `dlopen` for frameworks needed only in specific user flows.",
                impact: "dyld processes each linked library at launch: mapping, rebasing, and binding symbols. Each dynamic framework adds ~2-5ms to launch time on modern devices.",
                confidence: analyzer.confidenceScore(evidenceCount: totalLibraries, lowThreshold: 30, highThreshold: 100),
                relatedSymbols: Array(embeddedFrameworks.prefix(10)),
                details: [
                    .init(key: "Total Libraries", value: "\(totalLibraries)"),
                    .init(key: "Embedded Frameworks", value: "\(embeddedFrameworks.count)"),
                    .init(key: "System Frameworks", value: "\(systemFrameworks.count)")
                ]
            ))
        }

        if embeddedFrameworks.count > 20 {
            issues.append(DiagnosticIssue(
                title: "Excessive Embedded Frameworks",
                description: "Found \(embeddedFrameworks.count) embedded (third-party/custom) frameworks. Embedded frameworks have higher launch cost than system frameworks due to code signing validation.",
                severity: embeddedFrameworks.count > 40 ? .warning : .info,
                instrument: .startup,
                category: "Linked Frameworks",
                recommendation: "Merge small frameworks into the main binary or a single framework. Convert dynamic frameworks to static libraries where possible. Use Swift Package Manager with static linking.",
                impact: "Each embedded framework requires code signing validation and symbol binding at launch. Merging 20 frameworks into static libraries can save 50-100ms of launch time.",
                confidence: 0.7,
                relatedSymbols: Array(embeddedFrameworks.prefix(10)),
                details: [
                    .init(key: "Embedded Frameworks", value: "\(embeddedFrameworks.count)")
                ]
            ))
        }

        return issues
    }

    // MARK: - ObjC Class Registration Analysis

    private func analyzeObjCClassCount() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let objcClasses = analyzer.objcClassCount
        let swiftTypes = analyzer.swiftTypeCount
        let totalTypes = objcClasses + swiftTypes

        if objcClasses > 5000 {
            issues.append(DiagnosticIssue(
                title: "Large ObjC Class Count",
                description: "Found \(objcClasses) ObjC classes. The ObjC runtime registers all classes at launch, which scales linearly with class count.",
                severity: objcClasses > 10000 ? .warning : .info,
                instrument: .startup,
                category: "ObjC Registration",
                recommendation: "Reduce the number of ObjC classes by removing unused code and consolidating small utility classes. Use Swift structs and enums where ObjC interop isn't needed, as they don't require runtime registration.",
                impact: "ObjC class registration at launch takes ~1ms per 500 classes. An app with 10,000 classes adds ~20ms to pre-main time just for registration.",
                confidence: analyzer.confidenceScore(evidenceCount: objcClasses, lowThreshold: 3000, highThreshold: 10000),
                details: [
                    .init(key: "ObjC Classes", value: "\(objcClasses)"),
                    .init(key: "Swift Types", value: "\(swiftTypes)"),
                    .init(key: "Total Types", value: "\(totalTypes)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Binary Size Impact Analysis

    private func analyzeBinarySizeImpact() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let binarySizeMB = Double(binarySize) / 1_048_576
        let textSizeMB = Double(analyzer.machOInfo.totalTextSize) / 1_048_576

        if binarySizeMB > 50 {
            issues.append(DiagnosticIssue(
                title: "Binary Size Impacts Cold Launch",
                description: String(format: "The binary is %.1f MB (%.1f MB __TEXT). Large binaries require more page faults during cold launch, increasing time-to-first-frame.", binarySizeMB, textSizeMB),
                severity: binarySizeMB > 150 ? .warning : .info,
                instrument: .startup,
                category: "Binary Size",
                recommendation: "Enable Link-Time Optimization (LTO) and dead code stripping. Remove unused assets and frameworks. Consider on-demand resources for non-essential content. Use `-Osize` optimization for release builds.",
                impact: "Cold launch requires the kernel to page in the __TEXT segment. Each additional MB adds ~1-2ms on modern devices, more on older hardware or when under memory pressure.",
                confidence: 0.7,
                details: [
                    .init(key: "Binary Size", value: String(format: "%.1f MB", binarySizeMB)),
                    .init(key: "__TEXT Size", value: String(format: "%.1f MB", textSizeMB)),
                    .init(key: "Libraries", value: "\(analyzer.machOInfo.linkedLibraries.count)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Dynamic Library Analysis

    private func analyzeDynamicLibraries() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let reexportedCount = analyzer.findSymbols(matchingAny: [
            "re-export", "reexport"
        ]).count

        let lazyBindCount = analyzer.findSymbols(matchingAny: [
            "lazy_bind", "lazyBind"
        ]).count

        let weakBindCount = analyzer.findSymbols(matchingAny: [
            "weak_bind", "weakBind", "weak_import"
        ]).count

        if weakBindCount > 20 {
            issues.append(DiagnosticIssue(
                title: "High Weak Import Count",
                description: "Found \(weakBindCount) weak import symbol(s). Weak imports require additional processing by dyld at launch to check for their availability.",
                severity: .suggestion,
                instrument: .startup,
                category: "Dynamic Libraries",
                recommendation: "Reduce weak imports by setting a higher minimum deployment target (eliminating availability checks for older APIs). Use `@available` checks at a higher level rather than per-symbol weak linking.",
                impact: "Each weak import requires dyld to probe for the symbol's existence at launch. Large numbers of weak imports add measurable overhead to the symbol binding phase.",
                confidence: 0.45,
                details: [
                    .init(key: "Weak Imports", value: "\(weakBindCount)"),
                    .init(key: "Lazy Binds", value: "\(lazyBindCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Swift Metadata Analysis

    private func analyzeSwiftMetadata() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let swiftTypes = analyzer.swiftTypeCount
        let protocolConformances = analyzer.machOInfo.swiftProtocolConformances.count

        if protocolConformances > 500 {
            issues.append(DiagnosticIssue(
                title: "Large Swift Protocol Conformance Table",
                description: "Found \(protocolConformances) Swift protocol conformance(s). The Swift runtime processes conformance metadata at launch, and large conformance tables increase pre-main time.",
                severity: protocolConformances > 1000 ? .warning : .info,
                instrument: .startup,
                category: "Swift Metadata",
                recommendation: "Reduce protocol conformance count by consolidating generic conformance extensions and removing unused conformances. Use concrete types instead of protocol-based abstractions where dynamic dispatch isn't needed.",
                impact: "Swift protocol conformance tables are processed by the runtime at launch. Each conformance requires metadata validation. Very large apps can see 10-30ms from conformance processing alone.",
                confidence: analyzer.confidenceScore(evidenceCount: protocolConformances, lowThreshold: 300, highThreshold: 1000),
                details: [
                    .init(key: "Swift Types", value: "\(swiftTypes)"),
                    .init(key: "Protocol Conformances", value: "\(protocolConformances)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Eager Initialization Analysis

    private func analyzeEagerInitialization() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let singletonCount = analyzer.countAllEvidence(matchingAny: [
            ".shared", "sharedInstance", "singleton"
        ])

        let appDelegateCount = analyzer.countAllEvidence(matchingAny: [
            "didFinishLaunchingWithOptions",
            "applicationDidFinishLaunching",
            "willFinishLaunchingWithOptions"
        ])

        let sdkInitCount = analyzer.countAllEvidence(matchingAny: [
            "configure", "initialize", "setup", "start",
            "Firebase", "Crashlytics", "Analytics"
        ])

        if sdkInitCount > 5 {
            issues.append(DiagnosticIssue(
                title: "Multiple SDK Initializations at Launch",
                description: "Found \(sdkInitCount) SDK initialization/setup pattern(s). Initializing many SDKs in `didFinishLaunchingWithOptions` blocks the main thread during launch.",
                severity: sdkInitCount > 10 ? .warning : .info,
                instrument: .startup,
                category: "Eager Initialization",
                recommendation: "Defer non-essential SDK initialization until after first frame render. Use lazy initialization or background queues for SDKs that don't need to be ready immediately. Critical SDKs (crash reporting) should initialize first.",
                impact: "SDK initialization often involves disk I/O, network calls, and keychain access. Each SDK typically adds 10-50ms to launch time. Deferring non-critical SDKs can save 100-300ms.",
                confidence: analyzer.confidenceScore(evidenceCount: sdkInitCount, lowThreshold: 3, highThreshold: 15),
                details: [
                    .init(key: "SDK Init Patterns", value: "\(sdkInitCount)"),
                    .init(key: "Singleton Accesses", value: "\(singletonCount)"),
                    .init(key: "App Delegate Methods", value: "\(appDelegateCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Launch-Time Work Analysis

    private func analyzeLaunchTimeWork() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let coreDataCount = analyzer.countAllEvidence(matchingAny: [
            "NSPersistentContainer", "loadPersistentStores",
            "NSManagedObjectModel"
        ])

        let migrationCount = analyzer.countAllEvidence(matchingAny: [
            "NSMappingModel", "NSMigrationManager",
            "NSInferredMappingModelError"
        ])

        let keychainCount = analyzer.countAllEvidence(matchingAny: [
            "SecItemCopyMatching", "SecItemAdd", "SecItemUpdate",
            "Keychain"
        ])

        if coreDataCount > 0 && migrationCount > 0 {
            issues.append(DiagnosticIssue(
                title: "Core Data Migration at Launch Risk",
                description: "Found Core Data persistence (\(coreDataCount) patterns) with migration support (\(migrationCount) patterns). Lightweight migrations at launch can take seconds on large databases.",
                severity: .info,
                instrument: .startup,
                category: "Launch-Time Work",
                recommendation: "Load the persistent store asynchronously using `loadPersistentStores`'s completion handler. For heavy migrations, show a progress UI and migrate on a background thread. Consider using WAL journal mode for faster store loading.",
                impact: "Core Data migrations are synchronous by default and run on the calling thread. A lightweight migration on a large database can take 1-5 seconds, causing a visible launch delay.",
                confidence: 0.6,
                details: [
                    .init(key: "Core Data Patterns", value: "\(coreDataCount)"),
                    .init(key: "Migration Patterns", value: "\(migrationCount)"),
                    .init(key: "Keychain Ops", value: "\(keychainCount)")
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
            return "No significant launch time concerns detected. Your app appears to have a lean startup configuration."
        }

        let critical = issues.filter { $0.severity == .critical }.count
        let warnings = issues.filter { $0.severity == .warning }.count

        if critical > 0 {
            return "Found \(critical) critical and \(warnings) warning-level launch time issue(s). These patterns significantly impact time-to-first-frame and should be addressed."
        } else if warnings > 0 {
            return "Found \(warnings) warning-level launch time pattern(s) that may slow down app startup. Optimization recommended for better user experience."
        } else {
            return "Found \(issues.count) launch time finding(s). These are patterns worth reviewing to reduce time-to-first-frame."
        }
    }
}
