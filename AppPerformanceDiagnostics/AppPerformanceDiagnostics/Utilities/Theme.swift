import SwiftUI

/// Centralized design system for the app.
enum Theme {

    // MARK: - Colors

    enum Colors {
        static let background = Color(nsColor: .windowBackgroundColor)
        static let secondaryBackground = Color(nsColor: .controlBackgroundColor)
        static let tertiaryBackground = Color(nsColor: .underPageBackgroundColor)
        static let cardBackground = Color(nsColor: .controlBackgroundColor)

        static let primaryText = Color(nsColor: .labelColor)
        static let secondaryText = Color(nsColor: .secondaryLabelColor)
        static let tertiaryText = Color(nsColor: .tertiaryLabelColor)

        static let separator = Color(nsColor: .separatorColor)

        static let scoreExcellent = Color.green
        static let scoreGood = Color.mint
        static let scoreFair = Color.yellow
        static let scorePoor = Color.orange
        static let scoreCritical = Color.red

        static func scoreColor(for score: Int) -> Color {
            switch score {
            case 90...100: return scoreExcellent
            case 80..<90: return scoreGood
            case 70..<80: return scoreFair
            case 60..<70: return scorePoor
            default: return scoreCritical
            }
        }

        static func severityColor(for severity: Severity) -> Color {
            switch severity {
            case .critical: return .red
            case .warning: return .orange
            case .info: return .blue
            case .suggestion: return .secondary
            }
        }

        static let gradientPrimary = LinearGradient(
            colors: [.blue, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let gradientSuccess = LinearGradient(
            colors: [.green, .mint],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let gradientDanger = LinearGradient(
            colors: [.red, .orange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Typography

    enum Typography {
        static let largeTitle = Font.system(size: 28, weight: .bold, design: .rounded)
        static let title = Font.system(size: 22, weight: .semibold, design: .rounded)
        static let title2 = Font.system(size: 18, weight: .semibold, design: .rounded)
        static let title3 = Font.system(size: 16, weight: .medium, design: .rounded)
        static let headline = Font.system(size: 14, weight: .semibold)
        static let body = Font.system(size: 13, weight: .regular)
        static let callout = Font.system(size: 12, weight: .regular)
        static let caption = Font.system(size: 11, weight: .regular)
        static let caption2 = Font.system(size: 10, weight: .regular)
        static let monospaced = Font.system(size: 12, weight: .regular, design: .monospaced)
        static let scoreDisplay = Font.system(size: 48, weight: .bold, design: .rounded)
        static let scoreGrade = Font.system(size: 20, weight: .bold, design: .rounded)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxxSmall: CGFloat = 2
        static let xxSmall: CGFloat = 4
        static let xSmall: CGFloat = 6
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xLarge: CGFloat = 20
        static let xxLarge: CGFloat = 24
        static let xxxLarge: CGFloat = 32
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 14
        static let xLarge: CGFloat = 20
    }

    // MARK: - Shadow

    enum Shadow {
        static let small = ShadowStyle(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        static let medium = ShadowStyle(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        static let large = ShadowStyle(color: .black.opacity(0.15), radius: 16, x: 0, y: 8)
    }

    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

// MARK: - View Modifiers

struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.Spacing.large

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .shadow(
                color: Theme.Shadow.small.color,
                radius: Theme.Shadow.small.radius,
                x: Theme.Shadow.small.x,
                y: Theme.Shadow.small.y
            )
    }
}

struct SeverityBadgeModifier: ViewModifier {
    let severity: Severity

    func body(content: Content) -> some View {
        content
            .font(Theme.Typography.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.Colors.severityColor(for: severity).opacity(0.15))
            .foregroundStyle(Theme.Colors.severityColor(for: severity))
            .clipShape(Capsule())
    }
}

extension View {
    func cardStyle(padding: CGFloat = Theme.Spacing.large) -> some View {
        modifier(CardModifier(padding: padding))
    }

    func severityBadge(severity: Severity) -> some View {
        modifier(SeverityBadgeModifier(severity: severity))
    }
}
