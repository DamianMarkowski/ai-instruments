import Testing
import Nimble
@testable import AIInstruments

@Suite("BinaryAnalyzer Tests")
struct BinaryAnalyzerTests {

    // MARK: - Symbol Matching

    @Test("findSymbols matching is case-insensitive by default")
    func findSymbolsCaseInsensitive() {
        let analyzer = makeBinaryAnalyzer(symbols: [
            makeSymbol("_MyClass_delegate"),
            makeSymbol("_SomeOtherSymbol"),
            makeSymbol("_setDelegate"),
        ])

        let results = analyzer.findSymbols(matching: "delegate")
        expect(results.count).to(equal(2))
    }

    @Test("findSymbols matching with case sensitivity")
    func findSymbolsCaseSensitive() {
        let analyzer = makeBinaryAnalyzer(symbols: [
            makeSymbol("_MyClass_Delegate"),
            makeSymbol("_myclass_delegate"),
        ])

        let sensitive = analyzer.findSymbols(matching: "Delegate", caseSensitive: true)
        expect(sensitive.count).to(equal(1))
        expect(sensitive.first?.name).to(equal("_MyClass_Delegate"))
    }

    @Test("findSymbols matchingAny returns symbols matching any pattern")
    func findSymbolsMatchingAny() {
        let analyzer = makeBinaryAnalyzer(symbols: [
            makeSymbol("_delegate"),
            makeSymbol("_dataSource"),
            makeSymbol("_unrelated"),
        ])

        let results = analyzer.findSymbols(matchingAny: ["delegate", "dataSource"])
        expect(results.count).to(equal(2))
    }

    @Test("countSymbols returns correct count")
    func countSymbols() {
        let analyzer = makeBinaryAnalyzer(symbols: [
            makeSymbol("_timer_create"),
            makeSymbol("_timer_invalidate"),
            makeSymbol("_other"),
        ])

        expect(analyzer.countSymbols(matching: "timer")).to(equal(2))
        expect(analyzer.countSymbols(matching: "nonexistent")).to(equal(0))
    }

    // MARK: - String Matching

    @Test("findStrings matching is case-insensitive by default")
    func findStrings() {
        let analyzer = makeBinaryAnalyzer(extractedStrings: [
            "UIImageView", "uiimageview", "NSString"
        ])

        let results = analyzer.findStrings(matching: "UIImageView")
        expect(results.count).to(equal(2))
    }

    // MARK: - Class Analysis

    @Test("hasClass checks ObjC classes")
    func hasClass() {
        let analyzer = makeBinaryAnalyzer(objcClasses: ["AppDelegate", "ViewController"])
        expect(analyzer.hasClass("AppDelegate")).to(beTrue())
        expect(analyzer.hasClass("NonExistent")).to(beFalse())
    }

    @Test("findClasses returns matching classes")
    func findClasses() {
        let analyzer = makeBinaryAnalyzer(objcClasses: [
            "MainViewController", "SettingsViewController", "AppDelegate"
        ])

        let results = analyzer.findClasses(matching: "viewcontroller")
        expect(results.count).to(equal(2))
    }

    @Test("findViewControllerClasses finds VC-like class names")
    func findViewControllerClasses() {
        let analyzer = makeBinaryAnalyzer(objcClasses: [
            "MainViewController", "LoginController", "ProfileVC",
            "AppDelegate", "NetworkService"
        ])

        let vcs = analyzer.findViewControllerClasses()
        expect(vcs.count).to(equal(3))
        expect(vcs).to(contain("MainViewController"))
        expect(vcs).to(contain("LoginController"))
        expect(vcs).to(contain("ProfileVC"))
    }

    // MARK: - Framework Analysis

