import Foundation

/// Severity level for diagnostic issues, ordered from most to least severe.
enum Severity: String, Codable, CaseIterable, Comparable {
    case critical = "Critical"
    case warning = "Warning"
    case info = "Info"
    case suggestion = "Suggestion"

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        let order: [Severity] = [.critical, .warning, .info, .suggestion]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else { return false }
        return lhsIndex < rhsIndex
    }

    var icon: String {
        switch self {
        case .critical: return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .suggestion: return "lightbulb.fill"
        }
    }

    var weight: Int {
        switch self {
        case .critical: return 25
        case .warning: return 10
        case .info: return 3
        case .suggestion: return 1
        }
    }
}

/// Represents a single diagnostic issue found during analysis.
struct DiagnosticIssue: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String
    let severity: Severity
    let instrument: InstrumentType
    let category: String
    let location: String?
    let recommendation: String
    let impact: String
    let confidence: Double // 0.0 - 1.0
    let relatedSymbols: [String]
    let details: [DetailEntry]

    struct DetailEntry: Codable, Identifiable {
        var id: String { key }
        let key: String
        let value: String
    }

    init(
        title: String,
        description: String,
        severity: Severity,
        instrument: InstrumentType,
        category: String,
        location: String? = nil,
        recommendation: String,
        impact: String,
        confidence: Double = 0.8,
        relatedSymbols: [String] = [],
        details: [DetailEntry] = []
    ) {
        self.id = UUID()
        self.title = title
        self.description = description
        self.severity = severity
        self.instrument = instrument
        self.category = category
        self.location = location
        self.recommendation = recommendation
        self.impact = impact
        self.confidence = confidence
        self.relatedSymbols = relatedSymbols
        self.details = details
    }
}
