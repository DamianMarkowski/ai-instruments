import Foundation

/// Provides common binary analysis utilities used by all instrument analyzers.
final class BinaryAnalyzer {

    let machOInfo: MachOInfo

    init(machOInfo: MachOInfo) {
        self.machOInfo = machOInfo
    }

    // MARK: - Symbol Pattern Matching

    /// Find symbols matching a pattern (case-insensitive).
    func findSymbols(matching pattern: String, caseSensitive: Bool = false) -> [SymbolInfo] {
        if caseSensitive {
            return machOInfo.symbols.filter { $0.name.contains(pattern) }
        }
        let lowered = pattern.lowercased()
        return machOInfo.symbols.filter { $0.name.lowercased().contains(lowered) }
    }

    /// Find symbols matching any of the given patterns.
    func findSymbols(matchingAny patterns: [String], caseSensitive: Bool = false) -> [SymbolInfo] {
        let loweredPatterns = caseSensitive ? patterns : patterns.map { $0.lowercased() }
        return machOInfo.symbols.filter { symbol in
            let name = caseSensitive ? symbol.name : symbol.name.lowercased()
            return loweredPatterns.contains { name.contains($0) }
        }
    }

    /// Count symbols matching a pattern.
    func countSymbols(matching pattern: String, caseSensitive: Bool = false) -> Int {
        findSymbols(matching: pattern, caseSensitive: caseSensitive).count
    }

    // MARK: - String Pattern Analysis

    /// Find extracted strings matching a pattern.
    func findStrings(matching pattern: String, caseSensitive: Bool = false) -> [String] {
        if caseSensitive {
            return machOInfo.extractedStrings.filter { $0.contains(pattern) }
        }
        let lowered = pattern.lowercased()
        return machOInfo.extractedStrings.filter { $0.lowercased().contains(lowered) }
    }

    // MARK: - Class Analysis

    /// Check if a class exists in the binary.
    func hasClass(_ className: String) -> Bool {
        machOInfo.objcClasses.contains(className)
    }

    /// Find classes matching a pattern.
    func findClasses(matching pattern: String) -> [String] {
        let lowered = pattern.lowercased()
        return machOInfo.objcClasses.filter { $0.lowercased().contains(lowered) }
    }

    /// Find classes that inherit from UIViewController-like classes.
    func findViewControllerClasses() -> [String] {
        machOInfo.objcClasses.filter { className in
            className.hasSuffix("ViewController") ||
            className.hasSuffix("Controller") ||
            className.hasSuffix("VC")
        }
    }

    // MARK: - Framework Analysis

    /// Check if a specific framework is linked.
    func isFrameworkLinked(_ framework: String) -> Bool {
        machOInfo.linkedLibraries.contains { $0.contains(framework) }
    }

    /// Get the list of system frameworks used.
    func systemFrameworks() -> [String] {
        machOInfo.linkedLibraries.filter {
            $0.contains("/System/") || $0.contains("/usr/lib/")
        }
    }

    /// Get the list of embedded/third-party frameworks.
    func embeddedFrameworks() -> [String] {
        machOInfo.linkedLibraries.filter {
            $0.contains("@rpath") || $0.contains("@executable_path") ||
            (!$0.contains("/System/") && !$0.contains("/usr/lib/"))
        }
    }

    // MARK: - Section Analysis

    /// Get size of a specific section.
    func sectionSize(segment: String, section: String) -> UInt64 {
        machOInfo.sections
            .first { $0.segmentName == segment && $0.name == section }?
            .size ?? 0
    }

    /// Check if a section exists.
    func hasSection(segment: String, section: String) -> Bool {
        machOInfo.sections.contains { $0.segmentName == segment && $0.name == section }
    }

    // MARK: - Swift-Specific Analysis

    /// Check if the binary uses Swift.
    var usesSwift: Bool {
        isFrameworkLinked("libswiftCore") ||
        machOInfo.sections.contains { $0.name.hasPrefix("__swift") } ||
        machOInfo.symbols.contains { $0.name.contains("$s") || $0.name.contains("$S") }
    }

    /// Check if the binary uses Swift Concurrency.
    var usesSwiftConcurrency: Bool {
        isFrameworkLinked("libswift_Concurrency") ||
        machOInfo.symbols.contains { $0.name.contains("Concurrency") || $0.name.contains("async") || $0.name.contains("Task") }
    }

    /// Count of Swift types found in the binary.
    var swiftTypeCount: Int {
        machOInfo.swiftTypeDescriptors.count
    }

    /// Count of ObjC classes found in the binary.
    var objcClassCount: Int {
        machOInfo.objcClasses.count
    }

    // MARK: - Selector Analysis

    /// Find selectors matching a pattern.
    func findSelectors(matching pattern: String) -> [String] {
        let lowered = pattern.lowercased()
        return machOInfo.objcSelectors.filter { $0.lowercased().contains(lowered) }
    }

    /// Check if a selector exists.
    func hasSelector(_ selector: String) -> Bool {
        machOInfo.objcSelectors.contains(selector)
    }

    // MARK: - Statistical Helpers

    /// Calculate a confidence score based on evidence count and threshold.
    func confidenceScore(evidenceCount: Int, lowThreshold: Int = 1, highThreshold: Int = 10) -> Double {
        if evidenceCount <= 0 { return 0 }
        if evidenceCount >= highThreshold { return 1.0 }
        let range = Double(highThreshold - lowThreshold)
        let progress = Double(evidenceCount - lowThreshold) / range
        return min(1.0, max(0.3, progress))
    }
}
