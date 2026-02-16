import UIKit
import Foundation

// =============================================================================
// MARK: - Memory Allocation & Strong Reference Examples
//
// This file contains allocation patterns and object graphs with multiple
// strong references that AIInstruments should detect and count. It also
// includes image loading, data buffer, and collection growth patterns
// that the Allocations analyzer looks for.
// =============================================================================

// MARK: - 1. Strong Reference Counting — Shared Object Graph
//
// Multiple objects hold strong references to the same shared instances.
// AIInstruments should count the number of strong references per type.

/// Central data store that many other objects hold strong references to.
final class SharedDataStore: @unchecked Sendable {
    var items: [String] = []
    var metadata: [String: String] = [:]

    func addItem(_ item: String) {
        items.append(item)
    }
}

/// Shared user session referenced by many services.
final class UserSession: @unchecked Sendable {
    static let current = UserSession()
    var userId: String = ""
    var authToken: String = ""
    var isActive: Bool = false
}

/// Ref 1 → SharedDataStore, Ref 1 → UserSession
final class HomeScreenManager {
    let dataStore: SharedDataStore
    let session: UserSession
    let imageCache: ImageCacheStore

    init(dataStore: SharedDataStore, session: UserSession, imageCache: ImageCacheStore) {
        self.dataStore = dataStore
        self.session = session
        self.imageCache = imageCache
    }

    func loadHome() {
        dataStore.addItem("home_loaded")
    }
}

/// Ref 2 → SharedDataStore, Ref 2 → UserSession
final class SearchManager {
    let dataStore: SharedDataStore
    let session: UserSession
    var recentSearches: [String] = []

    init(dataStore: SharedDataStore, session: UserSession) {
        self.dataStore = dataStore
        self.session = session
    }

    func search(_ query: String) {
        recentSearches.append(query)
        dataStore.addItem("search: \(query)")
    }
}

/// Ref 3 → SharedDataStore, Ref 3 → UserSession
final class CartManager {
    let dataStore: SharedDataStore
    let session: UserSession
    var cartItems: [String] = []

    init(dataStore: SharedDataStore, session: UserSession) {
        self.dataStore = dataStore
        self.session = session
    }

    func addToCart(_ item: String) {
        cartItems.append(item)
        dataStore.addItem("cart: \(item)")
    }
}

/// Ref 4 → SharedDataStore, Ref 4 → UserSession
final class OrderManager {
    let dataStore: SharedDataStore
    let session: UserSession
    var orders: [String] = []

    init(dataStore: SharedDataStore, session: UserSession) {
        self.dataStore = dataStore
        self.session = session
    }

    func placeOrder() {
        let orderId = "ORD-\(orders.count + 1)"
        orders.append(orderId)
        dataStore.addItem("order: \(orderId)")
    }
}

/// Ref 5 → SharedDataStore, Ref 5 → UserSession
final class NotificationManager: @unchecked Sendable {
    let dataStore: SharedDataStore
    let session: UserSession
    var unreadCount: Int = 0

    init(dataStore: SharedDataStore, session: UserSession) {
        self.dataStore = dataStore
        self.session = session
    }

    func markAsRead() {
        unreadCount = 0
        dataStore.addItem("notifications_read")
    }
}

/// Ref 6 → SharedDataStore, Ref 6 → UserSession
final class AnalyticsManager: @unchecked Sendable {
    let dataStore: SharedDataStore
    let session: UserSession
    var eventLog: [String] = []

    init(dataStore: SharedDataStore, session: UserSession) {
        self.dataStore = dataStore
        self.session = session
    }

    func logEvent(_ event: String) {
        eventLog.append(event)
        dataStore.addItem("analytics: \(event)")
    }
}

/// Ref 7 → SharedDataStore
final class SyncManager: @unchecked Sendable {
    let dataStore: SharedDataStore
    let session: UserSession

    init(dataStore: SharedDataStore, session: UserSession) {
        self.dataStore = dataStore
        self.session = session
    }

    func syncToServer() {
        dataStore.addItem("sync_started")
    }
}

/// Object that wires everything together, demonstrating the reference graph.
final class AppContainer {
    let dataStore = SharedDataStore()
    let session = UserSession.current
    let imageCache = ImageCacheStore()

    lazy var homeManager = HomeScreenManager(dataStore: dataStore, session: session, imageCache: imageCache)
    lazy var searchManager = SearchManager(dataStore: dataStore, session: session)
    lazy var cartManager = CartManager(dataStore: dataStore, session: session)
    lazy var orderManager = OrderManager(dataStore: dataStore, session: session)
    lazy var notificationManager = NotificationManager(dataStore: dataStore, session: session)
    lazy var analyticsManager = AnalyticsManager(dataStore: dataStore, session: session)
    lazy var syncManager = SyncManager(dataStore: dataStore, session: session)

