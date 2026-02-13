import SwiftUI

@main
struct AppPerformanceDiagnosticsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 750)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Analysis") {
                Button("New Analysis...") {
                    NotificationCenter.default.post(
                        name: .newAnalysisRequested,
                        object: nil
                    )
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let newAnalysisRequested = Notification.Name("newAnalysisRequested")
}
