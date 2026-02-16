import SwiftUI
import UniformTypeIdentifiers

/// Main content view with navigation split view layout.
struct ContentView: View {
    @StateObject private var engine = AnalysisEngine()
    @State private var selectedInstrument: InstrumentType?
    @State private var showDashboard = true

    enum NavigationItem: Hashable {
        case dashboard
        case instrument(InstrumentType)
    }

    @State private var selectedItem: NavigationItem? = .dashboard

    var body: some View {
        Group {
            if engine.hasReport {
                analysisView
            } else {
                welcomeOrProgressView
            }
        }
        .frame(minWidth: 1000, minHeight: 650)
        .onReceive(NotificationCenter.default.publisher(for: .newAnalysisRequested)) { _ in
            startNewAnalysis()
        }
    }

    private func startNewAnalysis() {
        selectedItem = .dashboard
        engine.reset()
    }

    // MARK: - Welcome / Progress View

    @ViewBuilder
    private var welcomeOrProgressView: some View {
        switch engine.state {
        case .idle:
            WelcomeView(engine: engine)

        case .loading, .parsing, .analyzing:
            AnalysisProgressView(engine: engine)

        case .error(let message):
            ErrorView(message: message) {
                engine.reset()
            }

        case .complete:
            // Should transition to analysisView via hasReport
            ProgressView()
        }
    }

    // MARK: - Analysis Results View

    private var analysisView: some View {
        NavigationSplitView {
            SidebarView(
                engine: engine,
                selectedItem: $selectedItem,
                onNewAnalysis: startNewAnalysis
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    startNewAnalysis()
                } label: {
                    Label("New Analysis", systemImage: "arrow.counterclockwise")
                }

                if let report = engine.report {
                    Button {
                        exportReport(report)
                    } label: {
                        Label("Export Report", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedItem {
        case .dashboard, .none:
            if let report = engine.report {
                DashboardView(report: report, onSelectInstrument: { instrument in
                    selectedItem = .instrument(instrument)
                })
            }

        case .instrument(let instrument):
            if let result = engine.result(for: instrument) {
                InstrumentDetailView(result: result, machOInfo: engine.machOInfo)
            } else {
                Text("No results available for \(instrument.rawValue)")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
    }

    // MARK: - Export

    private func exportReport(_ report: AnalysisReport) {
        let panel = NSSavePanel()
        panel.title = "Export Analysis Report"
        panel.nameFieldStringValue = "\(report.appName)_analysis_report.txt"
        panel.allowedContentTypes = [.plainText]

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let text = generateReportText(report)
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func generateReportText(_ report: AnalysisReport) -> String {
        var text = """
        ═══════════════════════════════════════════════
        AI Instruments Report
        ═══════════════════════════════════════════════

        App: \(report.appName)
        Bundle ID: \(report.bundleIdentifier)
        Version: \(report.appVersion)
        Analysis Date: \(report.analysisDate.formattedTimestamp)
        Overall Score: \(report.overallScore)/100 (\(report.overallGrade))

        Total Issues: \(report.totalIssues)
        Critical: \(report.totalCritical)
        Warnings: \(report.totalWarnings)

        """

        for result in report.results {
            text += """

            ───────────────────────────────────────────
            \(result.instrument.rawValue) — Score: \(result.score)/100 (\(result.scoreGrade))
            ───────────────────────────────────────────

            \(result.summary)

            """

            for issue in result.issues {
                text += """

                [\(issue.severity.rawValue.uppercased())] \(issue.title)
                \(issue.description)

                Impact: \(issue.impact)
                Recommendation: \(issue.recommendation)
                Confidence: \(issue.confidence.confidenceLabel) (\(String(format: "%.0f%%", issue.confidence * 100)))

                """

                if !issue.relatedSymbols.isEmpty {
                    text += "  Related Symbols: \(issue.relatedSymbols.joined(separator: ", "))\n"
                }
            }
        }

        return text
    }
}

// MARK: - Analysis Progress View

struct AnalysisProgressView: View {
    @ObservedObject var engine: AnalysisEngine

    var body: some View {
        VStack(spacing: Theme.Spacing.xxLarge) {
            Spacer()

            // Animated icon
            ZStack {
                Circle()
                    .fill(Theme.Colors.gradientPrimary)
                    .frame(width: 100, height: 100)
                    .opacity(0.1)

                Circle()
                    .fill(Theme.Colors.gradientPrimary)
                    .frame(width: 70, height: 70)
                    .opacity(0.2)

                Image(systemName: instrumentIcon)
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse, options: .repeating)
            }

            VStack(spacing: Theme.Spacing.small) {
                Text("Analyzing Application")
                    .font(Theme.Typography.title)

                Text(engine.progressMessage)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

            ProgressView(value: engine.progress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 400)

            Text("\(Int(engine.progress * 100))%")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)

            Spacer()
        }
        .padding(Theme.Spacing.xxxLarge)
    }

    private var instrumentIcon: String {
        switch engine.state {
        case .analyzing(let instrument):
            return instrument.icon
        case .parsing:
            return "doc.text.magnifyingglass"
        case .loading:
            return "arrow.down.doc"
        default:
            return "gearshape.2"
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xLarge) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            VStack(spacing: Theme.Spacing.small) {
                Text("Analysis Error")
                    .font(Theme.Typography.title)

                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            Button("Try Again") {
                onRetry()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding(Theme.Spacing.xxxLarge)
    }
}
