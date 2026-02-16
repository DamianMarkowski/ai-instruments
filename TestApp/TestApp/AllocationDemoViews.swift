import SwiftUI
import UIKit

// MARK: - 1. Strong Reference Graph Demo

struct StrongRefGraphDemoView: View {
    @State private var log: [String] = []

    var body: some View {
        DemoScreen(
            description: "Multiple manager objects all hold strong references to the same SharedDataStore and UserSession. AIInstruments counts how many strong references point to each object.",
            log: log,
            onSimulate: simulate
        )
        .navigationTitle("Strong Reference Graph")
    }

    private func simulate() {
        log = ["▶ Creating AppContainer with shared objects..."]

        let container = AppContainer()
        container.initialize()

        log.append("")
        log.append("  SharedDataStore is strongly held by:")
        log.append("    1. AppContainer.dataStore")
        log.append("    2. HomeScreenManager.dataStore")
        log.append("    3. SearchManager.dataStore")
        log.append("    4. CartManager.dataStore")
        log.append("    5. OrderManager.dataStore")
        log.append("    6. NotificationManager.dataStore")
        log.append("    7. AnalyticsManager.dataStore")
        log.append("    8. SyncManager.dataStore")
        log.append("  ➜ 8 strong references total")
        log.append("")
        log.append("  UserSession is strongly held by:")
        log.append("    1. HomeScreenManager.session")
        log.append("    2. SearchManager.session")
        log.append("    3. CartManager.session")
        log.append("    4. OrderManager.session")
        log.append("    5. NotificationManager.session")
        log.append("    6. AnalyticsManager.session")
        log.append("    7. SyncManager.session")
        log.append("  ➜ 7 strong references total")
        log.append("")
        log.append("  ImageCacheStore is strongly held by:")
        log.append("    1. AppContainer.imageCache")
        log.append("    2. HomeScreenManager.imageCache")
        log.append("  ➜ 2 strong references total")
        log.append("")
        log.append("⚠️ If AppContainer is never released,")
        log.append("  none of these objects can be freed.")
        log.append("  Items in dataStore: \(container.dataStore.items.count)")
    }
}

// MARK: - 2. Image Loading Demo

struct ImageLoadingDemoView: View {
    @State private var log: [String] = []

    var body: some View {
        DemoScreen(
            description: "UIImage(named:) and UIImage(data:) load and decode images at full resolution. A 12 MP photo uses ~48 MB of RAM when decoded. Without downsampling, memory spikes quickly.",
            log: log,
            onSimulate: simulate
        )
        .navigationTitle("Image Loading")
    }

    private func simulate() {
        log = ["▶ Loading images at full resolution..."]

        let imageNames = [
            "hero_banner", "profile_photo", "background_large",
            "product_01", "product_02", "product_03",
            "product_04", "product_05", "category_header",
            "promo_banner", "avatar_default", "placeholder",
            "icon_settings", "icon_home", "icon_search",
            "splash_screen",
        ]

        var loaded = 0
        var failed = 0

        for name in imageNames {
            let image = UIImage(named: name)
            if image != nil {
                loaded += 1
            } else {
                failed += 1
            }
        }

        log.append("  Attempted: \(imageNames.count)")
        log.append("  Loaded: \(loaded), Not found: \(failed)")
        log.append("")
        log.append("  Each UIImage(named:) call decodes at full")
        log.append("  resolution and caches in system image cache.")
        log.append("")

        let sampleData = Data(count: 1024)
        let fromData = UIImage(data: sampleData)
        log.append("  UIImage(data:) also decodes fully: \(fromData == nil ? "nil (invalid)" : "loaded")")

        log.append("")
        log.append("⚠️ No downsampling detected in this code path")
        log.append("  All \(imageNames.count) images loaded at full resolution.")
        log.append("")
        log.append("ℹ️ Fix: use UIImage.preparingThumbnail(of:)")
        log.append("   or CGImageSourceCreateThumbnailAtIndex")
        log.append("   to downsample before decode.")
    }
}

// MARK: - 3. Data Buffer Demo

struct DataBufferDemoView: View {
    @State private var log: [String] = []

    var body: some View {
        DemoScreen(
            description: "Data buffers are created by loading entire files into memory at once. For large files, this causes proportional memory spikes. Memory-mapped I/O would let the OS page data in/out as needed.",
            log: log,
            onSimulate: simulate
        )
        .navigationTitle("Data Buffers")
    }

