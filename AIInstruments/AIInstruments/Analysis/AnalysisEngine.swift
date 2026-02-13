import Foundation
import Combine

/// Orchestrates all diagnostic analyses on an iOS app bundle.
/// Parses the Mach-O binary, runs each instrument analyzer, and produces an aggregated report.
@MainActor
final class AnalysisEngine: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case parsing
        case analyzing(instrument: InstrumentType)
        case complete
        case error(message: String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.loading, .loading), (.parsing, .parsing), (.complete, .complete):
                return true
            case (.analyzing(let a), .analyzing(let b)):
                return a == b
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @Published var state: State = .idle
    @Published var progress: Double = 0
    @Published var progressMessage: String = ""
    @Published var report: AnalysisReport?
    @Published var loadedApp: AppBundle?
    @Published var machOInfo: MachOInfo?

    var hasReport: Bool { report != nil }

    // MARK: - Analysis Pipeline

    func analyze(url: URL) async {
        state = .loading
        progress = 0
        progressMessage = "Loading app bundle..."
        report = nil
        loadedApp = nil
        machOInfo = nil

        do {
            // Step 1: Load the app bundle
            let appBundle = try await AppBundle.load(from: url)
            loadedApp = appBundle
            progress = 0.15
            progressMessage = "App bundle loaded: \(appBundle.name)"

            // Step 2: Parse the Mach-O binary
            state = .parsing
            progress = 0.20
            progressMessage = "Parsing Mach-O binary (\(formatBytes(appBundle.executableData.count)))..."

            let parsedInfo = await parseMachO(data: appBundle.executableData)
            machOInfo = parsedInfo

            guard parsedInfo.isValid else {
                if parsedInfo.isEncrypted {
                    state = .error(message: "The binary is encrypted (App Store encryption). Please provide a decrypted binary or a development build for analysis.")
                } else {
                    state = .error(message: "Failed to parse the Mach-O binary. The file may not be a valid iOS executable.")
                }
                return
            }

            progress = 0.35
            progressMessage = "Binary parsed: \(parsedInfo.architecture), \(parsedInfo.symbols.count) symbols"

            // Step 3: Run analyzers
            let binaryAnalyzer = BinaryAnalyzer(machOInfo: parsedInfo)
            var results: [AnalysisResult] = []

            // Leaks Analysis
            state = .analyzing(instrument: .leaks)
            progress = 0.45
            progressMessage = "Analyzing memory leak patterns..."

            let leaksResult = await runLeaksAnalysis(binaryAnalyzer: binaryAnalyzer)
            results.append(leaksResult)
            progress = 0.60

            // Concurrency Analysis
            state = .analyzing(instrument: .concurrency)
            progressMessage = "Analyzing Swift concurrency patterns..."

            let concurrencyResult = await runConcurrencyAnalysis(binaryAnalyzer: binaryAnalyzer)
            results.append(concurrencyResult)
            progress = 0.75

            // Allocations Analysis
            state = .analyzing(instrument: .allocations)
            progressMessage = "Analyzing memory allocation patterns..."

            let allocationsResult = await runAllocationsAnalysis(
                binaryAnalyzer: binaryAnalyzer,
                binarySize: appBundle.executableData.count
            )
            results.append(allocationsResult)
            progress = 0.90

            // Step 4: Generate report
            progressMessage = "Generating report..."

            let analysisReport = AnalysisReport(
                appName: appBundle.name,
                bundleIdentifier: appBundle.bundleIdentifier,
                appVersion: appBundle.version,
                results: results
            )

            report = analysisReport
            progress = 1.0
            progressMessage = "Analysis complete"
            state = .complete

        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    func reset() {
        state = .idle
        progress = 0
        progressMessage = ""
        report = nil
        loadedApp = nil
        machOInfo = nil
    }

    // MARK: - Analysis Runners

    private func parseMachO(data: Data) async -> MachOInfo {
        await Task.detached(priority: .userInitiated) {
            MachOParser(data: data).parse()
        }.value
    }

    private func runLeaksAnalysis(binaryAnalyzer: BinaryAnalyzer) async -> AnalysisResult {
        await Task.detached(priority: .userInitiated) {
            LeaksAnalyzer(binaryAnalyzer: binaryAnalyzer).analyze()
        }.value
    }

    private func runConcurrencyAnalysis(binaryAnalyzer: BinaryAnalyzer) async -> AnalysisResult {
        await Task.detached(priority: .userInitiated) {
            ConcurrencyAnalyzer(binaryAnalyzer: binaryAnalyzer).analyze()
        }.value
    }

    private func runAllocationsAnalysis(binaryAnalyzer: BinaryAnalyzer, binarySize: Int) async -> AnalysisResult {
        await Task.detached(priority: .userInitiated) {
            AllocationsAnalyzer(binaryAnalyzer: binaryAnalyzer, binarySize: binarySize).analyze()
        }.value
    }

    // MARK: - Result Accessors

    func result(for instrument: InstrumentType) -> AnalysisResult? {
        report?.results.first { $0.instrument == instrument }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 {
            return String(format: "%.1f MB", mb)
        }
        let kb = Double(bytes) / 1024
        return String(format: "%.0f KB", kb)
    }
}
