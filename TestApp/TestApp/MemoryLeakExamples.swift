import UIKit
import Foundation

// =============================================================================
// MARK: - Memory Leak Examples
//
// This file contains intentional memory leak patterns that AIInstruments
// should detect when analyzing the compiled binary. Each section demonstrates
// a common iOS memory management anti-pattern.
// =============================================================================

// MARK: - 1. Strong Delegate References
// The delegate and dataSource properties should be `weak` to avoid retain cycles.

protocol NetworkServiceDelegate: AnyObject {
    func networkService(_ service: NetworkService, didFetchData data: Data)
    func networkService(_ service: NetworkService, didFailWithError error: Error)
}

protocol DataFeedDataSource: AnyObject {
    func numberOfItems(in feed: DataFeedController) -> Int
    func dataFeed(_ feed: DataFeedController, itemAt index: Int) -> String
}

protocol ImageLoaderDelegate: AnyObject {
    func imageLoader(_ loader: ImageLoaderService, didLoad image: UIImage)
    func imageLoaderDidStartLoading(_ loader: ImageLoaderService)
}

/// BUG: `delegate` is a strong reference — should be `weak`.
final class NetworkService: @unchecked Sendable {
    var delegate: NetworkServiceDelegate?
    private let session = URLSession.shared

    func fetchData(from url: URL) {
        let task = session.dataTask(with: url) { [self] data, _, error in
            if let error = error {
                delegate?.networkService(self, didFailWithError: error)
            } else if let data = data {
                delegate?.networkService(self, didFetchData: data)
            }
        }
        task.resume()
    }

    func fetchMultipleEndpoints(_ urls: [URL]) {
        for url in urls {
            session.dataTask(with: url) { [self] data, _, _ in
                if let data = data {
                    delegate?.networkService(self, didFetchData: data)
                }
            }.resume()
        }
    }
}

/// BUG: `dataSource` is a strong reference — should be `weak`.
final class DataFeedController: @unchecked Sendable {
    var dataSource: DataFeedDataSource?
    var delegate: NetworkServiceDelegate?

    func reloadData() {
        guard let dataSource = dataSource else { return }
        let count = dataSource.numberOfItems(in: self)
        for i in 0..<count {
            _ = dataSource.dataFeed(self, itemAt: i)
        }
    }
}

/// BUG: `delegate` is a strong reference — should be `weak`.
final class ImageLoaderService: @unchecked Sendable {
    var delegate: ImageLoaderDelegate?

    func loadImage(from url: URL) {
        delegate?.imageLoaderDidStartLoading(self)
        URLSession.shared.dataTask(with: url) { [self] data, _, _ in
            if let data = data, let image = UIImage(data: data) {
                delegate?.imageLoader(self, didLoad: image)
            }
        }.resume()
    }
}

// MARK: - 2. Closure Capture Retain Cycles

/// BUG: Closures stored as properties capture `self` strongly, creating retain cycles.
final class ProfileViewController: UIViewController, NetworkServiceDelegate {
    private let networkService = NetworkService()
    private var completionHandler: (() -> Void)?
    private var onProfileUpdate: ((String) -> Void)?
    private var onError: ((Error) -> Void)?
    private var retryBlock: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()

        // BUG: Setting self as delegate on a strong-delegate object
        networkService.delegate = self

        // BUG: Closure captures `self` strongly, self owns `completionHandler`
        completionHandler = {
            self.updateUI()
            self.loadProfileData()
        }

        // BUG: Another strong self capture in stored closure
        onProfileUpdate = { name in
            self.title = name
            self.view.setNeedsLayout()
        }

        // BUG: Strong capture of self in error handler
        onError = { error in
            self.showError(error)
            self.retryBlock?()
        }

        // BUG: And another — retry captures self strongly
        retryBlock = {
            self.networkService.fetchData(from: URL(string: "https://api.example.com/profile")!)
        }

        // BUG: Multiple notification observers without corresponding removeObserver
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        // BUG: No removeObserver anywhere — observers leak!
    }

    @objc private func handleAppDidBecomeActive() { loadProfileData() }
    @objc private func handleAppWillResignActive() {}
    @objc private func handleKeyboardWillShow() {}
    @objc private func handleKeyboardWillHide() {}

    private func updateUI() {}
    private func loadProfileData() {}
    private func showError(_ error: Error) {}

    // MARK: NetworkServiceDelegate
    nonisolated func networkService(_ service: NetworkService, didFetchData data: Data) {}
    nonisolated func networkService(_ service: NetworkService, didFailWithError error: Error) {}

    // BUG: No deinit — makes retain cycle detection harder during development
}

// MARK: - 3. Timer Retain Cycles

/// BUG: Timer.scheduledTimer(target:) retains its target strongly.
/// When the target (self) also holds the timer, neither can be freed.
final class DashboardViewController: UIViewController {
    private var refreshTimer: Timer?
    private var pollingTimer: Timer?
    private var countdownTimer: Timer?
    private var heartbeatTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()

        // BUG: Timer retains self, self retains refreshTimer → retain cycle
        refreshTimer = Timer.scheduledTimer(
            timeInterval: 5.0,
            target: self,
            selector: #selector(refreshDashboard),
            userInfo: nil,
            repeats: true
        )

        // BUG: Same pattern — another retain cycle
        pollingTimer = Timer.scheduledTimer(
            timeInterval: 30.0,
            target: self,
            selector: #selector(pollForUpdates),
            userInfo: nil,
            repeats: true
        )

