//
//  WatchSessionManager.swift
//  beemed
//

import Foundation
import os
import WatchConnectivity

/// Manages WatchConnectivity session on iOS side.
/// Sends pinned goals to watch and receives +1 events from watch.
@Observable
final class WatchSessionManager: NSObject {
    static let shared = WatchSessionManager()

    private(set) var isWatchAppInstalled: Bool = false
    private(set) var isReachable: Bool = false

    private var session: WCSession?
    private weak var appModel: AppModel?

    private override init() {
        super.init()
    }

    func configure(appModel: AppModel) {
        self.appModel = appModel

        guard WCSession.isSupported() else { return }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    /// Send pinned goals to the watch via application context
    func sendPinnedGoals(_ goals: [Goal]) {
        guard let session, session.activationState == .activated else { return }

        #if os(iOS)
        guard session.isWatchAppInstalled else { return }
        #endif

        let watchGoals = goals.map { goal in
            WatchGoal(slug: goal.slug, title: goal.title, losedate: goal.losedate)
        }

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(watchGoals) else { return }

        do {
            try session.updateApplicationContext(["pinnedGoals": data])
        } catch {
            Logger.watch.error("Failed to send pinned goals to watch: \(error.localizedDescription)")
        }
    }
}

extension WatchSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            Logger.watch.error("WCSession activation failed: \(error.localizedDescription)")
            return
        }

        Task { @MainActor in
            #if os(iOS)
            self.isWatchAppInstalled = session.isWatchAppInstalled
            #endif
            self.isReachable = session.isReachable
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate session after switching watches
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isReachable = session.isReachable
        }
    }
    #endif

    /// Receive +1 events from watch via transferUserInfo
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let goalSlug = userInfo["goalSlug"] as? String,
              let value = userInfo["value"] as? Double else {
            return
        }

        let comment = userInfo["comment"] as? String

        Task { @MainActor in
            guard let appModel else { return }

            // Submit datapoint using AppModel
            _ = await appModel.addDatapoint(
                goalSlug: goalSlug,
                value: value,
                comment: comment
            )
        }
    }
}
