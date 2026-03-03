import SwiftUI

/// Represents the different diagnostic instruments available for analysis.
enum InstrumentType: String, CaseIterable, Identifiable, Codable {
    case leaks = "Leaks"
    case concurrency = "Swift Concurrency"
    case allocations = "Allocations"
    case energy = "Energy"
    case network = "Network"
    case hangs = "Hangs"
    case startup = "App Launch"
    case diskIO = "File Activity"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .leaks:
            return "drop.triangle.fill"
        case .concurrency:
            return "arrow.triangle.2.circlepath"
        case .allocations:
            return "memorychip.fill"
        case .energy:
            return "bolt.fill"
        case .network:
            return "network"
        case .hangs:
            return "hourglass"
        case .startup:
            return "flag.checkered"
        case .diskIO:
            return "internaldrive.fill"
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
        case .energy:
            return .green
        case .network:
            return .orange
        case .hangs:
            return .yellow
        case .startup:
            return .mint
        case .diskIO:
            return .brown
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
        case .energy:
            return LinearGradient(
                colors: [.green, .yellow],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .network:
            return LinearGradient(
                colors: [.orange, .red],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .hangs:
            return LinearGradient(
                colors: [.yellow, .orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .startup:
            return LinearGradient(
                colors: [.mint, .teal],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .diskIO:
            return LinearGradient(
                colors: [.brown, .orange],
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
        case .energy:
            return "Energy Impact Analysis"
        case .network:
            return "Network Usage Analysis"
        case .hangs:
            return "UI Responsiveness Analysis"
        case .startup:
            return "Launch Performance Analysis"
        case .diskIO:
            return "File Activity Analysis"
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
        case .energy:
            return "Identifies patterns that impact battery life including continuous location tracking, excessive timer usage, background processing, network session configuration, and sensor access patterns."
        case .network:
            return "Analyzes networking patterns including URL session configuration, App Transport Security compliance, certificate pinning, caching strategies, background transfers, and third-party networking framework usage."
        case .hangs:
            return "Detects patterns that cause UI hangs and main thread blocking, including synchronous I/O on the main thread, heavy computation, complex view hierarchies, and missing prefetching in scroll views."
        case .startup:
            return "Analyzes factors that affect app launch time including static initializer count, linked framework overhead, ObjC class registration cost, and binary size impact on cold launch."
        case .diskIO:
            return "Profiles file system access patterns including synchronous disk operations, large file handling, Core Data and SQLite usage, file coordination, and temporary file management."
        }
    }
}
