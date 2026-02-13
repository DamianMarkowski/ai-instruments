import Foundation

/// Analyzes iOS app binaries for memory allocation patterns and optimization opportunities.
///
/// Detection categories:
/// - Large allocation patterns
/// - Image and media loading
/// - Data buffer management
/// - Autorelease pool optimization
/// - Collection growth patterns
/// - Cache utilization
/// - String allocation patterns
/// - Memory-mapped file usage
final class AllocationsAnalyzer {

    private let analyzer: BinaryAnalyzer
    private let binarySize: Int

    init(binaryAnalyzer: BinaryAnalyzer, binarySize: Int) {
        self.analyzer = binaryAnalyzer
        self.binarySize = binarySize
    }

    func analyze() -> AnalysisResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        var issues: [DiagnosticIssue] = []

        issues.append(contentsOf: analyzeLargeAllocations())
        issues.append(contentsOf: analyzeImageLoading())
        issues.append(contentsOf: analyzeDataBuffers())
        issues.append(contentsOf: analyzeAutoreleasePools())
        issues.append(contentsOf: analyzeCollectionGrowth())
        issues.append(contentsOf: analyzeCacheUsage())
        issues.append(contentsOf: analyzeStringAllocations())
        issues.append(contentsOf: analyzeMemoryMappedFiles())
        issues.append(contentsOf: analyzeBinaryFootprint())
        issues.append(contentsOf: analyzeThirdPartyFrameworks())

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let score = calculateScore(issues: issues)

