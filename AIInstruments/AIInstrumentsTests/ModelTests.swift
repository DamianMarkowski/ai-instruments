import Testing
import Nimble
@testable import AIInstruments

// MARK: - Severity Tests

@Suite("Severity Tests")
struct SeverityTests {

    @Test("Severity comparison follows expected order: critical < warning < info < suggestion")
    func severityOrdering() {
        expect(Severity.critical < Severity.warning).to(beTrue())
        expect(Severity.warning < Severity.info).to(beTrue())
        expect(Severity.info < Severity.suggestion).to(beTrue())
        expect(Severity.critical < Severity.suggestion).to(beTrue())
    }

    @Test("Severity weights decrease with severity level")
    func severityWeights() {
        expect(Severity.critical.weight).to(equal(25))
        expect(Severity.warning.weight).to(equal(10))
        expect(Severity.info.weight).to(equal(3))
        expect(Severity.suggestion.weight).to(equal(1))
    }

    @Test("Each severity has a non-empty icon")
    func severityIcons() {
        for severity in Severity.allCases {
            expect(severity.icon).toNot(beEmpty())
        }
    }

    @Test("Severity raw values match expected strings")
    func severityRawValues() {
        expect(Severity.critical.rawValue).to(equal("Critical"))
        expect(Severity.warning.rawValue).to(equal("Warning"))
        expect(Severity.info.rawValue).to(equal("Info"))
        expect(Severity.suggestion.rawValue).to(equal("Suggestion"))
    }

    @Test("There are exactly 4 severity levels")
    func severityCaseCount() {
        expect(Severity.allCases.count).to(equal(4))
    }
}

// MARK: - InstrumentType Tests

@Suite("InstrumentType Tests")
struct InstrumentTypeTests {

    @Test("Instrument types have correct raw values")
    func rawValues() {
        expect(InstrumentType.leaks.rawValue).to(equal("Leaks"))
        expect(InstrumentType.concurrency.rawValue).to(equal("Swift Concurrency"))
        expect(InstrumentType.allocations.rawValue).to(equal("Allocations"))
    }

    @Test("Instrument type id equals raw value")
    func ids() {
        for type in InstrumentType.allCases {
            expect(type.id).to(equal(type.rawValue))
        }
    }

    @Test("Each instrument type has a non-empty icon, subtitle, and description")
    func metadata() {
        for type in InstrumentType.allCases {
            expect(type.icon).toNot(beEmpty())
            expect(type.subtitle).toNot(beEmpty())
            expect(type.instrumentDescription).toNot(beEmpty())
        }
    }

    @Test("There are exactly 3 instrument types")
    func caseCount() {
        expect(InstrumentType.allCases.count).to(equal(3))
    }
}

// MARK: - DiagnosticIssue Tests

@Suite("DiagnosticIssue Tests")
struct DiagnosticIssueTests {

    @Test("DiagnosticIssue initializes with defaults")
    func initDefaults() {
        let issue = DiagnosticIssue(
            title: "Test Issue",
            description: "A test",
            severity: .warning,
            instrument: .leaks,
            category: "Test",
            recommendation: "Fix it",
            impact: "High"
        )

        expect(issue.title).to(equal("Test Issue"))
        expect(issue.severity).to(equal(.warning))
        expect(issue.instrument).to(equal(.leaks))
        expect(issue.confidence).to(equal(0.8))
        expect(issue.relatedSymbols).to(beEmpty())
        expect(issue.details).to(beEmpty())
        expect(issue.location).to(beNil())
    }

    @Test("DiagnosticIssue initializes with custom values")
    func initCustom() {
        let issue = DiagnosticIssue(
            title: "Custom",
            description: "Desc",
            severity: .critical,
            instrument: .concurrency,
            category: "Cat",
            location: "/path/to/file.swift:42",
            recommendation: "Rec",
            impact: "Severe",
            confidence: 0.95,
            relatedSymbols: ["sym1", "sym2"],
            details: [.init(key: "k", value: "v")]
        )

        expect(issue.location).to(equal("/path/to/file.swift:42"))
        expect(issue.confidence).to(equal(0.95))
        expect(issue.relatedSymbols).to(equal(["sym1", "sym2"]))
        expect(issue.details.count).to(equal(1))
    }

