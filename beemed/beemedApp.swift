//
//  beemedApp.swift
//  beemed
//
//  Created by Daniel Mackinlay on 22/1/2026.
//

import SwiftUI
#if os(iOS)
import BackgroundTasks
#endif

@main
struct beemedApp: App {
    @State private var authState: AuthState
    @State private var goalsManager: GoalsManager
    @State private var queueManager: QueueManager
    @State private var syncManager: SyncManager
    @State private var backgroundUploader: BackgroundUploader
    #if os(iOS)
    @State private var backgroundScheduler: BackgroundSyncScheduler
    #endif
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let queue = QueueManager()
        let uploader = BackgroundUploader(queueManager: queue)

        _authState = State(initialValue: AuthState())
        _goalsManager = State(initialValue: GoalsManager())
        _queueManager = State(initialValue: queue)
        _syncManager = State(initialValue: SyncManager(queueManager: queue))
        _backgroundUploader = State(initialValue: uploader)

        #if os(iOS)
        let scheduler = BackgroundSyncScheduler(queueManager: queue, backgroundUploader: uploader)
        _backgroundScheduler = State(initialValue: scheduler)

        // Register background tasks BEFORE app finishes launching
        BackgroundSyncScheduler.registerTasks { task in
            Task { @MainActor in
                scheduler.handleTask(task)
            }
        }
        #endif
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
                    #if os(iOS)
                    backgroundScheduler.cancelAllTasks()
                    #endif
                    Task {
                        await syncManager.flush()
                    }
                case .background:
                    #if os(iOS)
                    backgroundScheduler.scheduleRefreshTask()
                    backgroundScheduler.scheduleProcessingTask()
                    #endif
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
        }
    }
}
