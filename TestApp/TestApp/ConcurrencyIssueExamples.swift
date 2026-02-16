import UIKit
import Foundation

// =============================================================================
// MARK: - Swift Concurrency Issue Examples
//
// This file contains intentional Swift concurrency anti-patterns that
// AIInstruments should detect. Each section demonstrates a common concurrency
// issue found in real iOS applications.
// =============================================================================

// MARK: - 1. Non-Sendable Types Crossing Concurrency Boundaries

/// BUG: Mutable class passed across concurrency boundaries without Sendable.
final class UserProfile {
    var name: String
    var email: String
    var avatarData: Data?
    var preferences: [String: Any] = [:]

    init(name: String, email: String) {
        self.name = name
        self.email = email
    }
}

/// BUG: Mutable state holder without Sendable conformance.
final class RequestContext {
    var headers: [String: String] = [:]
    var timeout: TimeInterval = 30
    var retryCount: Int = 0
    var body: Data?
}

/// BUG: Another non-Sendable type used in async contexts.
final class AnalyticsPayload {
    var eventName: String = ""
    var properties: [String: String] = [:]
    var timestamp: Date = Date()
    var userId: String?
}

// MARK: - 2. Unprotected Global / Static Mutable State

/// BUG: Global mutable state without any synchronization.
nonisolated(unsafe) var globalRequestCount: Int = 0
nonisolated(unsafe) var globalLastError: Error? = nil
nonisolated(unsafe) var globalActiveConnections: [String] = []
nonisolated(unsafe) var globalFeatureFlags: [String: Bool] = [:]
nonisolated(unsafe) var globalUserToken: String? = nil
nonisolated(unsafe) var globalEnvironment: String = "production"

/// BUG: Singleton with mutable state, no lock protection.
final class AppConfiguration: @unchecked Sendable {
    static let shared = AppConfiguration()
    static var sharedInstance: AppConfiguration { shared }

    var apiBaseURL: String = "https://api.example.com"
    var debugMode: Bool = false
    var logLevel: Int = 1
    var maxRetries: Int = 3
    var requestTimeout: TimeInterval = 30
    var currentUser: UserProfile?
    var sessionToken: String?

    private init() {}

    func update(baseURL: String) {
        apiBaseURL = baseURL
    }
}

/// BUG: Another singleton with unprotected mutable shared state.
final class FeatureFlagStore: @unchecked Sendable {
    static let shared = FeatureFlagStore()
    var flags: [String: Bool] = [:]
    var lastFetchDate: Date?

    private init() {}

    func isEnabled(_ flag: String) -> Bool {
        return flags[flag] ?? false
    }

    func setFlag(_ flag: String, enabled: Bool) {
        flags[flag] = enabled
    }
}

/// BUG: Static mutable properties on a type — data race risk.
final class MetricsCollector: @unchecked Sendable {
    static var instance = MetricsCollector()
    static var eventCount: Int = 0
    static var lastEventTime: Date?

    var metrics: [String: Double] = [:]
    var isCollecting = false

    func record(_ name: String, value: Double) {
        metrics[name] = value
        MetricsCollector.eventCount += 1
        MetricsCollector.lastEventTime = Date()
    }
}

// MARK: - 3. Tasks Without Cancellation Handling

/// BUG: Creates many tasks but never checks for cancellation or stores handles.
final class DataSyncManager {
    func syncAllData() {
        _ = Task { await fetchUsers() }
        _ = Task { await fetchPosts() }
        _ = Task { await fetchComments() }
        _ = Task { await fetchNotifications() }
        _ = Task { await fetchMessages() }
        _ = Task { await fetchSettings() }
        // BUG: None of these tasks check Task.isCancelled
        // BUG: No task handles stored — can't cancel them
    }

    private func fetchUsers() async {
        try? await Task.sleep(for: .seconds(2))
        globalRequestCount += 1
    }

    private func fetchPosts() async {
        try? await Task.sleep(for: .seconds(3))
        globalRequestCount += 1
    }

    private func fetchComments() async {
        try? await Task.sleep(for: .seconds(1))
        globalRequestCount += 1
    }

    private func fetchNotifications() async {
        try? await Task.sleep(for: .seconds(2))
        globalRequestCount += 1
    }

    private func fetchMessages() async {
        try? await Task.sleep(for: .seconds(4))
        globalRequestCount += 1
    }

    private func fetchSettings() async {
        try? await Task.sleep(for: .seconds(1))
        globalRequestCount += 1
    }
}

// MARK: - 4. Detached Tasks (Lose Structured Concurrency Benefits)

/// BUG: Heavy use of Task.detached — loses parent task context, priority, and cancellation.
final class BackgroundProcessor {
    func processAll() {
        Task.detached {
            await self.processImages()
        }
        Task.detached {
            await self.processVideos()
        }
        Task.detached {
            await self.processDocuments()
        }
        Task.detached {
            await self.compressFiles()
        }
        Task.detached(priority: .background) {
            await self.cleanupCache()
        }
    }

    private func processImages() async {
        try? await Task.sleep(for: .seconds(5))
    }

    private func processVideos() async {
        try? await Task.sleep(for: .seconds(10))
    }

    private func processDocuments() async {
        try? await Task.sleep(for: .seconds(3))
    }

    private func compressFiles() async {
        try? await Task.sleep(for: .seconds(7))
    }

    private func cleanupCache() async {
        try? await Task.sleep(for: .seconds(2))
    }
}

// MARK: - 5. Mixed Concurrency Models (GCD + Swift Concurrency)

