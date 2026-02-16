import SwiftUI
import UIKit

// MARK: - Helper Classes for Demos

final class DemoNetworkClient: NetworkServiceDelegate {
    var service: NetworkService?
    nonisolated func networkService(_ service: NetworkService, didFetchData data: Data) {}
    nonisolated func networkService(_ service: NetworkService, didFailWithError error: Error) {}
}

final class ClosureCycleOwner {
    var name: String
    var onComplete: (() -> Void)?

    init(name: String) { self.name = name }
}

final class TimerDemoOwner: NSObject, @unchecked Sendable {
    var timer: Timer?
    var fireCount = 0

    func startTimer() {
        timer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
    }

    @objc func timerFired() {
        fireCount += 1
    }
}

final class ParentNode {
    var child: ChildNode?
    let label: String
    init(label: String) { self.label = label }
}

final class ChildNode {
    var parent: ParentNode?
    let label: String
    init(label: String) { self.label = label }
}

// MARK: - 1. Strong Delegate Demo

struct StrongDelegateDemoView: View {
    @State private var log: [String] = []

    var body: some View {
        DemoScreen(
            description: "NetworkService.delegate is declared as a strong var instead of weak. When the delegate also holds a reference to the service, a retain cycle forms and neither object can be freed.",
            log: log,
            onSimulate: simulate
        )
        .navigationTitle("Strong Delegates")
    }

    private func simulate() {
        log = ["▶ Creating NetworkService and DemoNetworkClient..."]

        weak var weakService: NetworkService?
        weak var weakClient: DemoNetworkClient?

        do {
            let service = NetworkService()
            let client = DemoNetworkClient()

            service.delegate = client
            client.service = service

            weakService = service
            weakClient = client

            log.append("  service.delegate = client  (strong ⚠️)")
            log.append("  client.service  = service  (strong ⚠️)")
        }

        log.append("")
        log.append("▶ Local references released. Checking weak refs...")

        if weakService != nil {
            log.append("⚠️ NetworkService was NOT deallocated")
        } else {
            log.append("✅ NetworkService was deallocated")
        }
        if weakClient != nil {
            log.append("⚠️ DemoNetworkClient was NOT deallocated")
        } else {
            log.append("✅ DemoNetworkClient was deallocated")
        }

        if weakService != nil && weakClient != nil {
            log.append("")
            log.append("🔴 RETAIN CYCLE DETECTED")
            log.append("  Service ──strong──▶ Client")
            log.append("  Client  ──strong──▶ Service")
            log.append("")
            log.append("ℹ️ Fix: declare delegate as `weak var`")
        }
    }
}

// MARK: - 2. Closure Capture Demo

struct ClosureCaptureDemoView: View {
    @State private var log: [String] = []

    var body: some View {
        DemoScreen(
            description: "A closure stored as a property captures self strongly. Since self also owns the closure, a retain cycle forms — neither the object nor the closure can be freed.",
            log: log,
            onSimulate: simulate
        )
        .navigationTitle("Closure Retain Cycles")
    }

    private func simulate() {
        log = ["▶ Creating ClosureCycleOwner..."]

        weak var weakOwner: ClosureCycleOwner?

        do {
            let owner = ClosureCycleOwner(name: "LeakyObject")

            owner.onComplete = {
                _ = owner.name
            }

            weakOwner = owner

            log.append("  owner.onComplete = { _ = owner.name }")
            log.append("  Closure captures owner strongly")
            log.append("  Owner retains closure via .onComplete")
        }

        log.append("")
        log.append("▶ Local reference released. Checking...")

        if weakOwner != nil {
            log.append("⚠️ ClosureCycleOwner was NOT deallocated")
            log.append("")
            log.append("🔴 RETAIN CYCLE DETECTED")
            log.append("  Owner ──strong──▶ Closure (.onComplete)")
            log.append("  Closure ──strong──▶ Owner (captured)")
            log.append("")
            log.append("ℹ️ Fix: use [weak self] in closure")
        } else {
            log.append("✅ ClosureCycleOwner was deallocated")
        }
    }
}

// MARK: - 3. Notification Observer Leak Demo

struct NotificationLeakDemoView: View {
    @State private var log: [String] = []
    @State private var totalObservers = 0

