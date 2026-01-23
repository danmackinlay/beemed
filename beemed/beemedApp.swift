//
//  beemedApp.swift
//  beemed
//
//  Created by Daniel Mackinlay on 22/1/2026.
//

import SwiftUI

@main
struct beemedApp: App {
    @State private var authState: AuthState
    @State private var goalsManager: GoalsManager
    @State private var queueManager: QueueManager
    @State private var syncManager: SyncManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let queue = QueueManager()
        let sync = SyncManager(queueManager: queue)

        _authState = State(initialValue: AuthState())
        _goalsManager = State(initialValue: GoalsManager())
        _queueManager = State(initialValue: queue)
        _syncManager = State(initialValue: sync)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authState.isSignedIn {
                    MainView()
                } else {
                    LoginView()
                }
            }
            .environment(authState)
            .environment(goalsManager)
            .environment(queueManager)
            .environment(syncManager)
            .onAppear {
                // Configure WatchSessionManager for watch communication
                #if os(iOS)
                WatchSessionManager.shared.configure(
                    queueManager: queueManager,
                    syncManager: syncManager
                )
                #endif
            }
            .task {
                // Flush queue on app launch
                await syncManager.flush()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    Task {
                        await syncManager.flush()
                    }
                case .background, .inactive:
                    break
                @unknown default:
                    break
                }
            }
        }
    }
}
