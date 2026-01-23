//
//  SyncManager.swift
//  beemed
//

import Foundation
import Network
import os

enum NetworkState {
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
final class SyncManager {
    private(set) var networkStatus: NetworkState = .offline
    private(set) var lastSuccessPerGoal: [String: Date] = [:]
    private(set) var sendingDatapoints: Set<UUID> = []

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.beemed.networkMonitor")
    private let queueManager: QueueManager
    private var isFlushing = false

    init(queueManager: QueueManager) {
        self.queueManager = queueManager
        startMonitoring()
    }

    deinit {
        monitor.cancel()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let wasOffline = self.networkStatus == .offline
                self.networkStatus = path.status == .satisfied ? .online : .offline

                // Trigger flush when we come back online
                if wasOffline && self.networkStatus == .online {
                    await self.flush()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    var isOnline: Bool {
        networkStatus == .online || networkStatus == .syncing
    }

    func flush() async {
        guard !isFlushing else { return }
        guard !queueManager.queue.isEmpty else { return }

        isFlushing = true
        let previousStatus = networkStatus
        networkStatus = .syncing

        Logger.sync.info("Flushing queue with \(self.queueManager.queue.count) items")

        // Process items sequentially to avoid overwhelming the API
        let itemsToRetry = queueManager.itemsReadyToRetry()
        for item in itemsToRetry {
            await uploadSingleItem(item)
        }

        networkStatus = previousStatus == .syncing ? .online : previousStatus
        isFlushing = false
    }

    private func uploadSingleItem(_ item: QueuedDatapoint) async {
        do {
            try await BeeminderClient.createDatapoint(
                goalSlug: item.goalSlug,
                value: item.value,
                timestamp: item.timestamp,
                comment: item.comment,
                requestid: item.id.uuidString
            )
            Logger.sync.debug("Upload succeeded for \(item.id.uuidString.prefix(8))")
            queueManager.dequeue(id: item.id)
            lastSuccessPerGoal[item.goalSlug] = Date()

        } catch BeeminderClient.APIError.unauthorized {
            Logger.sync.warning("Auth failed for \(item.id.uuidString.prefix(8)) - removing item")
            queueManager.dequeue(id: item.id)

        } catch BeeminderClient.APIError.httpError(let statusCode) where statusCode == 409 {
            // Duplicate requestid - treat as success
            Logger.sync.debug("Duplicate (409) for \(item.id.uuidString.prefix(8))")
            queueManager.dequeue(id: item.id)
            lastSuccessPerGoal[item.goalSlug] = Date()

        } catch BeeminderClient.APIError.httpError(let statusCode) where statusCode == 422 {
            // Validation error - non-retryable, remove from queue
            Logger.sync.warning("Validation error (422) for \(item.id.uuidString.prefix(8)) - removing item")
            queueManager.dequeue(id: item.id)

        } catch BeeminderClient.APIError.httpError(let statusCode) where statusCode >= 500 {
            // Server error - retryable
            Logger.sync.warning("Server error (\(statusCode)) for \(item.id.uuidString.prefix(8)) - will retry")
            queueManager.markAttempt(id: item.id, error: "Server error (HTTP \(statusCode))", httpStatus: statusCode, isRetryable: true)

        } catch {
            // Network or other error - retryable
            Logger.sync.warning("Upload failed for \(item.id.uuidString.prefix(8)): \(error.localizedDescription)")
            queueManager.markAttempt(id: item.id, error: error.localizedDescription, isRetryable: true)
        }
    }

    func submitDatapoint(
        goalSlug: String,
        value: Double,
        timestamp: Date = Date(),
        comment: String? = nil
    ) async -> DatapointState {

        // Always enqueue first for durability
        let datapoint = queueManager.enqueue(
            goalSlug: goalSlug,
            value: value,
            timestamp: timestamp,
            comment: comment
        )

        Logger.sync.debug("Enqueued datapoint for \(goalSlug): value=\(value)")

        // Mark as sending
        sendingDatapoints.insert(datapoint.id)

        // Try immediate upload with inline await
        do {
            try await BeeminderClient.createDatapoint(
                goalSlug: datapoint.goalSlug,
                value: datapoint.value,
                timestamp: datapoint.timestamp,
                comment: datapoint.comment,
                requestid: datapoint.id.uuidString
            )

            // Actual success - remove from queue
            queueManager.dequeue(id: datapoint.id)
            sendingDatapoints.remove(datapoint.id)
            lastSuccessPerGoal[goalSlug] = Date()
            Logger.sync.debug("Immediate upload succeeded for \(goalSlug)")
            return .success(Date())

        } catch BeeminderClient.APIError.unauthorized {
            // Auth failed - remove item, surface error
            queueManager.dequeue(id: datapoint.id)
            sendingDatapoints.remove(datapoint.id)
            Logger.sync.warning("Auth failed for \(goalSlug) - please sign in again")
            return .failed("Please sign in again")

        } catch BeeminderClient.APIError.httpError(let statusCode) where statusCode == 409 {
            // Duplicate - treat as success
            queueManager.dequeue(id: datapoint.id)
            sendingDatapoints.remove(datapoint.id)
            lastSuccessPerGoal[goalSlug] = Date()
            return .success(Date())

        } catch BeeminderClient.APIError.httpError(let statusCode) where statusCode == 422 {
            // Validation error - non-retryable
            queueManager.dequeue(id: datapoint.id)
            sendingDatapoints.remove(datapoint.id)
            return .failed("Validation error")

        } catch {
            // Network/server error - keep in queue for retry
            queueManager.markAttempt(id: datapoint.id, error: error.localizedDescription, isRetryable: true)
            sendingDatapoints.remove(datapoint.id)
            Logger.sync.debug("Upload failed, queued for retry: \(error.localizedDescription)")
            return .queued(queueManager.pendingCount(for: goalSlug))
        }
    }

    func datapointState(for goalSlug: String) -> DatapointState {

        // Check if any datapoint for this goal is currently sending
        let pendingForGoal = queueManager.pendingDatapoints(for: goalSlug)
        if pendingForGoal.contains(where: { sendingDatapoints.contains($0.id) }) {
            return .sending
        }

        // Check for pending items
        let pendingCount = queueManager.pendingCount(for: goalSlug)
        if pendingCount > 0 {
            // Check if there's an error on the most recent attempt
            if let lastError = pendingForGoal.compactMap({ $0.lastError }).last {
                return .failed(lastError)
            }
            return .queued(pendingCount)
        }

        // Check for recent success
        if let lastSuccess = lastSuccessPerGoal[goalSlug] {
            return .success(lastSuccess)
        }

        return .idle
    }
}