    func initialize() {
        homeManager.loadHome()
        analyticsManager.logEvent("app_launch")
    }
}

// MARK: - 2. Heavy Image Loading Without Downsampling

/// BUG: Loads many images at full resolution — no downsampling, no caching strategy.
final class ImageGalleryViewController: UIViewController {
    private var images: [UIImage] = []
    private var imageViews: [UIImageView] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        loadAllImages()
    }

    private func loadAllImages() {
        // BUG: UIImage(named:) loads and caches at full resolution
        if let img = UIImage(named: "hero_banner") { images.append(img) }
        if let img = UIImage(named: "profile_photo") { images.append(img) }
        if let img = UIImage(named: "background_large") { images.append(img) }
        if let img = UIImage(named: "product_01") { images.append(img) }
        if let img = UIImage(named: "product_02") { images.append(img) }
        if let img = UIImage(named: "product_03") { images.append(img) }
        if let img = UIImage(named: "product_04") { images.append(img) }
        if let img = UIImage(named: "product_05") { images.append(img) }
        if let img = UIImage(named: "category_header") { images.append(img) }
        if let img = UIImage(named: "promo_banner") { images.append(img) }
        if let img = UIImage(named: "avatar_default") { images.append(img) }
        if let img = UIImage(named: "placeholder") { images.append(img) }

        // BUG: Loading from data without downsampling
        for i in 0..<5 {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: "/tmp/photo_\(i).jpg")),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }

        // Creating UIImageViews with full-size images
        for image in images {
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFill
            imageViews.append(imageView)
        }
    }

    /// BUG: Network image loading without downsampling
    func loadRemoteImages(_ urls: [URL]) {
        for url in urls {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data = data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        let iv = UIImageView(image: image)
                        self.imageViews.append(iv)
                    }
                }
            }.resume()
        }
    }
}

// MARK: - 3. Image Cache Store (Cache Without Memory Warning Handling)

/// BUG: Dictionary-based cache that does NOT respond to memory warnings.
/// NSCache auto-evicts, but this custom cache does not.
final class ImageCacheStore: @unchecked Sendable {
    var cache: [String: UIImage] = [:]
    var dataCache: [String: Data] = [:]

    func cacheImage(_ image: UIImage, forKey key: String) {
        cache[key] = image
    }

    func cachedImage(forKey key: String) -> UIImage? {
        return cache[key]
    }

    func cacheData(_ data: Data, forKey key: String) {
        dataCache[key] = data
    }

    // BUG: No didReceiveMemoryWarning handling to clear the cache
}

// MARK: - 4. Data Buffer Creation Patterns

/// BUG: Frequently creates large Data buffers without using memory mapping.
final class DataProcessingService: @unchecked Sendable {
    func processFiles(at paths: [String]) {
        for path in paths {
            // BUG: Loads entire file into memory
            if let data = NSData(contentsOfFile: path) as Data? {
                process(data)
            }
        }
    }

    func downloadAndProcess(urls: [URL]) {
        for url in urls {
            // BUG: contentsOf loads everything into a single Data buffer
            if let data = try? Data(contentsOf: url) {
                process(data)
            }
        }
    }

    func createBuffers() {
        // BUG: Pre-allocating large buffers
        let buffer1 = Data(count: 1024 * 1024)
        let buffer2 = Data(capacity: 512 * 1024)
        let buffer3 = Data(repeating: 0, count: 256 * 1024)
        process(buffer1)
        process(buffer2)
        process(buffer3)
    }

    func decodeJSON(from urls: [URL]) {
        let decoder = JSONDecoder()
        for url in urls {
            if let data = try? Data(contentsOf: url) {
                let _ = try? decoder.decode([String: String].self, from: data)
            }
        }
        let encoder = JSONEncoder()
        let samplePayload = ["key": "value", "foo": "bar"]
        if let encoded = try? encoder.encode(samplePayload) {
            process(encoded)
        }
    }

    private func process(_ data: Data) {}
}

// MARK: - 5. Collection Growth Without Capacity Reservation

/// BUG: Collections grow incrementally without reserveCapacity — causes allocation churn.
final class CollectionGrowthExample {
    func buildLargeArray() -> [String] {
        // BUG: No reserveCapacity — array reallocates as it grows
        var results: [String] = []
        for i in 0..<10000 {
            results.append("Item \(i)")
        }
        return results
    }

    func buildDictionary() -> [String: Int] {
        // BUG: No reserveCapacity on dictionary
        var dict: [String: Int] = [:]
        for i in 0..<5000 {
            dict["key_\(i)"] = i
            dict.updateValue(i * 2, forKey: "double_\(i)")
        }
        return dict
    }