        // BUG: Yet another timer retain cycle
        countdownTimer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(updateCountdown),
            userInfo: nil,
            repeats: true
        )

        heartbeatTimer = Timer.scheduledTimer(
            timeInterval: 60.0,
            target: self,
            selector: #selector(sendHeartbeat),
            userInfo: nil,
            repeats: true
        )

        // Additional notification observers without cleanup
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDataRefresh),
            name: Notification.Name("DataDidRefresh"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUserLogout),
            name: Notification.Name("UserDidLogout"),
            object: nil
        )

        // BUG: Timers are never invalidated, observers never removed!
    }

    @objc private func refreshDashboard() {}
    @objc private func pollForUpdates() {}
    @objc private func updateCountdown() {}
    @objc private func sendHeartbeat() {}
    @objc private func handleDataRefresh() {}
    @objc private func handleUserLogout() {}

    // BUG: No deinit to invalidate timers or remove observers
}

// MARK: - 4. Circular References (Coordinator ↔ ViewController)

/// Coordinator strongly retains child VCs; child VCs strongly retain coordinator.
final class AppCoordinator {
    var childCoordinators: [AppCoordinator] = []
    var navigationController: UINavigationController
    var detailVC: DetailViewController?
    var settingsVC: SettingsViewController?

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func showDetail() {
        let vc = DetailViewController()
        // BUG: VC holds a strong reference back to coordinator
        vc.coordinator = self
        detailVC = vc
        navigationController.pushViewController(vc, animated: true)
    }

    func showSettings() {
        let vc = SettingsViewController()
        // BUG: Same — strong back-reference
        vc.coordinator = self
        settingsVC = vc
        navigationController.pushViewController(vc, animated: true)
    }
}

/// Navigation router that creates a similar circular reference problem.
final class NavigationRouter {
    var viewControllers: [UIViewController] = []
    var currentNavigator: NavigationRouter?

    func navigate(to vc: UIViewController) {
        viewControllers.append(vc)
    }
}

final class DetailViewController: UIViewController {
    // BUG: Strong reference back to coordinator → circular reference
    var coordinator: AppCoordinator?

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUpdate),
            name: Notification.Name("DetailDidUpdate"),
            object: nil
        )
    }

    @objc private func handleUpdate() {}
    // BUG: No deinit
}

final class SettingsViewController: UIViewController {
    // BUG: Strong reference back to coordinator → circular reference
    var coordinator: AppCoordinator?

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    // BUG: No deinit
}

// MARK: - 5. Block-Based API Captures

/// Demonstrates strong captures in animation, networking, and GCD blocks.
final class AnimatedViewController: UIViewController {
    private let networkService = NetworkService()
    private var items: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        performAnimations()
        fetchAllData()
        dispatchWork()
    }

    private func performAnimations() {
        // Multiple animation blocks capturing self
        UIView.animate(withDuration: 0.3) {
            self.view.alpha = 1.0
        }
        UIView.animate(withDuration: 0.5, delay: 0.1, options: .curveEaseOut) {
            self.view.transform = .identity
        }
        UIView.animate(withDuration: 0.4) {
            self.view.layoutIfNeeded()
        }
        UIView.animate(withDuration: 0.25) {
            self.view.backgroundColor = .white
        }
    }

    private func fetchAllData() {
        // Network requests capturing self
        let urls = [
            "https://api.example.com/users",
            "https://api.example.com/posts",
            "https://api.example.com/comments",
            "https://api.example.com/likes",
        ].compactMap(URL.init(string:))

        for url in urls {
            URLSession.shared.dataTask(with: url) { [self] data, _, _ in
                if let data = data {
                    processResponse(data)
                }
            }.resume()
        }
    }

    private func dispatchWork() {
        // GCD dispatches capturing self
        DispatchQueue.main.async {
            self.view.setNeedsLayout()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            self.processInBackground()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.refreshUI()
        }
        DispatchQueue.global().async {
            self.items.append("processed")
        }
    }

    private func processResponse(_ data: Data) {}
    private func processInBackground() {}
    private func refreshUI() {}
}

// MARK: - 6. Complex Object Graph (Manager/Service/Store pattern)

/// Multiple interconnected services that hold strong references to each other.
final class UserService: @unchecked Sendable {
    var delegate: NetworkServiceDelegate?
    let analyticsStore = AnalyticsStore()
    let cacheManager = CacheManagerService()
    func fetchUser() {}
}

final class AnalyticsStore: @unchecked Sendable {
    let userService: UserService? = nil
    var events: [String] = []
    func trackEvent(_ name: String) { events.append(name) }
}

final class CacheManagerService: @unchecked Sendable {
    var cache: [String: Data] = [:]
    var delegate: NetworkServiceDelegate?
    func store(_ data: Data, forKey key: String) { cache[key] = data }
}

final class SessionManager: @unchecked Sendable {
    static let shared = SessionManager()
    var userService: UserService?
    var networkService: NetworkService?
    var isLoggedIn = false
}

final class SyncService: @unchecked Sendable {
    var delegate: NetworkServiceDelegate?
    let sessionManager = SessionManager.shared
    func startSync() {}
}

final class EventStore: @unchecked Sendable {
    var events: [String] = []
    var delegate: NetworkServiceDelegate?
    func log(_ event: String) { events.append(event) }
}