    private func simulate() {
        log = ["▶ Creating various Data buffers..."]

        let sizes: [(String, Int)] = [
            ("64 KB", 64 * 1024),
            ("256 KB", 256 * 1024),
            ("1 MB", 1024 * 1024),
            ("4 MB", 4 * 1024 * 1024),
        ]

        var totalBytes = 0
        for (label, size) in sizes {
            let buffer = Data(count: size)
            totalBytes += buffer.count
            log.append("  Data(count: \(label)) → \(buffer.count) bytes")
        }

        log.append("")
        log.append("  Total allocated: \(totalBytes / 1024) KB")
        log.append("")

        let tmpFile = NSTemporaryDirectory() + "testapp_demo.bin"
        let testData = Data(repeating: 42, count: 512 * 1024)
        try? testData.write(to: URL(fileURLWithPath: tmpFile))

        if let loaded = try? Data(contentsOf: URL(fileURLWithPath: tmpFile)) {
            log.append("  Data(contentsOf:) loaded \(loaded.count / 1024) KB")
            log.append("  ⚠️ Entire file buffered in RAM")
        }

        if let nsLoaded = NSData(contentsOfFile: tmpFile) {
            log.append("  NSData(contentsOfFile:) loaded \(nsLoaded.length / 1024) KB")
        }

        try? FileManager.default.removeItem(atPath: tmpFile)

        log.append("")
        log.append("⚠️ All buffers loaded entirely into memory")
        log.append("  No memory mapping (.mappedIfSafe) used")
        log.append("")
        log.append("ℹ️ Fix: Data(contentsOf: url, options: .mappedIfSafe)")
        log.append("   for large read-only files")
    }
}

// MARK: - 4. Collection Growth Demo

struct CollectionGrowthDemoView: View {
    @State private var log: [String] = []

    var body: some View {
        DemoScreen(
            description: "Arrays, dictionaries, and sets that grow incrementally without reserveCapacity cause repeated reallocations. Each realloc copies all existing elements, creating allocation churn.",
            log: log,
            onSimulate: simulate
        )
        .navigationTitle("Collection Growth")
    }

    private func simulate() {
        let count = 50_000
        log = ["▶ Building collections with \(count) elements..."]
        log.append("")

        // Without reserveCapacity
        let start1 = CFAbsoluteTimeGetCurrent()
        var array1: [String] = []
        for i in 0..<count {
            array1.append("item_\(i)")
        }
        let time1 = CFAbsoluteTimeGetCurrent() - start1

        // With reserveCapacity
        let start2 = CFAbsoluteTimeGetCurrent()
        var array2: [String] = []
        array2.reserveCapacity(count)
        for i in 0..<count {
            array2.append("item_\(i)")
        }
        let time2 = CFAbsoluteTimeGetCurrent() - start2

        log.append("  Array (no reserve):   \(String(format: "%.4f", time1))s")
        log.append("  Array (with reserve): \(String(format: "%.4f", time2))s")

        if time1 > time2 {
            let pct = ((time1 - time2) / time2) * 100
            log.append("  ⚠️ \(String(format: "%.0f", pct))% slower without reserveCapacity")
        }

        log.append("")

        // Dictionary without reserve
        let start3 = CFAbsoluteTimeGetCurrent()
        var dict: [String: Int] = [:]
        for i in 0..<count {
            dict["key_\(i)"] = i
        }
        let time3 = CFAbsoluteTimeGetCurrent() - start3
        log.append("  Dict (no reserve):    \(String(format: "%.4f", time3))s")

        // With reserve
        let start4 = CFAbsoluteTimeGetCurrent()
        var dict2: [String: Int] = [:]
        dict2.reserveCapacity(count)
        for i in 0..<count {
            dict2["key_\(i)"] = i
        }
        let time4 = CFAbsoluteTimeGetCurrent() - start4
        log.append("  Dict (with reserve):  \(String(format: "%.4f", time4))s")

        log.append("")
        log.append("  Reallocations (array doubling):")
        log.append("  ≈ \(Int(log2(Double(count)))) reallocs for \(count) elements")
        log.append("  Each copies all existing elements.")
        log.append("")
        log.append("ℹ️ Fix: call .reserveCapacity(_:) when the")
        log.append("   approximate size is known ahead of time")
    }
}

// MARK: - 5. String Allocation Demo

struct StringAllocationDemoView: View {
    @State private var log: [String] = []

    var body: some View {
        DemoScreen(
            description: "String concatenation with + in a loop creates a new String each iteration. String interpolation and repeated .components(separatedBy:) add allocation overhead from copy-on-write.",
            log: log,
            onSimulate: simulate
        )
        .navigationTitle("String Allocations")
    }

