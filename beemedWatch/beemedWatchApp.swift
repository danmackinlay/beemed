//
//  beemedWatchApp.swift
//  beemedWatch
//

import os
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
    var goals: [GoalSummary] = []
    var isConnected: Bool = false
    var lastSentGoal: String?
    var showingConfirmation: Bool = false

    private var session: WCSession?

    private static let pinnedGoalsKey = "pinnedGoalsData"

    override init() {
        super.init()

        // Load cached goals before session setup so UI never flashes empty
        if let cached = UserDefaults.standard.data(forKey: Self.pinnedGoalsKey) {
            decodeGoals(from: cached, persist: false)
        }

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
            Logger.watch.error("WCSession activation failed: \(error.localizedDescription)")
            return
        }

        Task { @MainActor in
            self.isConnected = activationState == .activated

            // Load any existing context
            if let data = session.receivedApplicationContext["pinnedGoals"] as? Data {
                self.decodeGoals(from: data)
            }

            // If still empty, try pulling from iPhone
            if self.goals.isEmpty {
                self.requestPinnedGoals()
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["pinnedGoals"] as? Data else { return }

        Task { @MainActor in
            self.decodeGoals(from: data)
        }
    }

    private func decodeGoals(from data: Data, persist: Bool = true) {
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([GoalSummary].self, from: data) {
            self.goals = decoded
            if persist {
                UserDefaults.standard.set(data, forKey: Self.pinnedGoalsKey)
            }
        }
    }

    /// Ask iPhone for current pinned goals (best-effort, requires reachability)
    func requestPinnedGoals() {
        guard let session, session.activationState == .activated, session.isReachable else { return }

        session.sendMessage(["requestPinnedGoals": true], replyHandler: { response in
            guard let data = response["pinnedGoals"] as? Data else { return }
            Task { @MainActor in
                self.decodeGoals(from: data)
            }
        }, errorHandler: { error in
            Logger.watch.error("Failed to request pinned goals: \(error.localizedDescription)")
        })
    }
}

// MARK: - GoalSummary Extensions

extension GoalSummary {
    var urgencyColor: Color {
        switch GoalUrgency(losedate: losedate) {
        case .critical: return .red
        case .warning: return .orange
        case .safe: return .yellow
        }
    }
}
