import SwiftUI

/// Sidebar navigation showing app info, instruments, and their scores.
struct SidebarView: View {
    @ObservedObject var engine: AnalysisEngine
    @Binding var selectedItem: ContentView.NavigationItem?
    var onNewAnalysis: () -> Void

    var body: some View {
        List(selection: $selectedItem) {
            // App Info Section
            if let app = engine.loadedApp {
                Section {
                    appInfoRow(app)
                }
            }

            // Dashboard
            Section("Overview") {
                NavigationLink(value: ContentView.NavigationItem.dashboard) {
                    Label {
                        HStack {
                            Text("Dashboard")
                            Spacer()
                            if let report = engine.report {
                                scoreTag(report.overallScore)
                            }
                        }
                    } icon: {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Instruments
            Section("Instruments") {
                ForEach(InstrumentType.allCases) { instrument in
                    NavigationLink(value: ContentView.NavigationItem.instrument(instrument)) {
                        instrumentRow(instrument)
                    }
                }
            }

            // Binary Info
            if let info = engine.machOInfo {
                Section("Binary Info") {
                    binaryInfoSection(info)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Diagnostics")
        .safeAreaInset(edge: .bottom) {
            Button {
                onNewAnalysis()
            } label: {
                Label("New Analysis", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .font(Theme.Typography.headline)
            .foregroundStyle(.blue)
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.small)
            .background(.bar)
        }
    }

    // MARK: - App Info Row

    private func appInfoRow(_ app: AppBundle) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxSmall) {
            HStack(spacing: Theme.Spacing.small) {
                Image(systemName: "app.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(Theme.Typography.headline)
                        .lineLimit(1)

                    Text(app.bundleIdentifier)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                        .lineLimit(1)
                }
            }

            HStack(spacing: Theme.Spacing.small) {
                infoChip("v\(app.version)")
                infoChip("iOS \(app.minimumOSVersion)")
            }
        }
        .padding(.vertical, Theme.Spacing.xxSmall)
    }

    private func infoChip(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.Colors.separator.opacity(0.3))
            .clipShape(Capsule())
    }

    // MARK: - Instrument Row

    private func instrumentRow(_ instrument: InstrumentType) -> some View {
        Label {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(instrument.rawValue)
                        .font(Theme.Typography.headline)

                    if let result = engine.result(for: instrument) {
                        Text("\(result.issues.count) issue\(result.issues.count == 1 ? "" : "s")")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.tertiaryText)
                    }
                }

                Spacer()

                if let result = engine.result(for: instrument) {
                    scoreTag(result.score)
                }
            }
        } icon: {
            Image(systemName: instrument.icon)
                .foregroundStyle(instrument.color)
        }
        .padding(.vertical, Theme.Spacing.xxxSmall)
    }

    // MARK: - Binary Info

    private func binaryInfoSection(_ info: MachOInfo) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxSmall) {
            binaryInfoRow("Architecture", value: info.architecture)
            binaryInfoRow("Type", value: info.fileType)
            binaryInfoRow("Symbols", value: info.symbols.count.formattedCount)
            binaryInfoRow("Classes", value: "\(info.objcClasses.count)")
            binaryInfoRow("Libraries", value: "\(info.linkedLibraries.count)")

            if info.isFatBinary {
                HStack(spacing: Theme.Spacing.xxSmall) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9))
                    Text("Universal Binary")
                        .font(Theme.Typography.caption2)
                }
                .foregroundStyle(Theme.Colors.tertiaryText)
            }
        }
    }

    private func binaryInfoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
            Spacer()
            Text(value)
                .font(Theme.Typography.caption)
                .fontWeight(.medium)
        }
    }

    // MARK: - Score Tag

    private func scoreTag(_ score: Int) -> some View {
        Text("\(score)")
            .font(Theme.Typography.caption)
            .fontWeight(.semibold)
            .foregroundStyle(Theme.Colors.scoreColor(for: score))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Theme.Colors.scoreColor(for: score).opacity(0.12))
            .clipShape(Capsule())
    }
}
