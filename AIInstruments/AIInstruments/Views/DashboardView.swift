import SwiftUI

/// Dashboard overview showing issue counts and per-instrument results.
struct DashboardView: View {
    let report: AnalysisReport
    let onSelectInstrument: (InstrumentType) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xxLarge) {
                // Header
                headerSection

                // Instrument Cards Grid
                instrumentCardsSection

                // Issues Summary
                issuesSummarySection

                // Top Issues
                topIssuesSection
            }
            .padding(Theme.Spacing.xxLarge)
        }
        .background(Theme.Colors.background)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: Theme.Spacing.xxLarge) {
            // Overall issue count
            overallIssuesView

            // App Summary
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                Text(report.appName)
                    .font(Theme.Typography.title)

                Text(report.bundleIdentifier)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.secondaryText)

                HStack(spacing: Theme.Spacing.medium) {
                    summaryChip(
                        icon: "exclamationmark.octagon.fill",
                        text: "\(report.totalCritical) Critical",
                        color: .red
                    )
                    summaryChip(
                        icon: "exclamationmark.triangle.fill",
                        text: "\(report.totalWarnings) Warnings",
                        color: .orange
                    )
                    summaryChip(
                        icon: "doc.text.magnifyingglass",
                        text: "\(report.totalIssues) Total",
                        color: .secondary
                    )
                }

                Text("Analyzed on \(report.analysisDate.formattedTimestamp)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }

            Spacer()
        }
        .cardStyle()
    }

    private var overallIssuesView: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.separator.opacity(0.3), lineWidth: 8)
                .frame(width: 100, height: 100)

            VStack(spacing: 0) {
                Text("\(report.totalIssues)")
                    .font(Theme.Typography.scoreDisplay)
                    .foregroundStyle(Theme.Colors.primaryText)

                Text("issue\(report.totalIssues == 1 ? "" : "s")")
                    .font(Theme.Typography.scoreGrade)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
    }

    private func summaryChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(Theme.Typography.caption)
        }
        .foregroundStyle(color)
    }

    // MARK: - Instrument Cards

    private var instrumentCardsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text("Instruments")
                .font(Theme.Typography.title3)

            HStack(spacing: Theme.Spacing.medium) {
                ForEach(report.results, id: \.instrument) { result in
                    instrumentIssueCard(result)
                }
            }
        }
    }

    private func instrumentIssueCard(_ result: AnalysisResult) -> some View {
        Button {
            onSelectInstrument(result.instrument)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                HStack {
                    Image(systemName: result.instrument.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(result.instrument.color)
                        .frame(width: 36, height: 36)
                        .background(result.instrument.color.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

                    Spacer()
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xxxSmall) {
                    Text(result.instrument.rawValue)
                        .font(Theme.Typography.headline)

                    Text("\(result.issues.count) issue\(result.issues.count == 1 ? "" : "s") found")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }

                // Severity breakdown
                HStack(spacing: Theme.Spacing.small) {
                    if result.criticalCount > 0 {
                        severityCount(result.criticalCount, severity: .critical)
                    }
                    if result.warningCount > 0 {
                        severityCount(result.warningCount, severity: .warning)
                    }
                    if result.infoCount > 0 {
                        severityCount(result.infoCount, severity: .info)
                    }
                    if result.suggestionCount > 0 {
                        severityCount(result.suggestionCount, severity: .suggestion)
                    }
                }
            }
            .padding(Theme.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .shadow(
                color: Theme.Shadow.small.color,
                radius: Theme.Shadow.small.radius,
                x: Theme.Shadow.small.x,
                y: Theme.Shadow.small.y
            )
        }
        .buttonStyle(.plain)
    }

    private func severityCount(_ count: Int, severity: Severity) -> some View {
        HStack(spacing: 2) {
            Circle()
                .fill(Theme.Colors.severityColor(for: severity))
                .frame(width: 6, height: 6)
            Text("\(count)")
                .font(Theme.Typography.caption2)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }

    // MARK: - Issues Summary

    private var issuesSummarySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text("Issue Distribution")
                .font(Theme.Typography.title3)

            HStack(spacing: Theme.Spacing.medium) {
                issueSeverityBar
                    .frame(maxWidth: .infinity)
                    .cardStyle()

                analysisMetrics
                    .frame(maxWidth: .infinity)
                    .cardStyle()
            }
        }
    }

    private var issueSeverityBar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text("By Severity")
                .font(Theme.Typography.headline)

            ForEach(Severity.allCases, id: \.rawValue) { severity in
                let count = report.allIssues.filter { $0.severity == severity }.count
                HStack {
                    Image(systemName: severity.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.severityColor(for: severity))
                        .frame(width: 20)

                    Text(severity.rawValue)
                        .font(Theme.Typography.callout)
                        .frame(width: 70, alignment: .leading)

                    GeometryReader { geometry in
                        let maxCount = max(1, report.allIssues.count)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.Colors.severityColor(for: severity).opacity(0.6))
                            .frame(width: geometry.size.width * CGFloat(count) / CGFloat(maxCount))
                    }
                    .frame(height: 12)

                    Text("\(count)")
                        .font(Theme.Typography.callout)
                        .fontWeight(.medium)
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
    }

    private var analysisMetrics: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text("Analysis Metrics")
                .font(Theme.Typography.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Theme.Spacing.medium) {
                metricCell("Total Issues", value: "\(report.totalIssues)")
                metricCell("Instruments", value: "\(report.results.count)")
                metricCell("Analysis Time", value: String(format: "%.2fs", report.totalAnalysisTime))
                metricCell("Version", value: report.appVersion)
            }
        }
    }

    private func metricCell(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.Typography.title3)
                .fontWeight(.semibold)
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Top Issues

    private var topIssuesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack {
                Text("Top Issues")
                    .font(Theme.Typography.title3)
                Spacer()
                Text("Showing highest severity")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }

            let topIssues = Array(report.allIssues.prefix(5))

            if topIssues.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("No issues found. Your app looks great!")
                        .font(Theme.Typography.body)
                }
                .cardStyle()
            } else {
                VStack(spacing: Theme.Spacing.small) {
                    ForEach(topIssues) { issue in
                        IssueRowView(issue: issue)
                    }
                }
            }
        }
    }

}

