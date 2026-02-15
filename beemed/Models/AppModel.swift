//
//  AppModel.swift
//  beemed
//

import Foundation
import Network
import os

enum NetworkState: Equatable {
    case online
    case offline
    case syncing
}

enum DatapointState: Equatable {
    case idle
    case sending
    case success(Date)
    case queued(Int)
    case failed(String)
}

@MainActor
@Observable
final class AppModel {
    // MARK: - Session State

    struct SessionState: Equatable {
        var tokenPresent: Bool = false
        var needsReauth: Bool = false
        var username: String = ""
        var isLoading: Bool = false
        var error: String?
    }

    // MARK: - Goals State

    struct GoalsState: Equatable {
        var goals: [Goal] = []
        var pinned: Set<String> = []
        var lastRefresh: Date?
        var isLoading: Bool = false
        var error: String?
    }

    // MARK: - Queue State

    struct QueueState: Equatable {
        var queuedCount: Int = 0
        var isFlushing: Bool = false
    }

    // MARK: - Readiness

    enum Readiness: Equatable { case cold, loaded }

    // MARK: - Published State

    var readiness: Readiness = .cold
    var session = SessionState()
    var goals = GoalsState()
    var queue = QueueState()
    var networkStatus: NetworkState {
        if !pathSatisfied { return .offline }
        if queue.isFlushing { return .syncing }
        return .online
    }

    // Track success per goal for UI feedback
    private(set) var lastSuccessPerGoal: [String: Date] = [:]
    private(set) var pendingCountByGoal: [String: Int] = [:]

    // MARK: - Dependencies

    private let api: any BeeminderAPI
    private let tokenStore: any TokenStore
    private let queueStore: any QueueStoreProtocol
    private let goalsStore: any GoalsStoreProtocol

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.beemed.networkMonitor")

    /// Tracks actual network path status (networkStatus is derived from this + queue.isFlushing)
    private var pathSatisfied: Bool = false

    private let usernameKey = "beeminder_username"

    // MARK: - Init

