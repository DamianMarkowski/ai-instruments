import UIKit
import Foundation

// =============================================================================
// MARK: - App Launch / Startup Time Examples
//
// This file contains intentional patterns that negatively affect app launch
// time. AIInstruments should detect these when analyzing the compiled binary.
// =============================================================================

// MARK: - 1. Static Initializers / +load Methods

final class EagerlyInitializedService {
    static let shared = EagerlyInitializedService()
    private init() {
        Thread.sleep(forTimeInterval: 0.05)
    }
}

final class AnotherEagerService {
    static let shared = AnotherEagerService()
    private init() {
        _ = UserDefaults.standard.string(forKey: "config")
    }
}

// MARK: - 2. Heavy AppDelegate Work

final class HeavyAppDelegate {
    func didFinishLaunchingWithOptions() {
        initializeAnalytics()
        initializeCrashReporting()
        initializePushNotifications()
        setupDatabaseMigration()
        prefetchData()
    }

    private func initializeAnalytics() {
        Thread.sleep(forTimeInterval: 0.02)
    }

    private func initializeCrashReporting() {
        Thread.sleep(forTimeInterval: 0.01)
    }

    private func initializePushNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func setupDatabaseMigration() {
        Thread.sleep(forTimeInterval: 0.05)
    }

    private func prefetchData() {
        URLSession.shared.dataTask(with: URL(string: "https://api.example.com/config")!) { _, _, _ in }.resume()
    }
}

// MARK: - 3. Multiple SDK Initializations

final class SDKInitializer {
    func initializeAllSDKs() {
        configureFirebase()
        configureCrashlytics()
        configureAnalytics()
        configureRemoteConfig()
        configurePushService()
        configureFeatureFlags()
    }

    private func configureFirebase() {}
    private func configureCrashlytics() {}
    private func configureAnalytics() {}
    private func configureRemoteConfig() {}
    private func configurePushService() {}
    private func configureFeatureFlags() {}
}

// MARK: - 4. Singleton Eager Access

final class GlobalStateInitializer {
    static let shared = GlobalStateInitializer()
    let networkManager = NetworkManagerStartup.shared
    let cacheManager = CacheManagerStartup.shared
    let configManager = ConfigManagerStartup.shared

    private init() {}
}

final class NetworkManagerStartup {
    static let shared = NetworkManagerStartup()
    private init() {}
}

final class CacheManagerStartup {
    static let shared = CacheManagerStartup()
    private init() {}
}

final class ConfigManagerStartup {
    static let shared = ConfigManagerStartup()
    private init() {}
}
