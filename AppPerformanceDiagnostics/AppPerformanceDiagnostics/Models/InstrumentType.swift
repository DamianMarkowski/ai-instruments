import SwiftUI

/// Represents the different diagnostic instruments available for analysis.
enum InstrumentType: String, CaseIterable, Identifiable, Codable {
    case leaks = "Leaks"
    case concurrency = "Swift Concurrency"
    case allocations = "Allocations"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .leaks:
            return "drop.triangle.fill"
        case .concurrency:
            return "arrow.triangle.2.circlepath"
        case .allocations:
            return "memorychip.fill"
        }
    }

    var color: Color {
        switch self {
        case .leaks:
            return .red
        case .concurrency:
            return .purple
        case .allocations:
            return .blue
        }
    }

    var accentGradient: LinearGradient {
        switch self {
        case .leaks:
            return LinearGradient(
                colors: [.red, .orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .concurrency:
            return LinearGradient(
                colors: [.purple, .indigo],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .allocations:
            return LinearGradient(
                colors: [.blue, .cyan],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var subtitle: String {
        switch self {
        case .leaks:
            return "Memory Leak Detection"
        case .concurrency:
            return "Concurrency Safety Analysis"
        case .allocations:
            return "Memory Allocation Profiling"
        }
    }

    var instrumentDescription: String {
        switch self {
        case .leaks:
            return "Detects potential memory leaks by analyzing retain cycle patterns, delegate references, closure captures, notification observers, and timer lifecycle management in your application binary."
        case .concurrency:
            return "Analyzes Swift concurrency patterns including Sendable conformance, actor isolation, MainActor usage, data race potential, and unsafe concurrent access patterns."
        case .allocations:
            return "Profiles memory allocation patterns by examining large allocations, autorelease pool usage, image and data loading patterns, collection growth, and cache utilization."
        }
    }
}
