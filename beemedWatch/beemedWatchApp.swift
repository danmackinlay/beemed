//
//  beemedWatchApp.swift
//  beemedWatch
//

import SwiftUI
import WatchConnectivity

@main
struct beemedWatchApp: App {
    @State private var watchState = WatchState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(watchState)
        }
    }
}

/// Observable state for watch app, manages WCSession and received goals
@Observable
final class WatchState: NSObject {
    var goals: [WatchGoal] = []
    var isConnected: Bool = false
    var lastSentGoal: String?
    var showingConfirmation: Bool = false

    private var session: WCSession?

    override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        guard WCSession.isSupported() else { return }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    /// Send +1 event to iPhone
    func sendPlusOne(goalSlug: String, value: Double = 1.0, comment: String? = nil) {
        guard let session, session.activationState == .activated else { return }

        var userInfo: [String: Any] = [
            "goalSlug": goalSlug,
            "value": value
        ]
        if let comment {
            userInfo["comment"] = comment
        }

        session.transferUserInfo(userInfo)

        // Show confirmation
        lastSentGoal = goalSlug
        showingConfirmation = true

        // Auto-hide confirmation
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if lastSentGoal == goalSlug {
                showingConfirmation = false
            }
        }
    }
}

extension WatchState: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("WCSession activation failed: \(error)")
            return
        }

        Task { @MainActor in
            self.isConnected = activationState == .activated

            // Load any existing context
            if let data = session.receivedApplicationContext["pinnedGoals"] as? Data {
                self.decodeGoals(from: data)
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["pinnedGoals"] as? Data else { return }

        Task { @MainActor in
            self.decodeGoals(from: data)
        }
    }

    private func decodeGoals(from data: Data) {
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([WatchGoal].self, from: data) {
            self.goals = decoded
        }
    }
}

/// Lightweight goal structure for watch communication
struct WatchGoal: Identifiable, Codable {
    let slug: String
    let title: String
    let losedate: Int

    var id: String { slug }

    var urgencyColor: Color {
        let timeToDerail = Date(timeIntervalSince1970: TimeInterval(losedate)).timeIntervalSinceNow
        let hours = timeToDerail / 3600
        if hours < 24 { return .red }
        if hours < 72 { return .orange }
        return .yellow
    }
}