        return AnalysisResult(
            instrument: .allocations,
            issues: issues.sorted { $0.severity < $1.severity },
            summary: generateSummary(issues: issues, score: score),
            score: score,
            analysisTimeSeconds: elapsed,
            metadata: [
                "binarySizeMB": String(format: "%.1f", Double(binarySize) / 1_048_576),
                "textSegmentSizeMB": String(format: "%.1f", Double(analyzer.machOInfo.totalTextSize) / 1_048_576),
                "dataSegmentSizeMB": String(format: "%.1f", Double(analyzer.machOInfo.totalDataSize) / 1_048_576),
                "linkedFrameworks": "\(analyzer.machOInfo.linkedLibraries.count)"
            ]
        )
    }

    // MARK: - Large Allocation Analysis

    private func analyzeLargeAllocations() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let mallocSymbols = analyzer.findSymbols(matchingAny: [
            "malloc", "calloc", "realloc", "valloc", "malloc_zone_malloc"
        ])

        let allocSymbols = analyzer.findSymbols(matchingAny: [
            "swift_allocObject", "swift_slowAlloc", "objc_msgSend_alloc",
            "class_createInstance", "_objc_rootAllocWithZone"
        ])

        // Check for manual memory allocation patterns
        if mallocSymbols.count > 10 {
            issues.append(DiagnosticIssue(
                title: "Significant Manual Memory Allocation",
                description: "Found \(mallocSymbols.count) manual memory allocation call(s) (malloc/calloc/realloc). Manual allocations bypass ARC and require explicit deallocation.",
                severity: mallocSymbols.count > 30 ? .warning : .info,
                instrument: .allocations,
                category: "Manual Allocations",
                recommendation: "Replace manual malloc/calloc with Swift arrays or Data types where possible. For performance-critical paths, consider using `UnsafeMutableBufferPointer.allocate(capacity:)` for safer manual allocation with guaranteed deallocation via `deallocate()`.",
                impact: "Manual allocations that aren't properly freed cause memory leaks. They also make memory usage harder to profile and debug.",
                confidence: analyzer.confidenceScore(evidenceCount: mallocSymbols.count, lowThreshold: 5, highThreshold: 30),
                relatedSymbols: Array(mallocSymbols.prefix(8).map(\.name)),
                details: [
                    .init(key: "malloc/calloc/realloc Calls", value: "\(mallocSymbols.count)"),
                    .init(key: "Swift/ObjC Allocations", value: "\(allocSymbols.count)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Image Loading Analysis

    private func analyzeImageLoading() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let imageLoadSymbols = analyzer.findSymbols(matchingAny: [
            "UIImage", "imageNamed", "imageWithContentsOfFile",
            "imageWithData", "CGImageSource", "ImageIO",
            "NSImage", "CIImage", "CGImage"
        ])

        let imageResizeSymbols = analyzer.findSymbols(matchingAny: [
            "drawInRect", "draw(in:", "resizableImage", "preparingThumbnail",
            "byPreparingThumbnail", "CGImageSourceCreateThumbnail",
            "UIGraphicsImageRenderer", "CGContext"
        ])

        let imageDownsampleSymbols = analyzer.findSymbols(matchingAny: [
            "kCGImageSourceThumbnailMaxPixelSize",
            "kCGImageSourceCreateThumbnailFromImageAlways",
            "preparingThumbnail"
        ])

        if imageLoadSymbols.count > 15 && imageDownsampleSymbols.count < 3 {
            issues.append(DiagnosticIssue(
                title: "Heavy Image Loading Without Downsampling",
                description: "Found \(imageLoadSymbols.count) image loading operations but limited downsampling (\(imageDownsampleSymbols.count) patterns). Large images decoded at full resolution consume significant memory.",
                severity: .warning,
                instrument: .allocations,
                category: "Image Loading",
                recommendation: "Use `UIImage.preparingThumbnail(of:)` (iOS 15+) or `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize` to downsample images to display size before decoding. A 12MP photo decoded at full resolution uses ~48MB of memory.",
                impact: "Full-resolution image decoding is one of the largest sources of memory spikes in iOS apps. Decoding images larger than the display size wastes memory proportional to the resolution difference.",
                confidence: analyzer.confidenceScore(evidenceCount: imageLoadSymbols.count, lowThreshold: 10, highThreshold: 30),
                relatedSymbols: Array(imageLoadSymbols.prefix(8).map(\.name)),
                details: [
                    .init(key: "Image Load Operations", value: "\(imageLoadSymbols.count)"),
                    .init(key: "Resize Operations", value: "\(imageResizeSymbols.count)"),
                    .init(key: "Downsampling Patterns", value: "\(imageDownsampleSymbols.count)")
                ]
            ))
        }

        // Check for image caching
        let imageCacheSymbols = analyzer.findSymbols(matchingAny: [
            "NSCache", "URLCache", "imageCache", "SDWebImage",
            "Kingfisher", "Nuke", "AlamofireImage"
        ])

        if imageLoadSymbols.count > 20 && imageCacheSymbols.count == 0 {
            issues.append(DiagnosticIssue(
                title: "No Image Caching Detected",
                description: "Found extensive image loading (\(imageLoadSymbols.count) patterns) but no apparent image caching mechanism. Repeatedly loading and decoding the same images wastes CPU and memory.",
                severity: .info,
                instrument: .allocations,
                category: "Image Loading",
                recommendation: "Implement an image cache using `NSCache` or a third-party library (SDWebImage, Kingfisher, Nuke). NSCache automatically evicts items under memory pressure.",
                impact: "Without caching, images are decoded from disk or network on every display, causing allocation spikes and CPU overhead.",
                confidence: 0.5,
                relatedSymbols: Array(imageLoadSymbols.prefix(5).map(\.name))
            ))
        }

        return issues
    }

    // MARK: - Data Buffer Analysis

    private func analyzeDataBuffers() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let dataCreationSymbols = analyzer.findSymbols(matchingAny: [
            "Data(contentsOf", "NSData", "dataWithContentsOfFile",
            "dataWithContentsOfURL", "Data(count:", "Data(capacity:"
        ])

        let jsonSymbols = analyzer.findSymbols(matchingAny: [
            "JSONDecoder", "JSONEncoder", "JSONSerialization",
            "jsonObject", "PropertyListSerialization"
        ])

        let networkDataSymbols = analyzer.findSymbols(matchingAny: [
            "URLSession", "dataTask", "downloadTask",
            "Alamofire", "AFNetworking"
        ])

        if dataCreationSymbols.count > 10 {
            issues.append(DiagnosticIssue(
                title: "Frequent Data Buffer Creation",
                description: "Found \(dataCreationSymbols.count) Data/NSData creation patterns. Frequent large data buffer allocations can cause memory pressure.",
                severity: dataCreationSymbols.count > 25 ? .warning : .info,
                instrument: .allocations,
                category: "Data Buffers",
                recommendation: "For large files, use memory-mapped data (`Data(contentsOf: url, options: .mappedIfSafe)`) instead of loading entirely into memory. Stream large JSON/XML payloads instead of loading the entire response into memory.",
                impact: "Loading entire files into memory creates allocation spikes proportional to file size. For large files, this can cause memory warnings or app termination.",
                confidence: 0.6,
                relatedSymbols: Array(dataCreationSymbols.prefix(5).map(\.name)),
                details: [
                    .init(key: "Data Creations", value: "\(dataCreationSymbols.count)"),
                    .init(key: "JSON Operations", value: "\(jsonSymbols.count)"),
                    .init(key: "Network Data", value: "\(networkDataSymbols.count)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Autorelease Pool Analysis

    private func analyzeAutoreleasePools() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let autoreleaseSymbols = analyzer.findSymbols(matchingAny: [
            "autoreleasepool", "objc_autoreleasePoolPush", "objc_autoreleasePoolPop",
            "NSAutoreleasePool"
        ])

        let loopPatterns = analyzer.findSymbols(matchingAny: [
            "forEach", "for_each", "map", "flatMap", "compactMap",
            "reduce", "filter", "enumerated"
        ])

        let objcBridging = analyzer.findSymbols(matchingAny: [
            "bridge", "_bridgeToObjectiveC", "NSString", "NSArray", "NSDictionary"
        ])

        // If there's significant ObjC bridging but few autorelease pools
        if objcBridging.count > 20 && autoreleaseSymbols.count < 3 {
            issues.append(DiagnosticIssue(
                title: "ObjC Bridging Without Autorelease Pool Management",
                description: "Found \(objcBridging.count) ObjC bridging operations but only \(autoreleaseSymbols.count) autorelease pool(s). ObjC-bridged objects may accumulate in the default autorelease pool.",
                severity: .info,
                instrument: .allocations,
                category: "Autorelease Pools",
                recommendation: "Wrap loops that perform ObjC bridging in `autoreleasepool { }` blocks. This is especially important for batch processing operations that create many temporary ObjC objects.",
                impact: "Without explicit autorelease pools, temporary ObjC objects created during bridging accumulate until the end of the run loop iteration, causing temporary memory spikes.",
                confidence: 0.5,
                relatedSymbols: Array(autoreleaseSymbols.prefix(3).map(\.name) + objcBridging.prefix(5).map(\.name)),
                details: [
                    .init(key: "Autorelease Pools", value: "\(autoreleaseSymbols.count)"),
                    .init(key: "ObjC Bridging Ops", value: "\(objcBridging.count)"),
                    .init(key: "Loop Patterns", value: "\(loopPatterns.count)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Collection Growth Analysis

    private func analyzeCollectionGrowth() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let arraySymbols = analyzer.findSymbols(matchingAny: [
            "Array", "ContiguousArray", "NSMutableArray", "append("
        ])

        let dictSymbols = analyzer.findSymbols(matchingAny: [
            "Dictionary", "NSMutableDictionary", "updateValue"
        ])

        let setSymbols = analyzer.findSymbols(matchingAny: [
            "Set.insert", "NSMutableSet", "NSMutableOrderedSet"
        ])

        let reserveSymbols = analyzer.findSymbols(matchingAny: [
            "reserveCapacity", "initWithCapacity"
        ])

        let totalCollectionOps = arraySymbols.count + dictSymbols.count + setSymbols.count

        if totalCollectionOps > 30 && reserveSymbols.count < 3 {
            issues.append(DiagnosticIssue(
                title: "Collection Growth Without Capacity Reservation",
                description: "Found \(totalCollectionOps) collection operation(s) but only \(reserveSymbols.count) capacity reservation(s). Collections without reserved capacity reallocate on growth, causing allocation churn.",
                severity: .suggestion,
                instrument: .allocations,
                category: "Collection Growth",
                recommendation: "Use `reserveCapacity(_:)` on arrays, dictionaries, and sets when the approximate size is known. This prevents repeated reallocation as the collection grows, reducing both allocation count and CPU overhead from copying.",
                impact: "Array growth triggers reallocation (typically 2x) and copying of all existing elements. For large arrays built incrementally, this can cause significant allocation churn.",
                confidence: 0.45,
                relatedSymbols: Array(reserveSymbols.prefix(3).map(\.name)),
                details: [
                    .init(key: "Array Operations", value: "\(arraySymbols.count)"),
                    .init(key: "Dictionary Operations", value: "\(dictSymbols.count)"),
                    .init(key: "Set Operations", value: "\(setSymbols.count)"),
                    .init(key: "Capacity Reservations", value: "\(reserveSymbols.count)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Cache Utilization Analysis

    private func analyzeCacheUsage() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let cacheSymbols = analyzer.findSymbols(matchingAny: [
            "NSCache", "URLCache", "cache", "Cache"
        ])

        let memoryWarningSymbols = analyzer.findSymbols(matchingAny: [
            "didReceiveMemoryWarning", "applicationDidReceiveMemoryWarning",
            "UIApplication.didReceiveMemoryWarningNotification"
        ])

        if cacheSymbols.count > 0 && memoryWarningSymbols.count == 0 {
            issues.append(DiagnosticIssue(
                title: "Cache Usage Without Memory Warning Handling",
                description: "Found \(cacheSymbols.count) cache usage(s) but no memory warning handler. While NSCache auto-evicts, custom caches need manual cleanup on memory warnings.",
                severity: .suggestion,
                instrument: .allocations,
                category: "Cache Management",
                recommendation: "If using custom caches (not NSCache), observe `UIApplication.didReceiveMemoryWarningNotification` and clear caches in response. NSCache handles this automatically but custom Dictionary-based caches do not.",
                impact: "Custom caches that don't respond to memory warnings can cause the app to be terminated by the system when memory is low.",
                confidence: 0.5,
                relatedSymbols: Array(cacheSymbols.prefix(5).map(\.name))
            ))
        }

        return issues
    }

    // MARK: - String Allocation Analysis

    private func analyzeStringAllocations() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let stringInterpolationSymbols = analyzer.findSymbols(matchingAny: [
            "appendInterpolation", "StringInterpolation",
            "string.init(describing:", "String(format:"
        ])

        let stringConcatSymbols = analyzer.findSymbols(matchingAny: [
            "append(contentsOf:", "joined(separator:", "components(separatedBy:"
        ])

        let totalStringOps = stringInterpolationSymbols.count + stringConcatSymbols.count

        if totalStringOps > 30 {
            issues.append(DiagnosticIssue(
                title: "Heavy String Processing",
                description: "Found \(totalStringOps) string creation/manipulation patterns. Extensive string operations can cause significant allocation overhead due to copy-on-write and bridging.",
                severity: .suggestion,
                instrument: .allocations,
                category: "String Allocations",
                recommendation: "For building strings incrementally, use a single `String` variable with `append` instead of concatenation with `+`. For formatting, prefer `String(format:)` over repeated interpolation in loops. Consider using `Substring` to avoid unnecessary copies.",
                impact: "String operations frequently allocate new buffers and copy data. In hot paths (tight loops, frequent updates), this creates allocation pressure that triggers more frequent garbage collection.",
                confidence: 0.4,
                relatedSymbols: Array((stringInterpolationSymbols + stringConcatSymbols).prefix(5).map(\.name)),
                details: [
                    .init(key: "String Interpolations", value: "\(stringInterpolationSymbols.count)"),
                    .init(key: "String Concatenations", value: "\(stringConcatSymbols.count)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Memory-Mapped File Analysis

    private func analyzeMemoryMappedFiles() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let mmapSymbols = analyzer.findSymbols(matchingAny: [
            "mmap", "mappedIfSafe", "alwaysMapped", "NSDataReadingMapped"
        ])

        let fileReadSymbols = analyzer.findSymbols(matchingAny: [
            "contentsOfFile", "contentsOf", "FileHandle", "FileManager",
            "read(", "readData"
        ])

        if fileReadSymbols.count > 10 && mmapSymbols.count == 0 {
            issues.append(DiagnosticIssue(
                title: "File Reading Without Memory Mapping",
                description: "Found \(fileReadSymbols.count) file reading operations but no memory-mapped file access. Memory mapping allows the OS to page data in/out as needed.",
                severity: .suggestion,
                instrument: .allocations,
                category: "Memory-Mapped Files",
                recommendation: "Use `Data(contentsOf: url, options: .mappedIfSafe)` for large read-only files. Memory-mapped files let the OS manage which portions are in physical memory, reducing your app's memory footprint.",
                impact: "Loading entire files into memory creates proportional allocation spikes. Memory mapping defers loading to the OS virtual memory system, which can page data in and out as needed.",
                confidence: 0.45,
                relatedSymbols: Array(fileReadSymbols.prefix(5).map(\.name)),
                details: [
                    .init(key: "File Read Operations", value: "\(fileReadSymbols.count)"),
                    .init(key: "Memory Map Usage", value: "\(mmapSymbols.count)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Binary Footprint Analysis

    private func analyzeBinaryFootprint() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let binarySizeMB = Double(binarySize) / 1_048_576
        let textSizeMB = Double(analyzer.machOInfo.totalTextSize) / 1_048_576
        let dataSizeMB = Double(analyzer.machOInfo.totalDataSize) / 1_048_576

        if binarySizeMB > 100 {
            issues.append(DiagnosticIssue(
                title: "Large Binary Size",
                description: String(format: "The executable binary is %.1f MB. Large binaries increase launch time and base memory usage.", binarySizeMB),
                severity: binarySizeMB > 200 ? .warning : .info,
                instrument: .allocations,
                category: "Binary Footprint",
                recommendation: "Review linked frameworks for unused dependencies. Enable dead code stripping (DEAD_CODE_STRIPPING = YES). Consider lazy loading of features using dynamic frameworks. Use Asset Catalogs for resources instead of embedding them.",
                impact: "The entire __TEXT segment is mapped into memory at launch. Larger binaries increase launch time and contribute to the app's memory footprint.",
                confidence: 0.8,
                details: [
                    .init(key: "Binary Size", value: String(format: "%.1f MB", binarySizeMB)),
                    .init(key: "__TEXT Segment", value: String(format: "%.1f MB", textSizeMB)),
                    .init(key: "__DATA Segment", value: String(format: "%.1f MB", dataSizeMB)),
                    .init(key: "Linked Libraries", value: "\(analyzer.machOInfo.linkedLibraries.count)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Third-Party Framework Analysis

    private func analyzeThirdPartyFrameworks() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let embeddedFrameworks = analyzer.embeddedFrameworks()

        if embeddedFrameworks.count > 15 {
            issues.append(DiagnosticIssue(
                title: "High Number of Embedded Frameworks",
                description: "Found \(embeddedFrameworks.count) embedded frameworks. Each dynamic framework adds to launch time and memory overhead.",
                severity: embeddedFrameworks.count > 30 ? .warning : .info,
                instrument: .allocations,
                category: "Framework Footprint",
                recommendation: "Audit embedded frameworks for unused or redundant dependencies. Consider using static libraries instead of dynamic frameworks to reduce launch time overhead. Merge small frameworks where possible.",
                impact: "Each dynamic framework requires dyld to map, relocate, and initialize at launch. Apps with many frameworks experience slower cold launches and higher base memory usage.",
                confidence: 0.7,
                relatedSymbols: Array(embeddedFrameworks.prefix(10)),
                details: [
                    .init(key: "Embedded Frameworks", value: "\(embeddedFrameworks.count)"),
                    .init(key: "System Frameworks", value: "\(analyzer.systemFrameworks().count)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Scoring

    private func calculateScore(issues: [DiagnosticIssue]) -> Int {
        let totalPenalty = issues.reduce(0) { $0 + $1.severity.weight }
        return max(0, 100 - totalPenalty)
    }

    private func generateSummary(issues: [DiagnosticIssue], score: Int) -> String {
        if issues.isEmpty {
            return "No significant allocation concerns detected. Your app appears to manage memory allocations efficiently."
        }

        let critical = issues.filter { $0.severity == .critical }.count
        let warnings = issues.filter { $0.severity == .warning }.count

        if critical > 0 {
            return "Found \(critical) critical and \(warnings) warning-level allocation issue(s). These patterns may cause excessive memory usage and potential OOM termination."
        } else if warnings > 0 {
            return "Found \(warnings) warning-level allocation pattern(s) that may lead to elevated memory usage. Optimization recommended for better performance on memory-constrained devices."
        } else {
            return "Found \(issues.count) allocation optimization opportunit(ies). These suggestions can help reduce memory footprint and improve allocation efficiency."
        }
    }
}