    @Test("Each DiagnosticIssue gets a unique ID")
    func uniqueIds() {
        let issue1 = DiagnosticIssue(title: "A", description: "", severity: .info, instrument: .leaks, category: "", recommendation: "", impact: "")
        let issue2 = DiagnosticIssue(title: "B", description: "", severity: .info, instrument: .leaks, category: "", recommendation: "", impact: "")
        expect(issue1.id).toNot(equal(issue2.id))
    }
}

// MARK: - AnalysisResult Tests

@Suite("AnalysisResult Tests")
struct AnalysisResultTests {

    @Test("Score is clamped between 0 and 100")
    func scoreClamping() {
        let overResult = AnalysisResult(instrument: .leaks, issues: [], summary: "", score: 150)
        expect(overResult.score).to(equal(100))

        let underResult = AnalysisResult(instrument: .leaks, issues: [], summary: "", score: -50)
        expect(underResult.score).to(equal(0))

        let normalResult = AnalysisResult(instrument: .leaks, issues: [], summary: "", score: 75)
        expect(normalResult.score).to(equal(75))
    }

    @Test("Score grade boundaries")
    func scoreGrade() {
        expect(AnalysisResult(instrument: .leaks, issues: [], summary: "", score: 95).scoreGrade).to(equal("A"))
        expect(AnalysisResult(instrument: .leaks, issues: [], summary: "", score: 90).scoreGrade).to(equal("A"))
        expect(AnalysisResult(instrument: .leaks, issues: [], summary: "", score: 89).scoreGrade).to(equal("B"))
        expect(AnalysisResult(instrument: .leaks, issues: [], summary: "", score: 80).scoreGrade).to(equal("B"))
        expect(AnalysisResult(instrument: .leaks, issues: [], summary: "", score: 79).scoreGrade).to(equal("C"))
        expect(AnalysisResult(instrument: .leaks, issues: [], summary: "", score: 70).scoreGrade).to(equal("C"))
        expect(AnalysisResult(instrument: .leaks, issues: [], summary: "", score: 69).scoreGrade).to(equal("D"))
        expect(AnalysisResult(instrument: .leaks, issues: [], summary: "", score: 60).scoreGrade).to(equal("D"))
        expect(AnalysisResult(instrument: .leaks, issues: [], summary: "", score: 59).scoreGrade).to(equal("F"))
        expect(AnalysisResult(instrument: .leaks, issues: [], summary: "", score: 0).scoreGrade).to(equal("F"))
    }

    @Test("Issue count computed properties")
    func issueCounts() {
        let issues = [
            DiagnosticIssue(title: "", description: "", severity: .critical, instrument: .leaks, category: "", recommendation: "", impact: ""),
            DiagnosticIssue(title: "", description: "", severity: .critical, instrument: .leaks, category: "", recommendation: "", impact: ""),
            DiagnosticIssue(title: "", description: "", severity: .warning, instrument: .leaks, category: "", recommendation: "", impact: ""),
            DiagnosticIssue(title: "", description: "", severity: .info, instrument: .leaks, category: "", recommendation: "", impact: ""),
            DiagnosticIssue(title: "", description: "", severity: .suggestion, instrument: .leaks, category: "", recommendation: "", impact: ""),
        ]

        let result = AnalysisResult(instrument: .leaks, issues: issues, summary: "", score: 50)
        expect(result.criticalCount).to(equal(2))
        expect(result.warningCount).to(equal(1))
        expect(result.infoCount).to(equal(1))
        expect(result.suggestionCount).to(equal(1))
    }
}

// MARK: - AnalysisReport Tests

@Suite("AnalysisReport Tests")
struct AnalysisReportTests {

    @Test("Report with no results has score 100")
    func emptyReport() {
        let report = AnalysisReport(appName: "Test", bundleIdentifier: "com.test", results: [])
        expect(report.overallScore).to(equal(100))
        expect(report.totalIssues).to(equal(0))
        expect(report.totalCritical).to(equal(0))
        expect(report.totalWarnings).to(equal(0))
        expect(report.allIssues).to(beEmpty())
    }

    @Test("Report overall score is average of result scores")
    func overallScore() {
        let r1 = AnalysisResult(instrument: .leaks, issues: [], summary: "", score: 80)
        let r2 = AnalysisResult(instrument: .concurrency, issues: [], summary: "", score: 60)
        let r3 = AnalysisResult(instrument: .allocations, issues: [], summary: "", score: 100)

        let report = AnalysisReport(appName: "Test", bundleIdentifier: "com.test", results: [r1, r2, r3])
        expect(report.overallScore).to(equal(80))
    }

