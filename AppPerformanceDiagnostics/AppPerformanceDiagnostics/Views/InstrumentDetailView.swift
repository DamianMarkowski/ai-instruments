import SwiftUI

/// Detail view for a single instrument's analysis results.
struct InstrumentDetailView: View {
    let result: AnalysisResult
    let machOInfo: MachOInfo?

    @State private var selectedSeverityFilter: Severity?
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .severity

    enum SortOrder: String, CaseIterable {
        case severity = "Severity"
        case confidence = "Confidence"
        case category = "Category"
    }

    private var filteredIssues: [DiagnosticIssue] {
        var issues = result.issues

        // Filter by severity
        if let severity = selectedSeverityFilter {
            issues = issues.filter { $0.severity == severity }
        }

        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            issues = issues.filter {
                $0.title.lowercased().contains(query) ||
                $0.description.lowercased().contains(query) ||
                $0.category.lowercased().contains(query)
            }
        }

        // Sort
        switch sortOrder {
        case .severity:
            issues.sort { $0.severity < $1.severity }
        case .confidence:
            issues.sort { $0.confidence > $1.confidence }
        case .category:
            issues.sort { $0.category < $1.category }
        }

        return issues
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xxLarge) {
                // Instrument Header
                instrumentHeader

                // Filters
                filterBar

                // Issues List
                issuesList
            }
            .padding(Theme.Spacing.xxLarge)
        }
        .background(Theme.Colors.background)
    }

    // MARK: - Instrument Header

    private var instrumentHeader: some View {
        HStack(spacing: Theme.Spacing.xLarge) {
            // Score gauge
            ZStack {
                Circle()
                    .stroke(Theme.Colors.separator.opacity(0.3), lineWidth: 6)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: CGFloat(result.score) / 100)
                    .stroke(
                        result.instrument.color,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(result.score)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Colors.scoreColor(for: result.score))

                    Text(result.scoreGrade)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                HStack {
                    Image(systemName: result.instrument.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(result.instrument.color)

                    Text(result.instrument.rawValue)
                        .font(Theme.Typography.title)
                }

                Text(result.summary)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(3)

                // Severity summary
                HStack(spacing: Theme.Spacing.medium) {
                    severityPill(.critical, count: result.criticalCount)
                    severityPill(.warning, count: result.warningCount)
                    severityPill(.info, count: result.infoCount)
                    severityPill(.suggestion, count: result.suggestionCount)

                    Spacer()

                    Text(String(format: "Analysis time: %.2fs", result.analysisTimeSeconds))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                }
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func severityPill(_ severity: Severity, count: Int) -> some View {
        if count > 0 {
            HStack(spacing: 4) {
                Image(systemName: severity.icon)
                    .font(.system(size: 10))
                Text("\(count)")
                    .font(Theme.Typography.caption)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(Theme.Colors.severityColor(for: severity))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.Colors.severityColor(for: severity).opacity(0.1))
            .clipShape(Capsule())
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: Theme.Spacing.medium) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Colors.tertiaryText)
                TextField("Search issues...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.body)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.Colors.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.small)
            .background(Theme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

            // Severity Filter
            Picker("Severity", selection: $selectedSeverityFilter) {
                Text("All Severities")
                    .tag(Optional<Severity>.none)
                ForEach(Severity.allCases, id: \.self) { severity in
                    Label(severity.rawValue, systemImage: severity.icon)
                        .tag(Optional(severity))
                }
            }
            .frame(width: 160)

            // Sort Order
            Picker("Sort", selection: $sortOrder) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .frame(width: 130)

            Spacer()

            Text("\(filteredIssues.count) issue\(filteredIssues.count == 1 ? "" : "s")")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.tertiaryText)
        }
    }

    // MARK: - Issues List

    private var issuesList: some View {
        VStack(spacing: Theme.Spacing.small) {
            if filteredIssues.isEmpty {
                emptyStateView
            } else {
                ForEach(filteredIssues) { issue in
                    IssueRowView(issue: issue)
                }
            }

            // Metadata
            if !result.metadata.isEmpty {
                metadataSection
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: Theme.Spacing.medium) {
            Image(systemName: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(Theme.Colors.tertiaryText)

            if searchText.isEmpty && selectedSeverityFilter == nil {
                Text("No issues found")
                    .font(Theme.Typography.title3)
                Text("This instrument did not detect any issues. Great job!")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.secondaryText)
            } else {
                Text("No matching issues")
                    .font(Theme.Typography.title3)
                Text("Try adjusting your filters")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xxxLarge)
        .cardStyle()
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("Analysis Metadata")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)
                .textCase(.uppercase)
                .tracking(1)

            HStack(spacing: Theme.Spacing.large) {
                ForEach(result.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(value)
                            .font(Theme.Typography.headline)
                        Text(key)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.tertiaryText)
                    }
                }
            }
        }
        .cardStyle()
    }
}