    var body: some View {
        DemoScreen(
            description: "NotificationCenter.addObserver is called multiple times without a corresponding removeObserver. Each tap adds more observers that are never cleaned up, leaking memory and potentially causing duplicate handling.",
            log: log,
            buttonTitle: "Add Observers (Leak)",
            onSimulate: simulate
        )
        .navigationTitle("Notification Leaks")
    }

    private func simulate() {
        if log.isEmpty {
            log.append("▶ Registering notification observers...")
        }

        let names: [Notification.Name] = [
            UIApplication.didBecomeActiveNotification,
            UIApplication.willResignActiveNotification,
            UIResponder.keyboardWillShowNotification,
        ]

        let object = NSObject()
        for name in names {
            NotificationCenter.default.addObserver(
                object,
                selector: NSSelectorFromString("description"),
                name: name,
                object: nil
            )
            totalObservers += 1
        }

        log.append("  +3 observers added (total: \(totalObservers))")

        if totalObservers >= 6 {
            log.append("")
            log.append("⚠️ \(totalObservers) observers registered, 0 removed")
            log.append("🔴 Observer imbalance — leak grows each tap!")
            log.append("")
            log.append("ℹ️ Fix: call removeObserver in deinit")
        }
    }
}

// MARK: - 4. Timer Retain Cycle Demo

struct TimerRetainCycleDemoView: View {
    @State private var log: [String] = []

    var body: some View {
        DemoScreen(
            description: "Timer.scheduledTimer(target:) retains its target. When the target also stores the Timer, a retain cycle forms. The timer keeps firing forever because neither object is deallocated.",
            log: log,
            onSimulate: simulate
        )
        .navigationTitle("Timer Retain Cycles")
    }

    private func simulate() {
        log = ["▶ Creating TimerDemoOwner with repeating timer..."]

        let owner = TimerDemoOwner()
        owner.startTimer()

        log.append("  Timer.scheduledTimer(target: self)")
        log.append("  owner.timer = timer  (strong)")
        log.append("  Timer → target = owner (strong)")
        log.append("")
        log.append("▶ Releasing local reference to owner...")

        Task { [weak owner] in
            try? await Task.sleep(for: .seconds(0.5))

            if owner != nil {
                log.append("⚠️ Owner NOT deallocated — Timer retains it")
                log.append("")
                log.append("▶ Timer keeps firing (watch below):")
            }

            for _ in 1...8 {
                try? await Task.sleep(for: .seconds(1))
                if let owner {
                    log.append("  🔴 Timer fired! (count: \(owner.fireCount))")
                } else {
                    log.append("  ✅ Owner was freed, timer stopped")
                    break
                }
            }

            if owner != nil {
                log.append("")
                log.append("🔴 Timer will fire FOREVER")
                log.append("ℹ️ Fix: invalidate timer in deinit/viewWillDisappear")
            }
        }
    }
}

// MARK: - 5. Circular Reference Demo

struct CircularReferenceDemoView: View {
    @State private var log: [String] = []

    var body: some View {
        DemoScreen(
            description: "Parent holds a strong reference to Child, and Child holds a strong reference back to Parent. When external references are released, neither object can reach a zero reference count.",
            log: log,
            onSimulate: simulate
        )
        .navigationTitle("Circular References")
    }

    private func simulate() {
        log = ["▶ Creating Parent ↔ Child object pairs..."]

        var leakedPairs = 0
        var freedPairs = 0

        for i in 1...4 {
            weak var weakParent: ParentNode?
            weak var weakChild: ChildNode?

            do {
                let parent = ParentNode(label: "Parent-\(i)")
                let child = ChildNode(label: "Child-\(i)")

                parent.child = child
                child.parent = parent

                weakParent = parent
                weakChild = child
            }

            let parentLeaked = weakParent != nil
            let childLeaked = weakChild != nil

            if parentLeaked || childLeaked {
                leakedPairs += 1
                log.append("  Pair \(i): ⚠️ LEAKED (parent: \(parentLeaked), child: \(childLeaked))")
            } else {
                freedPairs += 1
                log.append("  Pair \(i): ✅ Freed")
            }
        }

        log.append("")
        log.append("▶ Results: \(leakedPairs) leaked, \(freedPairs) freed")

        if leakedPairs > 0 {
            log.append("")
            log.append("🔴 CIRCULAR REFERENCES DETECTED")
            log.append("  Parent ──strong──▶ Child  (.child)")
            log.append("  Child  ──strong──▶ Parent (.parent)")
            log.append("")
            log.append("ℹ️ Fix: declare child.parent as `weak var`")
        }
    }
}
