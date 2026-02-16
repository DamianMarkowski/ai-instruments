import SwiftUI
import Foundation

// MARK: - Helper Classes for Demos

final class RaceCounter: @unchecked Sendable {
    var value = 0
}

// MARK: - 1. Non-Sendable Types Demo

struct NonSendableDemoView: View {
    @State private var log: [String] = []

    var body: some View {
        DemoScreen(
            description: "A mutable class (UserProfile) is passed to multiple concurrent tasks without Sendable conformance. Each task mutates the shared object, leading to unpredictable results.",
            log: log,
            onSimulate: simulate
        )
        .navigationTitle("Non-Sendable Types")
    }

    private func simulate() {
        log = ["▶ Creating shared mutable UserProfile..."]
        log.append("  UserProfile is a class — reference type, NOT Sendable")
        log.append("")

        let profile = UserProfile(name: "Alice", email: "alice@example.com")

        log.append("▶ Sending to 5 concurrent tasks that mutate it...")

        Task {
            await withTaskGroup(of: Void.self) { group in
                for i in 1...5 {
                    group.addTask { @Sendable [log] in
                        profile.name = "Task-\(i)"
                        profile.email = "task\(i)@example.com"
                    }
                    _ = log
                }
            }

            log.append("")
            log.append("▶ Final state after concurrent mutations:")
            log.append("  name:  \"\(profile.name)\"")
            log.append("  email: \"\(profile.email)\"")
            log.append("")
            log.append("⚠️ Values are non-deterministic — data race!")
            log.append("  The name might belong to one task,")
            log.append("  the email to another.")
            log.append("")
            log.append("ℹ️ Fix: make UserProfile a struct (value type)")
            log.append("   or conform to Sendable with proper sync")
        }
    }
}

// MARK: - 2. Unprotected Global State Demo

struct UnprotectedStateDemoView: View {
    @State private var log: [String] = []

    var body: some View {
        DemoScreen(
            description: "Multiple threads increment a shared counter simultaneously without synchronization. The read-modify-write operation is not atomic, so increments are lost to data races.",
            log: log,
            onSimulate: simulate
        )
        .navigationTitle("Unprotected Global State")
    }

    private func simulate() {
        let iterations = 5000
        log = ["▶ Incrementing shared counter \(iterations)× from concurrent threads..."]
        log.append("  No lock, no actor, no synchronization")
        log.append("")

        let counter = RaceCounter()
        let group = DispatchGroup()

        for _ in 0..<iterations {
            group.enter()
            DispatchQueue.global().async {
                let current = counter.value
                counter.value = current + 1
                group.leave()
            }
        }

        group.notify(queue: .main) { [self] in
            log.append("▶ Results:")
            log.append("  Expected: \(iterations)")
            log.append("  Actual:   \(counter.value)")
            let lost = iterations - counter.value
            log.append("")
            if lost > 0 {
                log.append("⚠️ DATA RACE: \(lost) increments lost!")
                log.append("  Multiple threads read the same value")
                log.append("  before any had written back.")
            } else {
                log.append("✅ No lost increments this run")
                log.append("  (races are non-deterministic — try again)")
            }
            log.append("")
            log.append("ℹ️ Fix: use an Actor, OSAllocatedUnfairLock,")
            log.append("   or other synchronization primitive")
        }
    }
}

// MARK: - 3. Tasks Without Cancellation Demo

struct TaskNoCancelDemoView: View {
    @State private var log: [String] = []
    @State private var tasks: [Task<Void, Never>] = []

    var body: some View {
        DemoScreen(
            description: "Multiple unstructured Tasks are created without storing handles or checking Task.isCancelled. When the user tries to cancel, the tasks continue running to completion.",
            log: log,
            buttonTitle: tasks.isEmpty ? "Start Tasks" : "Cancel All Tasks"
        ) {
            if tasks.isEmpty {
                startTasks()
            } else {
                cancelTasks()
            }
        }
        .navigationTitle("Tasks Without Cancel")
    }

    private func startTasks() {
        log = ["▶ Creating 6 unstructured tasks..."]
        tasks = []

        for i in 1...6 {
            let t = Task {
                let seconds = Double.random(in: 1...4)
                log.append("  Task \(i) started (will run \(String(format: "%.1f", seconds))s)")
                try? await Task.sleep(for: .seconds(seconds))
                log.append("  ✅ Task \(i) completed (never checked isCancelled)")
            }
            tasks.append(t)
        }

        log.append("")
        log.append("ℹ️ Tap again to attempt cancellation...")
    }

    private func cancelTasks() {
        log.append("")
        log.append("▶ Calling .cancel() on all task handles...")

        for (i, task) in tasks.enumerated() {
            task.cancel()
            log.append("  task[\(i + 1)].cancel() called")
        }

        log.append("")
        log.append("⚠️ Tasks ignore cancellation because they")
        log.append("  never call Task.checkCancellation() or")
        log.append("  check Task.isCancelled.")
        log.append("")
        log.append("ℹ️ Fix: add try Task.checkCancellation()")
        log.append("   inside long-running task bodies")

        tasks = []
    }
}

