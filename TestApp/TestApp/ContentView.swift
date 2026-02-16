//
//  ContentView.swift
//  TestApp
//
//  Created by Damian Markowski on 14/02/2026.
//

import SwiftUI

// MARK: - Reusable Demo Screen Layout

struct DemoScreen: View {
    let description: String
    let log: [String]
    var buttonTitle: String = "Simulate Issue"
    let onSimulate: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Button(action: onSimulate) {
                    Label(buttonTitle, systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                if !log.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(log.enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(logColor(for: entry))
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func logColor(for text: String) -> Color {
        if text.contains("⚠️") || text.contains("🔴") { return .red }
        if text.contains("✅") || text.contains("🟢") { return .green }
        if text.contains("▶") { return .accentColor }
        if text.contains("ℹ️") { return .orange }
        return .primary
    }
}

// MARK: - Main Navigation

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Memory Leaks") {
                    NavigationLink { StrongDelegateDemoView() } label: {
                        Label("Strong Delegates", systemImage: "link")
                    }
                    NavigationLink { ClosureCaptureDemoView() } label: {
                        Label("Closure Retain Cycles", systemImage: "arrow.triangle.2.circlepath")
                    }
                    NavigationLink { NotificationLeakDemoView() } label: {
                        Label("Notification Observer Leaks", systemImage: "bell.badge")
                    }
                    NavigationLink { TimerRetainCycleDemoView() } label: {
                        Label("Timer Retain Cycles", systemImage: "timer")
                    }
                    NavigationLink { CircularReferenceDemoView() } label: {
                        Label("Circular References", systemImage: "arrow.2.squarepath")
                    }
                }

                Section("Swift Concurrency") {
                    NavigationLink { NonSendableDemoView() } label: {
                        Label("Non-Sendable Types", systemImage: "exclamationmark.shield")
                    }
                    NavigationLink { UnprotectedStateDemoView() } label: {
                        Label("Unprotected Global State", systemImage: "globe")
                    }
                    NavigationLink { TaskNoCancelDemoView() } label: {
                        Label("Tasks Without Cancellation", systemImage: "xmark.circle")
                    }
                    NavigationLink { DetachedTaskDemoView() } label: {
                        Label("Detached Tasks", systemImage: "arrow.up.right.circle")
                    }
                    NavigationLink { MixedConcurrencyDemoView() } label: {
                        Label("Mixed GCD + async/await", systemImage: "shuffle")
                    }
                    NavigationLink { UnsafeContinuationDemoView() } label: {
                        Label("Unsafe Continuations", systemImage: "exclamationmark.triangle")
                    }
                }

                Section("Allocations") {
                    NavigationLink { StrongRefGraphDemoView() } label: {
                        Label("Strong Reference Graph", systemImage: "circle.grid.3x3")
                    }
                    NavigationLink { ImageLoadingDemoView() } label: {
                        Label("Image Loading (No Downsampling)", systemImage: "photo.stack")
                    }
                    NavigationLink { DataBufferDemoView() } label: {
                        Label("Data Buffers", systemImage: "externaldrive")
                    }
                    NavigationLink { CollectionGrowthDemoView() } label: {
                        Label("Collection Growth (No Reserve)", systemImage: "chart.bar")
                    }
                    NavigationLink { StringAllocationDemoView() } label: {
                        Label("String Allocations", systemImage: "textformat")
                    }
                    NavigationLink { FileIODemoView() } label: {
                        Label("File I/O (No Memory Mapping)", systemImage: "doc")
                    }
                }
            }
            .navigationTitle("TestApp Issues")
        }
    }
}

#Preview {
    ContentView()
}
