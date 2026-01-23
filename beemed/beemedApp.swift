//
//  beemedApp.swift
//  beemed
//
//  Created by Daniel Mackinlay on 22/1/2026.
//

import SwiftUI

@main
struct beemedApp: App {
    @State private var appModel = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if appModel.readiness == .cold {
                    ProgressView("Loading...")
                } else if appModel.session.tokenPresent && !appModel.session.needsReauth {
                    MainView()
                } else {
                    LoginView()
                }
            }
            .environment(appModel)
            .onAppear {
                // Configure WatchSessionManager for watch communication
                #if os(iOS)
                WatchSessionManager.shared.configure(appModel: appModel)
                #endif
            }
            .task {
                // Initialize app state on launch
                await appModel.start()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    Task {
                        await appModel.flushQueue()
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
