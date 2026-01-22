//
//  beemedApp.swift
//  beemed
//
//  Created by Daniel Mackinlay on 22/1/2026.
//

import SwiftUI

@main
struct beemedApp: App {
    @State private var authState = AuthState()
    @State private var goalsManager = GoalsManager()
    @State private var queueManager = QueueManager()
    @State private var syncManager = SyncManager()
    @Environment(\.scenePhase) private var scenePhase

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
                // Configure SyncManager with QueueManager
                syncManager.configure(queueManager: queueManager)
            }
            .task {
                // Flush queue on app launch
                await syncManager.flush()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    // Flush queue when app becomes active
                    Task {
                        await syncManager.flush()
                    }
                }
            }
        }
    }
}
