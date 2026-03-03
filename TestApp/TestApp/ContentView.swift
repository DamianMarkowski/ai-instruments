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

                Section("Energy") {
                    Label("Continuous GPS Tracking", systemImage: "location.fill")
                    Label("Excessive Timers (No Tolerance)", systemImage: "timer")
                    Label("CADisplayLink (No Rate Limit)", systemImage: "display")
                    Label("Background Processing", systemImage: "arrow.clockwise")
                    Label("Motion Sensor Polling", systemImage: "gyroscope")
                }

                Section("Network") {
                    Label("Plaintext HTTP URLs", systemImage: "lock.open")
                    Label("Shared Session Only", systemImage: "network")
                    Label("No Certificate Pinning", systemImage: "shield.slash")
                    Label("WebSocket (No Heartbeat)", systemImage: "bolt.horizontal")
                    Label("Heavy JSON Serialization", systemImage: "doc.text")
                }

                Section("Hangs") {
                    Label("Synchronous File I/O", systemImage: "hourglass")
                    Label("Heavy Sort on Main Thread", systemImage: "arrow.up.arrow.down")
                    Label("Deep View Hierarchy", systemImage: "square.stack.3d.up")
                    Label("No Prefetch / Diffable DS", systemImage: "tablecells")
                    Label("Core Data on Main Thread", systemImage: "cylinder.split.1x2")
                }

                Section("App Launch") {
                    Label("Eager Singleton Init", systemImage: "flag.checkered")
                    Label("Multiple SDK Inits", systemImage: "puzzlepiece.extension")
                    Label("Heavy AppDelegate Work", systemImage: "gearshape.2")
                }

                Section("File Activity") {
                    Label("Sync File Ops", systemImage: "internaldrive")
                    Label("Core Data No Batching", systemImage: "cylinder")
                    Label("SQLite No WAL", systemImage: "tablecells.badge.ellipsis")
                    Label("Temp Files No Cleanup", systemImage: "trash")
                    Label("No File Protection", systemImage: "lock.open.fill")
                }
            }
            .navigationTitle("TestApp Issues")
        }
    }
}

#Preview {
    ContentView()
}