    init(
        api: (any BeeminderAPI)? = nil,
        tokenStore: (any TokenStore)? = nil,
        queueStore: (any QueueStoreProtocol)? = nil,
        goalsStore: (any GoalsStoreProtocol)? = nil
    ) {
        self.api = api ?? LiveBeeminderAPI()
        self.tokenStore = tokenStore ?? KeychainTokenStore()
        self.queueStore = queueStore ?? QueueStore()
        self.goalsStore = goalsStore ?? GoalsStore()

        startNetworkMonitoring()
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Startup

    func start() async {
        // Hydrate stores from disk first (async I/O)
        await goalsStore.hydrate()
        await queueStore.hydrate()

        // Load token state
        let token = await tokenStore.load()
        session.tokenPresent = token != nil
        session.username = UserDefaults.standard.string(forKey: usernameKey) ?? ""

        // Load goals from disk
        do {
            let snapshot = try await goalsStore.load()
            goals.goals = snapshot.goals
            goals.pinned = snapshot.pinned
            goals.lastRefresh = snapshot.lastRefresh
        } catch {
            Logger.persistence.error("Failed to load goals: \(error.localizedDescription)")
        }

        // Load queue state
        await refreshQueueState()

        readiness = .loaded

        // Flush queue if we have pending items
        if queue.queuedCount > 0 {
            await flushQueue()
        }
    }

    // MARK: - Auth Operations

    func signIn() async {
        session.isLoading = true
        session.error = nil

        do {
            let result = try await AuthService.signIn()

            // Save token
            try await tokenStore.save(result.accessToken)
            UserDefaults.standard.set(result.username, forKey: usernameKey)

            session.tokenPresent = true
            session.username = result.username
            session.needsReauth = false

            // Flush queue after successful reauth
            await flushQueue()
        } catch {
            session.error = error.localizedDescription
        }

        session.isLoading = false
    }

    func signOut() async {
        do {
            try await tokenStore.clear()
        } catch {
            Logger.auth.error("Failed to clear token: \(error.localizedDescription)")
        }

        UserDefaults.standard.removeObject(forKey: usernameKey)

        // Clear queue and goals
        do {
            try await queueStore.clearAll()
            try await goalsStore.clear()
        } catch {
            Logger.persistence.error("Failed to clear data on sign out: \(error.localizedDescription)")
        }

        session = SessionState()
        goals = GoalsState()
        queue = QueueState()
        lastSuccessPerGoal = [:]
    }

    // MARK: - Goals Operations

    func refreshGoalsIfStale(staleAfter: TimeInterval = 300) async {
        guard session.tokenPresent, !session.needsReauth else { return }
        if let last = goals.lastRefresh, Date().timeIntervalSince(last) < staleAfter {
            return
        }
        await refreshGoals()
    }

    func refreshGoals() async {
        guard let token = await tokenStore.load() else {
            session.needsReauth = true
            return
        }

        goals.isLoading = true
        goals.error = nil

        do {
            let fetchedGoals = try await api.fetchGoals(token: token)
            let sorted = fetchedGoals.sorted { $0.updatedAt > $1.updatedAt }

            try await goalsStore.saveGoals(sorted, at: Date())

            goals.goals = sorted
            goals.lastRefresh = Date()
        } catch let error as APIError where error == .unauthorized {
            session.needsReauth = true
            goals.error = "Please sign in again"
        } catch {
            goals.error = error.localizedDescription
        }

        goals.isLoading = false
    }

    func setPinned(_ newPinned: Set<String>) async {
        goals.pinned = newPinned
        do {
            try await goalsStore.savePinned(newPinned)
        } catch {
            Logger.persistence.error("Failed to save pinned goals: \(error.localizedDescription)")
        }
    }

    var pinnedGoals: [Goal] {
        goals.goals.filter { goals.pinned.contains($0.slug) }
    }

    // MARK: - Datapoint Operations

    func addDatapoint(
        goalSlug: String,
        value: Double,
        timestamp: Date = Date(),
        comment: String? = nil
    ) async -> DatapointState {
        guard let token = await tokenStore.load() else {
            session.needsReauth = true
            return .failed("Please sign in again")
        }

        // Create and enqueue datapoint for durability
        let datapoint = QueuedDatapoint(
            goalSlug: goalSlug,
            value: value,
            timestamp: timestamp,
            comment: comment
        )

        do {
            try await queueStore.enqueue(datapoint)
        } catch {
            Logger.persistence.error("Failed to enqueue datapoint: \(error.localizedDescription)")
            return .failed("Failed to save")
        }

        await refreshQueueState()

        // If we need reauth, don't try uploading - keep in queue
        if session.needsReauth {
            return .queued(pendingCountByGoal[goalSlug] ?? 1)
        }

        // Skip upload attempt if offline - item stays in queue with attemptCount=0
        guard pathSatisfied else {
            Logger.sync.debug("Offline - queued datapoint for \(goalSlug) without upload attempt")
            return .queued(pendingCountByGoal[goalSlug] ?? 1)
        }

        Logger.sync.debug("Enqueued datapoint for \(goalSlug): value=\(value)")

        // Try immediate upload
        let request = CreateDatapointRequest(
            goalSlug: goalSlug,
            value: value,
            timestamp: timestamp,
            comment: comment,
            requestid: datapoint.id.uuidString
        )

        do {
            try await api.createDatapoint(token: token, request: request)

            // Success - remove from queue
            try await queueStore.remove(datapoint.id)
            await refreshQueueState()
            lastSuccessPerGoal[goalSlug] = Date()
            Logger.sync.debug("Immediate upload succeeded for \(goalSlug)")
            return .success(Date())

        } catch let error as APIError {
            switch error {
            case .unauthorized:
                // Keep item in queue for retry after reauth
                session.needsReauth = true
                try? await queueStore.markAttempt(
                    datapoint.id,
                    error: .retryable("Auth required - will retry after sign-in")
                )
                await refreshQueueState()
                Logger.sync.warning("Auth failed for \(goalSlug) - keeping item for retry")
                return .queued(pendingCountByGoal[goalSlug] ?? 1)

            case .httpError(let statusCode) where statusCode == 409:
                // Duplicate - treat as success
                try? await queueStore.remove(datapoint.id)
                await refreshQueueState()
                lastSuccessPerGoal[goalSlug] = Date()
                return .success(Date())

            case .httpError(let statusCode) where statusCode == 422:
                // Validation error - non-retryable
                try? await queueStore.remove(datapoint.id)
                await refreshQueueState()
                return .failed("Validation error")

            default:
                // Network/server error - keep in queue for retry
                try? await queueStore.markAttempt(
                    datapoint.id,
                    error: .retryable(error.localizedDescription)
                )
                await refreshQueueState()
                Logger.sync.debug("Upload failed, queued for retry: \(error.localizedDescription)")
                return .queued(pendingCountByGoal[goalSlug] ?? 1)
            }

        } catch {
            try? await queueStore.markAttempt(
                datapoint.id,
                error: .retryable(error.localizedDescription)
            )
            await refreshQueueState()
            Logger.sync.debug("Upload failed, queued for retry: \(error.localizedDescription)")
            return .queued(pendingCountByGoal[goalSlug] ?? 1)
        }
    }

    // MARK: - Queue Operations

    func flushQueue() async {
        guard pathSatisfied else { return }
        guard !queue.isFlushing else { return }
        guard queue.queuedCount > 0 else { return }
        guard !session.needsReauth else { return }

        guard let token = await tokenStore.load() else {
            session.needsReauth = true
            return
        }

        queue.isFlushing = true

        Logger.sync.info("Flushing queue with \(self.queue.queuedCount) items")

        do {
            let itemsToRetry = try await queueStore.itemsReadyToRetry()
            for item in itemsToRetry {
                await uploadSingleItem(item, token: token)
            }
        } catch {
            Logger.sync.error("Failed to get items to retry: \(error.localizedDescription)")
        }

        await refreshQueueState()
        queue.isFlushing = false
    }

    private func uploadSingleItem(_ item: QueuedDatapoint, token: String) async {
        let request = CreateDatapointRequest(
            goalSlug: item.goalSlug,
            value: item.value,
            timestamp: item.timestamp,
            comment: item.comment,
            requestid: item.id.uuidString
        )

        do {
            try await api.createDatapoint(token: token, request: request)
            Logger.sync.debug("Upload succeeded for \(item.id.uuidString.prefix(8))")
            try await queueStore.remove(item.id)
            lastSuccessPerGoal[item.goalSlug] = Date()

        } catch let error as APIError {
            switch error {
            case .unauthorized:
                // Keep item in queue for retry after reauth
                Logger.sync.warning("Auth failed for \(item.id.uuidString.prefix(8)) - keeping for retry")
                session.needsReauth = true
                try? await queueStore.markAttempt(
                    item.id,
                    error: .retryable("Auth required - will retry after sign-in")
                )

            case .httpError(let statusCode) where statusCode == 409:
                // Duplicate - treat as success
                Logger.sync.debug("Duplicate (409) for \(item.id.uuidString.prefix(8))")
                try? await queueStore.remove(item.id)
                lastSuccessPerGoal[item.goalSlug] = Date()

            case .httpError(let statusCode) where statusCode == 422:
                // Validation error - non-retryable
                Logger.sync.warning("Validation error (422) for \(item.id.uuidString.prefix(8)) - removing item")
                try? await queueStore.remove(item.id)

            case .httpError(let statusCode) where statusCode >= 500:
                Logger.sync.warning("Server error (\(statusCode)) for \(item.id.uuidString.prefix(8)) - will retry")
                try? await queueStore.markAttempt(
                    item.id,
                    error: .retryable("Server error (HTTP \(statusCode))", status: statusCode)
                )

            default:
                Logger.sync.warning("Upload failed for \(item.id.uuidString.prefix(8)): \(error.localizedDescription)")
                try? await queueStore.markAttempt(
                    item.id,
                    error: .retryable(error.localizedDescription)
                )
            }

        } catch {
            Logger.sync.warning("Upload failed for \(item.id.uuidString.prefix(8)): \(error.localizedDescription)")
            try? await queueStore.markAttempt(
                item.id,
                error: .retryable(error.localizedDescription)
            )
        }
    }

    /// Synchronous datapoint state computed from observable properties.
    /// Use this for UI binding.
    func datapointStateFor(_ goalSlug: String) -> DatapointState {
        // Check for pending items
        let pendingCount = pendingCountByGoal[goalSlug] ?? 0
        if pendingCount > 0 {
            return .queued(pendingCount)
        }

        // Check for recent success
        if let lastSuccess = lastSuccessPerGoal[goalSlug] {
            return .success(lastSuccess)
        }

        return .idle
    }

    // MARK: - Private Helpers

    private func refreshQueueState() async {
        do {
            let snapshot = try await queueStore.loadSnapshot()
            queue.queuedCount = snapshot.items.count

            // Compute per-goal pending counts
            var counts: [String: Int] = [:]
            for item in snapshot.items {
                counts[item.goalSlug, default: 0] += 1
            }
            pendingCountByGoal = counts
        } catch {
            Logger.persistence.error("Failed to refresh queue state: \(error.localizedDescription)")
        }
    }

    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let nowOnline = path.status == .satisfied
                let wasOffline = !self.pathSatisfied

                self.pathSatisfied = nowOnline

                // Trigger flush when we come back online
                if wasOffline && nowOnline {
                    await self.flushQueue()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    var isOnline: Bool {
        networkStatus == .online || networkStatus == .syncing
    }
}