    @Test("Report aggregates issues from all results")
    func aggregatedIssues() {
        let issue1 = DiagnosticIssue(title: "I1", description: "", severity: .critical, instrument: .leaks, category: "", recommendation: "", impact: "")
        let issue2 = DiagnosticIssue(title: "I2", description: "", severity: .warning, instrument: .concurrency, category: "", recommendation: "", impact: "")
        let r1 = AnalysisResult(instrument: .leaks, issues: [issue1], summary: "", score: 75)
        let r2 = AnalysisResult(instrument: .concurrency, issues: [issue2], summary: "", score: 90)

        let report = AnalysisReport(appName: "Test", bundleIdentifier: "com.test", results: [r1, r2])
        expect(report.totalIssues).to(equal(2))
        expect(report.totalCritical).to(equal(1))
        expect(report.totalWarnings).to(equal(1))
        expect(report.allIssues.count).to(equal(2))
    }

    @Test("Report overall grade boundaries")
    func overallGrade() {
        let makeReport = { (score: Int) -> AnalysisReport in
            let r = AnalysisResult(instrument: .leaks, issues: [], summary: "", score: score)
            return AnalysisReport(appName: "T", bundleIdentifier: "c", results: [r])
        }
        expect(makeReport(95).overallGrade).to(equal("A"))
        expect(makeReport(85).overallGrade).to(equal("B"))
        expect(makeReport(75).overallGrade).to(equal("C"))
        expect(makeReport(65).overallGrade).to(equal("D"))
        expect(makeReport(50).overallGrade).to(equal("F"))
    }

    @Test("Report metadata is populated correctly")
    func metadata() {
        let report = AnalysisReport(
            appName: "MyApp",
            bundleIdentifier: "com.example.myapp",
            appVersion: "2.1",
            results: []
        )
        expect(report.appName).to(equal("MyApp"))
        expect(report.bundleIdentifier).to(equal("com.example.myapp"))
        expect(report.appVersion).to(equal("2.1"))
    }
}

// MARK: - MachOInfo Tests

@Suite("MachOInfo Tests")
struct MachOInfoTests {

    @Test("MachOInfo.invalid has expected default values")
    func invalidInfo() {
        let info = MachOInfo.invalid
        expect(info.isValid).to(beFalse())
        expect(info.isFatBinary).to(beFalse())
        expect(info.isEncrypted).to(beFalse())
        expect(info.architecture).to(equal("Unknown"))
        expect(info.symbols).to(beEmpty())
        expect(info.objcClasses).to(beEmpty())
        expect(info.totalTextSize).to(equal(0))
    }

    @Test("Merging two MachOInfo combines their data")
    func merging() {
        let info1 = MachOInfoBuilder().build()
        var builder2 = MachOInfoBuilder()
        builder2.symbols = [makeSymbol("_extra_sym")]
        builder2.objcClasses = ["ExtraClass"]
        builder2.objcSelectors = ["extraSelector"]
        builder2.extractedStrings = ["extra string"]
        builder2.totalTextSize = 100
        builder2.totalDataSize = 50
        let info2 = builder2.build()

        let merged = info1.merging(with: info2)
        expect(merged.isValid).to(beTrue())
        expect(merged.symbols.count).to(equal(1))
        expect(merged.objcClasses).to(contain("ExtraClass"))
        expect(merged.objcSelectors).to(contain("extraSelector"))
        expect(merged.extractedStrings).to(contain("extra string"))
        expect(merged.totalTextSize).to(equal(100))
        expect(merged.totalDataSize).to(equal(50))
    }

    @Test("Merging deduplicates classes and selectors")
    func mergingDeduplicates() {
        var b1 = MachOInfoBuilder()
        b1.objcClasses = ["ClassA", "ClassB"]
        b1.objcSelectors = ["sel1", "sel2"]
        let info1 = b1.build()

        var b2 = MachOInfoBuilder()
        b2.objcClasses = ["ClassB", "ClassC"]
        b2.objcSelectors = ["sel2", "sel3"]
        let info2 = b2.build()

        let merged = info1.merging(with: info2)
        expect(Set(merged.objcClasses)).to(equal(Set(["ClassA", "ClassB", "ClassC"])))
        expect(Set(merged.objcSelectors)).to(equal(Set(["sel1", "sel2", "sel3"])))
    }
}
