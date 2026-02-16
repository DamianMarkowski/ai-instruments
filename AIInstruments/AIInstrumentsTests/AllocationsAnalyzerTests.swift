import Testing
import Nimble
@testable import AIInstruments

@Suite("AllocationsAnalyzer Tests")
struct AllocationsAnalyzerTests {

    // MARK: - Basic Analysis

    @Test("Analyzing small binary with no patterns produces clean result")
    func cleanBinary() {
        let ba = makeBinaryAnalyzer()
        let result = AllocationsAnalyzer(binaryAnalyzer: ba, binarySize: 1_000).analyze()

        expect(result.instrument).to(equal(.allocations))
        expect(result.score).to(equal(100))
    }

    // MARK: - Large Allocation Detection

    @Test("Detects significant manual memory allocation")
    func manualAllocations() {
        var symbols: [SymbolInfo] = []
        for i in 0..<15 {
            symbols.append(makeSymbol("_malloc_\(i)"))
        }

        let ba = makeBinaryAnalyzer(symbols: symbols)
        let result = AllocationsAnalyzer(binaryAnalyzer: ba, binarySize: 1_000).analyze()
        let allocIssues = result.issues.filter { $0.category == "Manual Allocations" }
        expect(allocIssues).toNot(beEmpty())
    }

    // MARK: - Image Loading Detection

    @Test("Detects heavy image loading without downsampling")
    func imageLoadingNoDownsampling() {
        let ba = makeBinaryAnalyzer(
            objcSelectors: [
                "imageNamed:", "imageWithContentsOfFile:", "UIImage",
                "imageWithData:"
            ]
        )

        let result = AllocationsAnalyzer(binaryAnalyzer: ba, binarySize: 1_000).analyze()
        let imageIssues = result.issues.filter { $0.category == "Image Loading" }
        expect(imageIssues).toNot(beEmpty())
    }

