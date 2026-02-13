import SwiftUI
import UniformTypeIdentifiers

/// Welcome screen with drag-and-drop zone for loading iOS app bundles.
struct WelcomeView: View {
    @ObservedObject var engine: AnalysisEngine
    @State private var isDragTargeted = false
    @State private var showFileImporter = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.top, Theme.Spacing.xxxLarge)

            Spacer()

            // Drop Zone
            dropZone
                .padding(.horizontal, Theme.Spacing.xxxLarge)

            Spacer()

            // Instruments Preview
            instrumentsPreview
                .padding(.horizontal, Theme.Spacing.xxxLarge)
                .padding(.bottom, Theme.Spacing.xxxLarge)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [
                UTType(filenameExtension: "ipa") ?? .data,
                UTType(filenameExtension: "app") ?? .folder
            ],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.medium) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "stethoscope")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Text("AI Instruments")
                .font(Theme.Typography.largeTitle)

            Text("AI-driven static analysis for iOS applications")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: Theme.Spacing.large) {
            Image(systemName: isDragTargeted ? "arrow.down.circle.fill" : "square.and.arrow.down")
                .font(.system(size: 40))
                .foregroundStyle(isDragTargeted ? .blue : Theme.Colors.secondaryText)
                .symbolEffect(.bounce, value: isDragTargeted)

            VStack(spacing: Theme.Spacing.xSmall) {
                Text("Drop your iOS app here")
                    .font(Theme.Typography.title3)

                Text("Supports .ipa files and .app bundles")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }

            Text("or")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)

            Button("Browse Files") {
                showFileImporter = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: 500, minHeight: 220)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(
                    isDragTargeted ? Color.blue : Theme.Colors.separator,
                    style: StrokeStyle(lineWidth: 2, dash: isDragTargeted ? [] : [8, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                        .fill(isDragTargeted ? Color.blue.opacity(0.05) : Color.clear)
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers: providers)
        }
        .animation(.easeInOut(duration: 0.2), value: isDragTargeted)
    }

    // MARK: - Instruments Preview

    private var instrumentsPreview: some View {
        VStack(spacing: Theme.Spacing.medium) {
            Text("Analysis Instruments")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)
                .textCase(.uppercase)
                .tracking(1.2)

            HStack(spacing: Theme.Spacing.large) {
                ForEach(InstrumentType.allCases) { instrument in
                    instrumentCard(instrument)
                }
            }
        }
    }

    private func instrumentCard(_ instrument: InstrumentType) -> some View {
        VStack(spacing: Theme.Spacing.small) {
            Image(systemName: instrument.icon)
                .font(.system(size: 24))
                .foregroundStyle(instrument.color)
                .frame(width: 44, height: 44)
                .background(instrument.color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

            VStack(spacing: 2) {
                Text(instrument.rawValue)
                    .font(Theme.Typography.headline)
                    .lineLimit(1)

                Text(instrument.subtitle)
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.Colors.tertiaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.medium)
        .background(Theme.Colors.cardBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
    }

    // MARK: - Drop Handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
            guard let urlData = data as? Data,
                  let urlString = String(data: urlData, encoding: .utf8),
                  let url = URL(string: urlString) else { return }

            if url.isSupportedForAnalysis {
                Task { @MainActor in
                    await engine.analyze(url: url)
                }
            }
        }

        return true
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            if url.startAccessingSecurityScopedResource() {
                Task {
                    await engine.analyze(url: url)
                    url.stopAccessingSecurityScopedResource()
                }
            }
        case .failure:
            break
        }
    }
}