    @Test("isFrameworkLinked detects linked frameworks")
    func isFrameworkLinked() {
        let analyzer = makeBinaryAnalyzer(linkedLibraries: [
            "/System/Library/Frameworks/UIKit.framework/UIKit",
            "/usr/lib/libswiftCore.dylib",
            "@rpath/Alamofire.framework/Alamofire"
        ])

        expect(analyzer.isFrameworkLinked("UIKit")).to(beTrue())
        expect(analyzer.isFrameworkLinked("libswiftCore")).to(beTrue())
        expect(analyzer.isFrameworkLinked("Alamofire")).to(beTrue())
        expect(analyzer.isFrameworkLinked("CoreData")).to(beFalse())
    }

    @Test("systemFrameworks filters system libraries")
    func systemFrameworks() {
        let analyzer = makeBinaryAnalyzer(linkedLibraries: [
            "/System/Library/Frameworks/UIKit.framework/UIKit",
            "/usr/lib/libswiftCore.dylib",
            "@rpath/Alamofire.framework/Alamofire"
        ])

        let system = analyzer.systemFrameworks()
        expect(system.count).to(equal(2))
    }

    @Test("embeddedFrameworks filters non-system libraries")
    func embeddedFrameworks() {
        let analyzer = makeBinaryAnalyzer(linkedLibraries: [
            "/System/Library/Frameworks/UIKit.framework/UIKit",
            "@rpath/Alamofire.framework/Alamofire",
            "@executable_path/../Frameworks/MyLib.framework/MyLib"
        ])

        let embedded = analyzer.embeddedFrameworks()
        expect(embedded.count).to(equal(2))
    }

    // MARK: - Section Analysis

    @Test("sectionSize returns correct size")
    func sectionSize() {
        let analyzer = makeBinaryAnalyzer(sections: [
            SectionInfo(name: "__text", segmentName: "__TEXT", address: 0, size: 1024, offset: 0, align: 4),
            SectionInfo(name: "__data", segmentName: "__DATA", address: 0, size: 512, offset: 0, align: 4),
        ])

        expect(analyzer.sectionSize(segment: "__TEXT", section: "__text")).to(equal(1024))
        expect(analyzer.sectionSize(segment: "__DATA", section: "__data")).to(equal(512))
        expect(analyzer.sectionSize(segment: "__TEXT", section: "__nonexistent")).to(equal(0))
    }

    @Test("hasSection checks section existence")
    func hasSection() {
        let analyzer = makeBinaryAnalyzer(sections: [
            SectionInfo(name: "__text", segmentName: "__TEXT", address: 0, size: 100, offset: 0, align: 4)
        ])

        expect(analyzer.hasSection(segment: "__TEXT", section: "__text")).to(beTrue())
        expect(analyzer.hasSection(segment: "__DATA", section: "__bss")).to(beFalse())
    }

    // MARK: - Swift Detection

    @Test("usesSwift detects Swift via libswiftCore")
    func usesSwiftViaLibrary() {
        let analyzer = makeBinaryAnalyzer(linkedLibraries: ["/usr/lib/libswiftCore.dylib"])
        expect(analyzer.usesSwift).to(beTrue())
    }

    @Test("usesSwift detects Swift via swift sections")
    func usesSwiftViaSections() {
        let analyzer = makeBinaryAnalyzer(sections: [
            SectionInfo(name: "__swift5_types", segmentName: "__TEXT", address: 0, size: 100, offset: 0, align: 4)
        ])
        expect(analyzer.usesSwift).to(beTrue())
    }

    @Test("usesSwift detects Swift via symbol names")
    func usesSwiftViaSymbols() {
        let analyzer = makeBinaryAnalyzer(symbols: [makeSymbol("_$s4Main7MyClassCN")])
        expect(analyzer.usesSwift).to(beTrue())
    }

    @Test("usesSwift is false for pure ObjC binary")
    func noSwift() {
        let analyzer = makeBinaryAnalyzer(
            symbols: [makeSymbol("_OBJC_CLASS_$_AppDelegate")],
            linkedLibraries: ["/System/Library/Frameworks/UIKit.framework/UIKit"]
        )
        expect(analyzer.usesSwift).to(beFalse())
    }