    @Test("No image loading issue when downsampling is used")
    func imageLoadingWithDownsampling() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_UIImage_1"),
                makeSymbol("_imageNamed_1"),
            ],
            objcSelectors: [
                "imageNamed:", "UIImage",
                "preparingThumbnail", "preparingThumbnail"
            ]
        )

        let result = AllocationsAnalyzer(binaryAnalyzer: ba, binarySize: 1_000).analyze()
        let heavyImageIssues = result.issues.filter {
            $0.category == "Image Loading" && $0.title.contains("Without Downsampling")
        }
        expect(heavyImageIssues).to(beEmpty())
    }

    // MARK: - Data Buffer Detection

    @Test("Detects frequent data buffer creation")
    func dataBuffers() {
        let ba = makeBinaryAnalyzer(
            objcSelectors: [
                "dataWithContentsOfFile:", "NSData",
                "dataWithContentsOfURL:", "dataWithContentsOfFile:"
            ]
        )

        let result = AllocationsAnalyzer(binaryAnalyzer: ba, binarySize: 1_000).analyze()
        let dataIssues = result.issues.filter { $0.category == "Data Buffers" }
        expect(dataIssues).toNot(beEmpty())
    }

    // MARK: - Autorelease Pool Detection

    @Test("Detects ObjC bridging without autorelease pool management")
    func autoreleasePoolMissing() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_bridge_1"),
                makeSymbol("_NSString_1"),
                makeSymbol("_NSArray_1"),
                makeSymbol("_NSDictionary_1"),
                makeSymbol("_bridge_2"),
                makeSymbol("_bridgeToObjectiveC"),
            ]
        )

        let result = AllocationsAnalyzer(binaryAnalyzer: ba, binarySize: 1_000).analyze()
        let autoreleaseIssues = result.issues.filter { $0.category == "Autorelease Pools" }
        expect(autoreleaseIssues).toNot(beEmpty())
    }

    // MARK: - Collection Growth Detection

    @Test("Detects collection growth without capacity reservation")
    func collectionGrowth() {
        var symbols: [SymbolInfo] = []
        for i in 0..<20 {
            symbols.append(makeSymbol("_Array_append_\(i)"))
        }
        for i in 0..<15 {
            symbols.append(makeSymbol("_Dictionary_update_\(i)"))
        }

        let ba = makeBinaryAnalyzer(symbols: symbols)
        let result = AllocationsAnalyzer(binaryAnalyzer: ba, binarySize: 1_000).analyze()
        let collectionIssues = result.issues.filter { $0.category == "Collection Growth" }
        expect(collectionIssues).toNot(beEmpty())
    }

    // MARK: - Cache Usage Detection

    @Test("Detects cache usage without memory warning handling")
    func cacheNoMemoryWarning() {
        let ba = makeBinaryAnalyzer(
            symbols: [makeSymbol("_NSCache_init")]
        )

        let result = AllocationsAnalyzer(binaryAnalyzer: ba, binarySize: 1_000).analyze()
        let cacheIssues = result.issues.filter { $0.category == "Cache Management" }
        expect(cacheIssues).toNot(beEmpty())
    }

    // MARK: - Memory-Mapped File Detection

    @Test("Detects file reading without memory mapping")
    func fileReadingNoMmap() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_FileHandle_1"),
                makeSymbol("_contentsOfFile_1"),
                makeSymbol("_FileManager_1"),
                makeSymbol("_readData_1"),
            ]
        )

        let result = AllocationsAnalyzer(binaryAnalyzer: ba, binarySize: 1_000).analyze()
        let mmapIssues = result.issues.filter { $0.category == "Memory-Mapped Files" }
        expect(mmapIssues).toNot(beEmpty())
    }

    // MARK: - Binary Footprint Detection

    @Test("Detects large binary size")
    func largeBinarySize() {
        let ba = makeBinaryAnalyzer(totalTextSize: 50_000_000, totalDataSize: 20_000_000)
        let largeBinarySize = 120_000_000 // 120 MB

        let result = AllocationsAnalyzer(binaryAnalyzer: ba, binarySize: largeBinarySize).analyze()
        let footprintIssues = result.issues.filter { $0.category == "Binary Footprint" }
        expect(footprintIssues).toNot(beEmpty())
    }

    @Test("No binary footprint issue for small binaries")
    func smallBinarySize() {
        let ba = makeBinaryAnalyzer()
        let result = AllocationsAnalyzer(binaryAnalyzer: ba, binarySize: 5_000_000).analyze()
        let footprintIssues = result.issues.filter { $0.category == "Binary Footprint" }
        expect(footprintIssues).to(beEmpty())
    }

    // MARK: - Third-Party Framework Detection

    @Test("Detects high number of embedded frameworks")
    func manyEmbeddedFrameworks() {
        var libraries: [String] = []
        for i in 0..<20 {
            libraries.append("@rpath/Framework\(i).framework/Framework\(i)")
        }

        let ba = makeBinaryAnalyzer(linkedLibraries: libraries)
        let result = AllocationsAnalyzer(binaryAnalyzer: ba, binarySize: 1_000).analyze()
        let frameworkIssues = result.issues.filter { $0.category == "Framework Footprint" }
        expect(frameworkIssues).toNot(beEmpty())
    }

    // MARK: - Scoring

    @Test("Score decreases with more issues")
    func scoringPenalty() {
        let cleanBa = makeBinaryAnalyzer()
        let cleanResult = AllocationsAnalyzer(binaryAnalyzer: cleanBa, binarySize: 1_000).analyze()

        var symbols: [SymbolInfo] = []
        for i in 0..<15 { symbols.append(makeSymbol("_malloc_\(i)")) }
        let dirtyBa = makeBinaryAnalyzer(symbols: symbols)
        let dirtyResult = AllocationsAnalyzer(binaryAnalyzer: dirtyBa, binarySize: 120_000_000).analyze()

        expect(dirtyResult.score).to(beLessThan(cleanResult.score))
    }

    // MARK: - Metadata

    @Test("Result metadata contains expected keys")
    func metadata() {
        let ba = makeBinaryAnalyzer()
        let result = AllocationsAnalyzer(binaryAnalyzer: ba, binarySize: 5_000_000).analyze()
        expect(result.metadata["binarySizeMB"]).toNot(beNil())
        expect(result.metadata["textSegmentSizeMB"]).toNot(beNil())
        expect(result.metadata["dataSegmentSizeMB"]).toNot(beNil())
        expect(result.metadata["linkedFrameworks"]).toNot(beNil())
    }
}