/// BUG: Mixes DispatchQueue (GCD) with async/await in the same type.
final class MixedConcurrencyService: @unchecked Sendable {
    private let serialQueue = DispatchQueue(label: "com.testapp.serial")
    private let concurrentQueue = DispatchQueue(label: "com.testapp.concurrent", attributes: .concurrent)
    private let processingGroup = DispatchGroup()
    var results: [String] = []

    func performMixedWork() async {
        // GCD-based work
        DispatchQueue.global(qos: .userInitiated).async {
            self.processItemA()
        }
        DispatchQueue.global(qos: .utility).async {
            self.processItemB()
        }
        DispatchQueue.global().async {
            self.processItemC()
        }

        // Swift Concurrency-based work (in the same flow!)
        await withTaskGroup(of: String.self) { group in
            group.addTask { await self.asyncProcessA() }
            group.addTask { await self.asyncProcessB() }
            group.addTask { await self.asyncProcessC() }
            for await result in group {
                results.append(result)
            }
        }

        // More GCD
        serialQueue.async { self.finalize() }
        concurrentQueue.async { self.log() }

        processingGroup.enter()
        DispatchQueue.global().async {
            self.processItemD()
            self.processingGroup.leave()
        }
        processingGroup.enter()
        DispatchQueue.global().async {
            self.processItemE()
            self.processingGroup.leave()
        }

        processingGroup.notify(queue: .main) {
            self.updateUI()
        }
    }

    /// BUG: DispatchQueue.sync — deadlock risk if called on the current queue.
    func synchronousAccess() -> [String] {
        serialQueue.sync { results }
    }

    func synchronousProcess() -> Int {
        serialQueue.sync { results.count }
    }

    func synchronousRead() -> String {
        serialQueue.sync { results.first ?? "" }
    }

    func synchronousCheck() -> Bool {
        serialQueue.sync { !results.isEmpty }
    }

    private func processItemA() {}
    private func processItemB() {}
    private func processItemC() {}
    private func processItemD() {}
    private func processItemE() {}
    private func finalize() {}
    private func log() {}
    private func updateUI() {}

    private func asyncProcessA() async -> String {
        try? await Task.sleep(for: .seconds(1))
        return "A"
    }

    private func asyncProcessB() async -> String {
        try? await Task.sleep(for: .seconds(1))
        return "B"
    }

    private func asyncProcessC() async -> String {
        try? await Task.sleep(for: .seconds(1))
        return "C"
    }
}

// MARK: - 6. Legacy Main Queue Dispatching Alongside Swift Concurrency

/// BUG: Uses DispatchQueue.main.async for UI updates instead of @MainActor.
final class LegacyUIUpdater: @unchecked Sendable {
    func fetchAndUpdateUI() async {
        let data = await fetchData()

        DispatchQueue.main.async {
            self.applyData(data)
        }
        DispatchQueue.main.async {
            self.refreshLabels()
        }
        DispatchQueue.main.async {
            self.updateBadge()
        }
        DispatchQueue.main.async {
            self.animateChanges()
        }
        DispatchQueue.main.async {
            self.reloadTable()
        }
        DispatchQueue.main.async {
            self.dismissLoader()
        }
    }

    private func fetchData() async -> Data {
        try? await Task.sleep(for: .seconds(1))
        return Data()
    }

    private func applyData(_ data: Data) {}
    private func refreshLabels() {}
    private func updateBadge() {}
    private func animateChanges() {}
    private func reloadTable() {}
    private func dismissLoader() {}
}

// MARK: - 7. Unsafe Continuations

/// BUG: Uses unsafe continuations where checked ones should be preferred.
final class LegacyAPIBridge {
    typealias Callback = (Data?, Error?) -> Void

    func legacyFetch(url: URL, completion: @escaping Callback) {
        URLSession.shared.dataTask(with: url) { data, _, error in
            completion(data, error)
        }.resume()
    }

    /// BUG: Should use withCheckedContinuation, not withUnsafeContinuation
    func fetchAsync(url: URL) async -> Data? {
        await withUnsafeContinuation { continuation in
            legacyFetch(url: url) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// BUG: Another unsafe continuation
    func fetchAsyncThrowing(url: URL) async throws -> Data {
        try await withUnsafeThrowingContinuation { continuation in
            legacyFetch(url: url) { data, error in
                if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? URLError(.badServerResponse))
                }
            }
        }
    }

    /// BUG: And two more unsafe continuations
    func fetchWithTimeout(url: URL) async -> Data? {
        await withUnsafeContinuation { continuation in
            legacyFetch(url: url) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    func fetchAndValidate(url: URL) async throws -> Data {
        try await withUnsafeThrowingContinuation { continuation in
            legacyFetch(url: url) { data, error in
                if let data = data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? URLError(.zeroByteResource))
                }
            }
        }
    }
}

// MARK: - 8. Concurrency-Unsafe ViewController

/// BUG: Async work in a ViewController without proper MainActor/cancellation handling.
final class FeedViewController: UIViewController {
    private var items: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        // BUG: Unstructured tasks without handles — can't cancel when VC dismissed
        Task {
            await loadFeed()
        }
        Task {
            await loadSuggestions()
        }
        Task {
            await loadAds()
        }

        // Mix of old and new concurrency
        DispatchQueue.global(qos: .background).async {
            self.prefetchImages()
        }
        DispatchQueue.global().async {
            self.precomputeLayouts()
        }
    }

    private func loadFeed() async {
        try? await Task.sleep(for: .seconds(2))
        items = ["Post 1", "Post 2", "Post 3"]
    }

    private func loadSuggestions() async {
        try? await Task.sleep(for: .seconds(1))
    }

    private func loadAds() async {
        try? await Task.sleep(for: .seconds(3))
    }

    private func prefetchImages() {}
    private func precomputeLayouts() {}
}
