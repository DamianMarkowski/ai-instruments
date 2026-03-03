import Testing
import Nimble
@testable import AIInstruments

@Suite("StartupAnalyzer Tests")
struct StartupAnalyzerTests {

    // MARK: - Basic Analysis

    @Test("Analyzing small binary with no patterns produces clean result")
    func cleanBinary() {
        let ba = makeBinaryAnalyzer()
        let result = StartupAnalyzer(binaryAnalyzer: ba, binarySize: 1_000).analyze()

        expect(result.instrument).to(equal(.startup))
        expect(result.score).to(equal(100))
        expect(result.analysisTimeSeconds).to(beGreaterThanOrEqualTo(0))
    }

    // MARK: - Static Initializer Detection

    @Test("Detects significant static initializer count")
    func staticInitializers() {
        var symbols: [SymbolInfo] = []
        for i in 0..<8 {
            symbols.append(makeSymbol("_globalinit_\(i)"))
        }

        let ba = makeBinaryAnalyzer(
            symbols: symbols,
            objcSelectors: ["load"]
        )
        let result = StartupAnalyzer(binaryAnalyzer: ba, binarySize: 1_000).analyze()
        let initIssues = result.issues.filter { $0.category == "Static Initializers" }
        expect(initIssues).toNot(beEmpty())
    }

    // MARK: - Linked Framework Detection

    @Test("Detects high number of linked libraries")
    func manyLinkedLibraries() {
        var libraries: [String] = []
        for i in 0..<55 {
            libraries.append("/System/Library/Framework\(i).framework/Framework\(i)")
        }

        let ba = makeBinaryAnalyzer(linkedLibraries: libraries)
        let result = StartupAnalyzer(binaryAnalyzer: ba, binarySize: 1_000).analyze()
        let frameworkIssues = result.issues.filter { $0.category == "Linked Frameworks" }
        expect(frameworkIssues).toNot(beEmpty())
    }

    @Test("Detects excessive embedded frameworks")
    func excessiveEmbeddedFrameworks() {
        var libraries: [String] = []
        for i in 0..<25 {
            libraries.append("@rpath/Framework\(i).framework/Framework\(i)")
        }

        let ba = makeBinaryAnalyzer(linkedLibraries: libraries)
        let result = StartupAnalyzer(binaryAnalyzer: ba, binarySize: 1_000).analyze()
        let embeddedIssues = result.issues.filter { $0.title.contains("Embedded") }
        expect(embeddedIssues).toNot(beEmpty())
    }

    // MARK: - ObjC Class Count Detection

    @Test("Detects large ObjC class count")
    func largeObjCClassCount() {
        var classes: [String] = []
        for i in 0..<5500 {
            classes.append("Class\(i)")
        }

        let ba = makeBinaryAnalyzer(objcClasses: classes)
        let result = StartupAnalyzer(binaryAnalyzer: ba, binarySize: 1_000).analyze()
        let classIssues = result.issues.filter { $0.category == "ObjC Registration" }
        expect(classIssues).toNot(beEmpty())
    }

    @Test("No ObjC class issue for small class count")
    func smallObjCClassCount() {
        let ba = makeBinaryAnalyzer(objcClasses: ["ClassA", "ClassB", "ClassC"])
        let result = StartupAnalyzer(binaryAnalyzer: ba, binarySize: 1_000).analyze()
        let classIssues = result.issues.filter { $0.category == "ObjC Registration" }
        expect(classIssues).to(beEmpty())
    }

    // MARK: - Binary Size Impact Detection

    @Test("Detects binary size impact on cold launch")
    func largeBinarySize() {
        let ba = makeBinaryAnalyzer(totalTextSize: 30_000_000)
        let result = StartupAnalyzer(binaryAnalyzer: ba, binarySize: 60_000_000).analyze()
        let sizeIssues = result.issues.filter { $0.category == "Binary Size" }
        expect(sizeIssues).toNot(beEmpty())
    }

    @Test("No binary size issue for small binaries")
    func smallBinarySize() {
        let ba = makeBinaryAnalyzer()
        let result = StartupAnalyzer(binaryAnalyzer: ba, binarySize: 5_000_000).analyze()
        let sizeIssues = result.issues.filter { $0.category == "Binary Size" }
        expect(sizeIssues).to(beEmpty())
    }

    // MARK: - Swift Metadata Detection

    @Test("Detects large protocol conformance table")
    func largeProtocolConformances() {
        var conformances: [String] = []
        for i in 0..<600 {
            conformances.append("Conformance\(i)")
        }

        let ba = makeBinaryAnalyzer(swiftProtocolConformances: conformances)
        let result = StartupAnalyzer(binaryAnalyzer: ba, binarySize: 1_000).analyze()
        let metaIssues = result.issues.filter { $0.category == "Swift Metadata" }
        expect(metaIssues).toNot(beEmpty())
    }

    // MARK: - Eager Initialization Detection

    @Test("Detects multiple SDK initializations at launch")
    func multipleSdkInits() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_Firebase_configure"),
                makeSymbol("_Crashlytics_init"),
                makeSymbol("_Analytics_initialize"),
                makeSymbol("_setup_sdk_1"),
                makeSymbol("_initialize_sdk_2"),
                makeSymbol("_start_sdk_3"),
            ]
        )

        let result = StartupAnalyzer(binaryAnalyzer: ba, binarySize: 1_000).analyze()
        let initIssues = result.issues.filter { $0.category == "Eager Initialization" }
        expect(initIssues).toNot(beEmpty())
    }

    // MARK: - Launch-Time Work Detection

    @Test("Detects Core Data migration at launch risk")
    func coreDataMigrationRisk() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_NSPersistentContainer"),
                makeSymbol("_loadPersistentStores"),
                makeSymbol("_NSMappingModel"),
                makeSymbol("_NSMigrationManager"),
            ]
        )

        let result = StartupAnalyzer(binaryAnalyzer: ba, binarySize: 1_000).analyze()
        let launchIssues = result.issues.filter { $0.category == "Launch-Time Work" }
        expect(launchIssues).toNot(beEmpty())
    }

    // MARK: - Scoring

    @Test("Score decreases with more issues")
    func scoringPenalty() {
        let cleanBa = makeBinaryAnalyzer()
        let cleanResult = StartupAnalyzer(binaryAnalyzer: cleanBa, binarySize: 1_000).analyze()
        expect(cleanResult.score).to(equal(100))

        var libraries: [String] = []
        for i in 0..<55 {
            libraries.append("/System/Library/Framework\(i).framework/Framework\(i)")
        }
        let dirtyBa = makeBinaryAnalyzer(linkedLibraries: libraries)
        let dirtyResult = StartupAnalyzer(binaryAnalyzer: dirtyBa, binarySize: 60_000_000).analyze()
        expect(dirtyResult.score).to(beLessThan(cleanResult.score))
    }

    // MARK: - Metadata

    @Test("Result metadata contains expected keys")
    func metadata() {
        let ba = makeBinaryAnalyzer()
        let result = StartupAnalyzer(binaryAnalyzer: ba, binarySize: 5_000_000).analyze()
        expect(result.metadata["binarySizeMB"]).toNot(beNil())
        expect(result.metadata["linkedLibraryCount"]).toNot(beNil())
        expect(result.metadata["objcClassCount"]).toNot(beNil())
        expect(result.metadata["swiftTypeCount"]).toNot(beNil())
    }
}
