import SwiftUI

// MARK: - Date Extensions

extension Date {
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

// MARK: - Double Extensions

extension Double {
    var percentageString: String {
        String(format: "%.0f%%", self * 100)
    }

    var confidenceLabel: String {
        switch self {
        case 0.8...1.0: return "High"
        case 0.6..<0.8: return "Medium"
        case 0.4..<0.6: return "Low"
        default: return "Very Low"
        }
    }
}

// MARK: - Int Extensions

extension Int {
    var formattedCount: String {
        if self >= 1000 {
            return String(format: "%.1fK", Double(self) / 1000)
        }
        return "\(self)"
    }
}

// MARK: - View Extensions

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - URL Extensions

extension URL {
    var isIPAFile: Bool {
        pathExtension.lowercased() == "ipa"
    }

    var isAppBundle: Bool {
        pathExtension.lowercased() == "app"
    }

    var isSupportedForAnalysis: Bool {
        isIPAFile || isAppBundle
    }
}