    private func simulate() {
        let count = 10_000
        log = ["▶ String operations with \(count) iterations..."]
        log.append("")

        // Concatenation with +
        let start1 = CFAbsoluteTimeGetCurrent()
        var result1 = ""
        for i in 0..<count {
            result1 = result1 + "item\(i),"
        }
        let time1 = CFAbsoluteTimeGetCurrent() - start1

        // Using append
        let start2 = CFAbsoluteTimeGetCurrent()
        var result2 = ""
        for i in 0..<count {
            result2.append("item\(i),")
        }
        let time2 = CFAbsoluteTimeGetCurrent() - start2

        log.append("  Concatenation (+):  \(String(format: "%.4f", time1))s")
        log.append("  Mutation (append):  \(String(format: "%.4f", time2))s")

        if time1 > time2 * 1.2 {
            let factor = time1 / max(time2, 0.0001)
            log.append("  ⚠️ Concat is \(String(format: "%.1f", factor))× slower!")
        }

        log.append("")
        log.append("  String length: \(result1.count) characters")

        // String splitting
        let start3 = CFAbsoluteTimeGetCurrent()
        let parts = result2.components(separatedBy: ",")
        let time3 = CFAbsoluteTimeGetCurrent() - start3
        log.append("  components(separatedBy:): \(String(format: "%.4f", time3))s")
        log.append("  Produced \(parts.count) substrings")

        // Rejoining
        let start4 = CFAbsoluteTimeGetCurrent()
        _ = parts.joined(separator: "; ")
        let time4 = CFAbsoluteTimeGetCurrent() - start4
        log.append("  joined(separator:): \(String(format: "%.4f", time4))s")

        log.append("")
        log.append("⚠️ Each + creates a new String allocation,")
        log.append("  copying all previous content.")
        log.append("")
        log.append("ℹ️ Fix: use .append() or a single interpolation.")
        log.append("   Use Substring to avoid unnecessary copies.")
    }
}

// MARK: - 6. File I/O Demo

struct FileIODemoView: View {
    @State private var log: [String] = []

    var body: some View {
        DemoScreen(
            description: "Files are read entirely into memory using Data(contentsOf:) without .mappedIfSafe. Memory mapping lets the OS page data in/out, keeping the app's resident memory low.",
            log: log,
            onSimulate: simulate
        )
        .navigationTitle("File I/O")
    }

    private func simulate() {
        log = ["▶ Comparing file reading approaches..."]
        log.append("")

        let tmpDir = NSTemporaryDirectory()
        let filePath = tmpDir + "testapp_fileio_demo.bin"
        let fileURL = URL(fileURLWithPath: filePath)
        let fileSize = 2 * 1024 * 1024 // 2 MB

        let content = Data(repeating: 0xAB, count: fileSize)
        try? content.write(to: fileURL)

        log.append("  Created test file: \(fileSize / 1024) KB")
        log.append("")

        // Standard read (full buffer)
        let start1 = CFAbsoluteTimeGetCurrent()
        let data1 = try? Data(contentsOf: fileURL)
        let time1 = CFAbsoluteTimeGetCurrent() - start1
        log.append("  Data(contentsOf:)")
        log.append("    Time: \(String(format: "%.4f", time1))s")
        log.append("    Loaded: \(data1?.count ?? 0) bytes into RAM")
        log.append("    ⚠️ Entire file buffered in memory")
        log.append("")

        // Memory-mapped read
        let start2 = CFAbsoluteTimeGetCurrent()
        let data2 = try? Data(contentsOf: fileURL, options: .mappedIfSafe)
        let time2 = CFAbsoluteTimeGetCurrent() - start2
        log.append("  Data(contentsOf:, options: .mappedIfSafe)")
        log.append("    Time: \(String(format: "%.4f", time2))s")
        log.append("    Size: \(data2?.count ?? 0) bytes")
        log.append("    ✅ Memory-mapped — OS pages in on demand")
        log.append("")

        // FileHandle read
        let start3 = CFAbsoluteTimeGetCurrent()
        if let handle = FileHandle(forReadingAtPath: filePath) {
            let data3 = handle.readDataToEndOfFile()
            let time3 = CFAbsoluteTimeGetCurrent() - start3
            handle.closeFile()
            log.append("  FileHandle.readDataToEndOfFile()")
            log.append("    Time: \(String(format: "%.4f", time3))s")
            log.append("    Loaded: \(data3.count) bytes")
            log.append("    ⚠️ Also reads entire file into RAM")
        }

        try? FileManager.default.removeItem(at: fileURL)

        log.append("")
        log.append("ℹ️ For large read-only files, always use")
        log.append("   .mappedIfSafe to reduce memory footprint.")
    }
}