    @Test("usesSwiftConcurrency detects concurrency library")
    func usesSwiftConcurrency() {
        let analyzer = makeBinaryAnalyzer(linkedLibraries: ["/usr/lib/swift/libswift_Concurrency.dylib"])
        expect(analyzer.usesSwiftConcurrency).to(beTrue())
    }

    // MARK: - Selector Analysis

    @Test("findSelectors matching works case-insensitively")
    func findSelectors() {
        let analyzer = makeBinaryAnalyzer(objcSelectors: [
            "setDelegate:", "viewDidLoad", "setDataSource:"
        ])

        let results = analyzer.findSelectors(matching: "delegate")
        expect(results.count).to(equal(1))
    }

    @Test("findSelectors matchingAny works with multiple patterns")
    func findSelectorsMatchingAny() {
        let analyzer = makeBinaryAnalyzer(objcSelectors: [
            "setDelegate:", "viewDidLoad", "addObserver:selector:name:object:"
        ])

        let results = analyzer.findSelectors(matchingAny: ["delegate", "observer"])
        expect(results.count).to(equal(2))
    }

    @Test("hasSelector checks exact selector presence")
    func hasSelector() {
        let analyzer = makeBinaryAnalyzer(objcSelectors: ["viewDidLoad", "init"])
        expect(analyzer.hasSelector("viewDidLoad")).to(beTrue())
        expect(analyzer.hasSelector("viewDidAppear:")).to(beFalse())
    }

    // MARK: - Evidence Search

    @Test("countAllEvidence combines symbols and selectors")
    func countAllEvidence() {
        let analyzer = makeBinaryAnalyzer(
            symbols: [makeSymbol("_addObserver"), makeSymbol("_removeObserver")],
            objcSelectors: ["addObserver:selector:name:object:"]
        )

        let count = analyzer.countAllEvidence(matchingAny: ["addObserver"])
        expect(count).to(equal(2)) // 1 symbol + 1 selector
    }

    // MARK: - Combined Class Names

    @Test("allClassNames combines ObjC classes and Swift type descriptors")
    func allClassNames() {
        let analyzer = makeBinaryAnalyzer(
            objcClasses: ["ObjcClass"],
            swiftTypeDescriptors: ["SwiftModule.SwiftClass"]
        )

        expect(analyzer.allClassNames.count).to(equal(2))
        expect(analyzer.allClassNames).to(contain("ObjcClass"))
        expect(analyzer.allClassNames).to(contain("SwiftModule.SwiftClass"))
    }

    @Test("findAllViewControllerClasses searches combined names")
    func findAllViewControllerClasses() {
        let analyzer = makeBinaryAnalyzer(
            objcClasses: ["MainViewController"],
            swiftTypeDescriptors: ["App.LoginController"]
        )

        let vcs = analyzer.findAllViewControllerClasses()
        expect(vcs.count).to(equal(2))
    }

    // MARK: - Confidence Score

    @Test("confidenceScore returns 0 for no evidence")
    func confidenceScoreZero() {
        let analyzer = makeBinaryAnalyzer()
        expect(analyzer.confidenceScore(evidenceCount: 0)).to(equal(0))
        expect(analyzer.confidenceScore(evidenceCount: -1)).to(equal(0))
    }

    @Test("confidenceScore returns 1.0 at or above high threshold")
    func confidenceScoreMax() {
        let analyzer = makeBinaryAnalyzer()
        expect(analyzer.confidenceScore(evidenceCount: 10)).to(equal(1.0))
        expect(analyzer.confidenceScore(evidenceCount: 100)).to(equal(1.0))
    }

    @Test("confidenceScore scales between thresholds")
    func confidenceScoreScaling() {
        let analyzer = makeBinaryAnalyzer()
        let mid = analyzer.confidenceScore(evidenceCount: 5, lowThreshold: 1, highThreshold: 10)
        expect(mid).to(beGreaterThan(0.0))
        expect(mid).to(beLessThan(1.0))
    }
}