    func buildSet() -> Set<String> {
        var set: Set<String> = []
        for i in 0..<3000 {
            set.insert("element_\(i)")
        }
        return set
    }

    func transformCollections() -> [String] {
        let source = Array(0..<1000)

        let mapped = source.map { "value_\($0)" }
        let filtered = mapped.filter { $0.contains("1") }
        let compacted = source.compactMap { $0 > 500 ? "big_\($0)" : nil }
        let flat = [source, source, source].flatMap { $0.map { String($0) } }
        let reduced = source.reduce("") { $0 + ",\($1)" }
        _ = reduced

        var combined: [String] = []
        combined.append(contentsOf: mapped)
        combined.append(contentsOf: filtered)
        combined.append(contentsOf: compacted)
        combined.append(contentsOf: flat)

        for (index, element) in source.enumerated() {
            combined.append("\(index):\(element)")
        }

        return combined
    }

    func processWithMutableArrays() {
        var items = NSMutableArray()
        for i in 0..<100 {
            items.add("NSItem_\(i)")
        }

        var dict = NSMutableDictionary()
        for i in 0..<100 {
            dict["key_\(i)"] = "value_\(i)"
        }
    }
}

// MARK: - 6. String Allocation Patterns

/// BUG: Heavy string operations cause allocation overhead from copy-on-write.
final class StringProcessor {
    func buildReport(items: [String]) -> String {
        // BUG: String concatenation in a loop — each `+` creates a new String
        var report = ""
        for item in items {
            report = report + "- " + item + "\n"
        }
        return report
    }

    func formatEntries(_ entries: [(String, Int)]) -> [String] {
        // Heavy string interpolation
        return entries.map { name, count in
            "Entry: \(name) (count: \(count), formatted: \(String(format: "%05d", count)))"
        }
    }

    func processCSV(_ csv: String) -> [[String]] {
        let lines = csv.components(separatedBy: "\n")
        return lines.map { $0.components(separatedBy: ",") }
    }

    func joinResults(_ results: [[String]]) -> String {
        return results.map { $0.joined(separator: ", ") }.joined(separator: "\n")
    }

    func generateLogLines(count: Int) -> [String] {
        var lines: [String] = []
        for i in 0..<count {
            let timestamp = String(format: "2026-02-16T%02d:%02d:%02d", i / 3600, (i / 60) % 60, i % 60)
            let level = i % 3 == 0 ? "ERROR" : (i % 2 == 0 ? "WARN" : "INFO")
            let message = "Log entry #\(i): \(level) at \(timestamp) — processing item \(i)"
            lines.append(contentsOf: [message])
        }
        return lines
    }
}

// MARK: - 7. File Reading Without Memory Mapping

/// BUG: Reads files entirely into memory instead of using memory-mapped access.
final class FileProcessor: @unchecked Sendable {
    func readAllFiles(in directory: String) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: directory) else { return }

        for file in files {
            let path = (directory as NSString).appendingPathComponent(file)

            // BUG: No .mappedIfSafe option
            if let data = fm.contents(atPath: path) {
                processFileData(data)
            }
        }
    }

    func readWithFileHandle(_ path: String) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        let data = handle.readDataToEndOfFile()
        handle.closeFile()
        processFileData(data)
    }

    func readMultipleFiles(_ paths: [String]) {
        for path in paths {
            // BUG: contentsOfFile without memory mapping
            if let data = NSData(contentsOfFile: path) as Data? {
                processFileData(data)
            }
        }
    }

    func readFromURLs(_ urls: [URL]) {
        for url in urls {
            // BUG: No .mappedIfSafe
            if let data = try? Data(contentsOf: url) {
                processFileData(data)
            }
        }
    }

    private func processFileData(_ data: Data) {}
}

// MARK: - 8. ObjC Bridging Without Autorelease Pools

/// BUG: Heavy ObjC bridging in loops without wrapping in autoreleasepool.
final class ObjCBridgingExample {
    func processStrings(_ strings: [String]) -> [NSString] {
        // BUG: Each Swift String → NSString bridge creates an autoreleased ObjC object
        var results: [NSString] = []
        for str in strings {
            let nsStr = str as NSString
            let uppercased = nsStr.uppercased as NSString
            results.append(uppercased)
        }
        return results
    }

    func processDictionaries(_ dicts: [[String: Any]]) -> [NSDictionary] {
        var results: [NSDictionary] = []
        for dict in dicts {
            let nsDict = dict as NSDictionary
            results.append(nsDict)
        }
        return results
    }

    func processArrays(_ arrays: [[Int]]) -> [NSArray] {
        var results: [NSArray] = []
        for arr in arrays {
            let nsArr = arr as NSArray
            results.append(nsArr)
        }
        return results
    }
}