// MARK: - Issue Row View (reusable)

struct IssueRowView: View {
    let issue: DiagnosticIssue
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Theme.Spacing.medium) {
                    Image(systemName: issue.severity.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.severityColor(for: issue.severity))
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.title)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.primaryText)

                        HStack(spacing: Theme.Spacing.small) {
                            Text(issue.instrument.rawValue)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(issue.instrument.color)

                            Text(issue.category)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.tertiaryText)

                            Text("Confidence: \(issue.confidence.confidenceLabel)")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.tertiaryText)
                        }
                    }

                    Spacer()

                    Text(issue.severity.rawValue)
                        .severityBadge(severity: issue.severity)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Colors.tertiaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(Theme.Spacing.medium)
            }
            .buttonStyle(.plain)

            // Expanded Detail
            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                    Divider()

                    Text(issue.description)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    if !issue.impact.isEmpty {
                        detailSection("Impact", text: issue.impact, icon: "bolt.fill", color: .orange)
                    }

                    detailSection("Recommendation", text: issue.recommendation, icon: "lightbulb.fill", color: .yellow)

                    if !issue.relatedSymbols.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxSmall) {
                            Text("Related Symbols")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.tertiaryText)
                                .textCase(.uppercase)

                            ForEach(issue.relatedSymbols.prefix(5), id: \.self) { symbol in
                                Text(symbol)
                                    .font(Theme.Typography.monospaced)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }

                    if !issue.details.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxSmall) {
                            Text("Details")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.tertiaryText)
                                .textCase(.uppercase)

                            ForEach(issue.details) { detail in
                                HStack {
                                    Text(detail.key)
                                        .font(Theme.Typography.callout)
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                    Spacer()
                                    Text(detail.value)
                                        .font(Theme.Typography.callout)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                    }
                }
                .padding([.horizontal, .bottom], Theme.Spacing.medium)
            }
        }
        .background(Theme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .shadow(
            color: Theme.Shadow.small.color,
            radius: Theme.Shadow.small.radius,
            x: Theme.Shadow.small.x,
            y: Theme.Shadow.small.y
        )
    }

    private func detailSection(_ title: String, text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.small) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
                    .textCase(.uppercase)

                Text(text)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
    }
}