// MARK: - 4. Detached Tasks Demo

struct DetachedTaskDemoView: View {
    @State private var log: [String] = []

    var body: some View {
        DemoScreen(
            description: "Task.detached creates tasks that don't inherit the parent's priority, task-local values, or actor context. They run completely independently, losing structured concurrency benefits.",
            log: log,
            onSimulate: simulate
        )
        .navigationTitle("Detached Tasks")
    }

    private func simulate() {
        log = ["▶ Creating 4 detached tasks..."]
        log.append("  Parent priority: .userInitiated")
        log.append("")

        Task(priority: .userInitiated) {
            Task.detached {
                let priority = Task.currentPriority
                await MainActor.run {
                    self.log.append("  Detached-1 priority: \(priority) (lost parent's)")
                }
            }
            Task.detached {
                let priority = Task.currentPriority
                await MainActor.run {
                    self.log.append("  Detached-2 priority: \(priority) (lost parent's)")
                }
            }
            Task.detached(priority: .background) {
                let priority = Task.currentPriority
                await MainActor.run {
                    self.log.append("  Detached-3 priority: .background (explicit)")
                    _ = priority
                }
            }
            Task.detached {
                let priority = Task.currentPriority
                await MainActor.run {
                    self.log.append("  Detached-4 priority: \(priority)")
                    self.log.append("")
                    self.log.append("⚠️ Detached tasks:")
                    self.log.append("  • Don't inherit parent priority")
                    self.log.append("  • Don't inherit task-local values")
                    self.log.append("  • Don't propagate cancellation")
                    self.log.append("  • Don't inherit actor isolation")
                    self.log.append("")
                    self.log.append("ℹ️ Fix: prefer Task { } over Task.detached { }")
                }
            }
        }
    }
}

// MARK: - 5. Mixed Concurrency Demo

struct MixedConcurrencyDemoView: View {
    @State private var log: [String] = []

    var body: some View {
        DemoScreen(
            description: "Mixing GCD (DispatchQueue) with Swift Concurrency (async/await) in the same flow. The execution order becomes unpredictable and harder to reason about.",
            log: log,
            onSimulate: simulate
        )
        .navigationTitle("Mixed GCD + async/await")
    }

    private func simulate() {
        log = ["▶ Interleaving GCD and async/await work..."]
        log.append("")

        let startTime = CFAbsoluteTimeGetCurrent()

        DispatchQueue.global().async {
            let elapsed = String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime)
            DispatchQueue.main.async {
                self.log.append("  [\(elapsed)s] GCD global queue - step A")
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let elapsed = String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime)
            self.log.append("  [\(elapsed)s] GCD main queue - step B")
        }

        Task {
            let elapsed = String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime)
            log.append("  [\(elapsed)s] Task (async) - step C")

            try? await Task.sleep(for: .milliseconds(20))
            let elapsed2 = String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime)
            log.append("  [\(elapsed2)s] Task (after sleep) - step D")
        }

        DispatchQueue.global(qos: .background).async {
            let elapsed = String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime)
            DispatchQueue.main.async {
                self.log.append("  [\(elapsed)s] GCD background - step E")
            }
        }

        Task {
            try? await Task.sleep(for: .milliseconds(200))
            log.append("")
            log.append("⚠️ Execution order is non-deterministic!")
            log.append("  GCD and Swift Concurrency use different")
            log.append("  scheduling mechanisms.")
            log.append("")
            log.append("ℹ️ Fix: use one concurrency model consistently.")
            log.append("   Migrate GCD → async/await gradually.")
        }
    }
}

// MARK: - 6. Unsafe Continuation Demo

struct UnsafeContinuationDemoView: View {
    @State private var log: [String] = []

    var body: some View {
        DemoScreen(
            description: "withUnsafeContinuation bridges callback-based APIs to async/await, but provides NO runtime checks. Resuming twice causes undefined behavior; never resuming leaks the task forever.",
            log: log,
            onSimulate: simulate
        )
        .navigationTitle("Unsafe Continuations")
    }

    private func simulate() {
        log = ["▶ Bridging a callback API with unsafe continuation..."]

        Task {
            log.append("  Using withUnsafeContinuation { cont in")
            log.append("    legacyFetch { result in")
            log.append("      cont.resume(returning: result)")
            log.append("    }")
            log.append("  }")
            log.append("")

            let result = await withUnsafeContinuation { (cont: UnsafeContinuation<String, Never>) in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    cont.resume(returning: "{ \"status\": \"ok\" }")
                }
            }

            log.append("  Result: \(result)")
            log.append("")
            log.append("⚠️ withUnsafeContinuation risks:")
            log.append("  • Resume twice → undefined behavior / crash")
            log.append("  • Never resume → task leaks forever")
            log.append("  • No runtime diagnostics in Release builds")
            log.append("")
            log.append("ℹ️ Fix: use withCheckedContinuation instead.")
            log.append("   It traps on misuse during development.")
        }
    }
}
