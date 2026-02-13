import Foundation

/// Contains the analysis results for a single instrument.
struct AnalysisResult: Identifiable {
    let id: UUID
    let instrument: InstrumentType
    let issues: [DiagnosticIssue]
    let summary: String
    let score: Int // 0-100 health score (100 = no issues)
    let timestamp: Date
    let analysisTimeSeconds: Double
    let metadata: [String: String]

    init(
        instrument: InstrumentType,
        issues: [DiagnosticIssue],
        summary: String,
        score: Int,
        analysisTimeSeconds: Double = 0,
        metadata: [String: String] = [:]
    ) {
        self.id = UUID()
        self.instrument = instrument
        self.issues = issues
        self.summary = summary
        self.score = max(0, min(100, score))
        self.timestamp = Date()
        self.analysisTimeSeconds = analysisTimeSeconds
        self.metadata = metadata
    }

    var criticalCount: Int {
        issues.filter { $0.severity == .critical }.count
    }

    var warningCount: Int {
        issues.filter { $0.severity == .warning }.count
    }

    var infoCount: Int {
        issues.filter { $0.severity == .info }.count
    }

    var suggestionCount: Int {
        issues.filter { $0.severity == .suggestion }.count
    }

    var scoreGrade: String {
        switch score {
        case 90...100: return "A"
        case 80..<90: return "B"
        case 70..<80: return "C"
        case 60..<70: return "D"
        default: return "F"
        }
    }
}

/// Aggregated analysis report for the entire application.
struct AnalysisReport: Identifiable {
    let id: UUID
    let appName: String
    let bundleIdentifier: String
    let appVersion: String
    let results: [AnalysisResult]
    let overallScore: Int
    let analysisDate: Date
    let totalAnalysisTime: Double

    init(
        appName: String,
        bundleIdentifier: String,
        appVersion: String = "Unknown",
        results: [AnalysisResult]
    ) {
        self.id = UUID()
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.appVersion = appVersion
        self.results = results
        self.analysisDate = Date()
        self.totalAnalysisTime = results.reduce(0) { $0 + $1.analysisTimeSeconds }

        // Weighted average score
        if results.isEmpty {
            self.overallScore = 100
        } else {
            let totalScore = results.reduce(0) { $0 + $1.score }
            self.overallScore = totalScore / results.count
        }
    }

    var totalIssues: Int {
        results.reduce(0) { $0 + $1.issues.count }
    }

    var totalCritical: Int {
        results.reduce(0) { $0 + $1.criticalCount }
    }

    var totalWarnings: Int {
        results.reduce(0) { $0 + $1.warningCount }
    }

    var allIssues: [DiagnosticIssue] {
        results.flatMap { $0.issues }.sorted { $0.severity < $1.severity }
    }

    var overallGrade: String {
        switch overallScore {
        case 90...100: return "A"
        case 80..<90: return "B"
        case 70..<80: return "C"
        case 60..<70: return "D"
        default: return "F"
        }
    }
}
