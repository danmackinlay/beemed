//
//  WatchSessionManager.swift
//  beemed
//

import Foundation
import os

#if canImport(WatchConnectivity)
import WatchConnectivity

/// Manages WatchConnectivity session on iOS side.
/// Sends pinned goals to watch and receives +1 events from watch.
///
/// Two-phase lifecycle:
/// - `activate()` is called from `App.init()` so the WCSession is ready even when
///   iOS launches in the background for WatchConnectivity traffic.
/// - `bind(appModel:)` is called from `.onAppear` once AppModel exists.
/// - When datapoints arrive before `bind()`, they're persisted to `queueStore`
///   and flushed on the next full launch.
@Observable
final class WatchSessionManager: NSObject {
    static let shared = WatchSessionManager()

    private(set) var isWatchAppInstalled: Bool = false
    private(set) var isReachable: Bool = false

    private var session: WCSession?
    private weak var appModel: AppModel?
    /// Fallback persistence: iOS may be woken in the background by WatchConnectivity
    /// before AppModel is initialized — queueStore ensures datapoints aren't dropped.
    private let queueStore = QueueStore()
    private var lastSentData: Data?
    private var pendingData: Data?

    private override init() {
        super.init()
    }

    /// Activate the WCSession early (no AppModel dependency).
    /// Call from app init so background launches can receive messages.
    func activate() {
        guard WCSession.isSupported() else { return }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    /// Bind the AppModel reference once it's ready.
    func bind(appModel: AppModel) {
        self.appModel = appModel
    }

    /// Send pinned goals to the watch via application context.
    /// Buffers the payload when the session isn't ready and flushes later.
    func sendPinnedGoals(_ goals: [Goal]) {
        let summaries = goals.map { goal in
            GoalSummary(slug: goal.slug, title: goal.title, losedate: goal.losedate)
        }

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(summaries) else { return }

        // Skip if identical to last send
        if data == lastSentData { return }

        guard let session, session.activationState == .activated else {
            pendingData = data
            return
        }

        #if os(iOS)
        guard session.isWatchAppInstalled else {
            pendingData = data
            return
        }
        #endif

        do {
            try session.updateApplicationContext(["pinnedGoals": data])
            lastSentData = data
            pendingData = nil
        } catch {
            Logger.watch.error("Failed to send pinned goals to watch: \(error.localizedDescription)")
            pendingData = data
        }
    }

    /// Attempt to send any buffered payload that couldn't be sent earlier.
    private func flushPending() {
        guard let data = pendingData else { return }

        guard let session, session.activationState == .activated else { return }

        #if os(iOS)
        guard session.isWatchAppInstalled else { return }
        #endif

        do {
            try session.updateApplicationContext(["pinnedGoals": data])
            lastSentData = data
            pendingData = nil
        } catch {
            Logger.watch.error("Failed to flush pending goals to watch: \(error.localizedDescription)")
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

            // Flush any buffered goals now that session is active
            self.flushPending()
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

            // Flush any buffered goals when watch state changes
            self.flushPending()
        }
    }
    #endif

    /// Handle pull requests and datapoint submissions from watch
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if message["requestPinnedGoals"] as? Bool == true {
            Task { @MainActor in
                guard let appModel else {
                    replyHandler([:])
                    return
                }

                let summaries = appModel.pinnedGoals.map { goal in
                    GoalSummary(slug: goal.slug, title: goal.title, losedate: goal.losedate)
                }

                let encoder = JSONEncoder()
                if let data = try? encoder.encode(summaries) {
                    replyHandler(["pinnedGoals": data])
                } else {
                    replyHandler([:])
                }
            }
        } else if message["submitDatapoint"] as? Bool == true {
            guard let goalSlug = message["goalSlug"] as? String,
                  let value = message["value"] as? Double else {
                replyHandler(["error": "missing fields"])
                return
            }
            let comment = message["comment"] as? String

            Task { @MainActor in
                if let appModel {
                    _ = await appModel.addDatapoint(goalSlug: goalSlug, value: value, comment: comment)
                } else {
                    let item = QueuedDatapoint(goalSlug: goalSlug, value: value, comment: comment)
                    try? await self.queueStore.enqueue(item)
                }
                replyHandler(["ok": true])
            }
        }
    }

    /// Receive +1 events from watch via transferUserInfo
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let goalSlug = userInfo["goalSlug"] as? String,
              let value = userInfo["value"] as? Double else {
            return
        }

        let comment = userInfo["comment"] as? String

        Task { @MainActor in
            if let appModel {
                _ = await appModel.addDatapoint(goalSlug: goalSlug, value: value, comment: comment)
            } else {
                // No AppModel yet (background launch) — persist to queue for later flush
                let item = QueuedDatapoint(goalSlug: goalSlug, value: value, comment: comment)
                try? await self.queueStore.enqueue(item)
            }
        }
    }
}

#else

// No-op stub for macOS (WatchConnectivity not available)
@Observable
final class WatchSessionManager: NSObject {
    static let shared = WatchSessionManager()

    private(set) var isWatchAppInstalled: Bool = false
    private(set) var isReachable: Bool = false

    private override init() {
        super.init()
    }

    func activate() {}
    func bind(appModel: AppModel) {}
    func sendPinnedGoals(_ goals: [Goal]) {}
}

#endif
