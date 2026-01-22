//
//  SyncManager.swift
//  beemed
//

import Foundation
import Network

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
        guard networkStatus == .online else { return }
        guard !queueManager.queue.isEmpty else { return }

        isFlushing = true
        networkStatus = .syncing

        // Process items sequentially to avoid overwhelming the API
        for datapoint in queueManager.queue {
            sendingDatapoints.insert(datapoint.id)

            do {
                try await BeeminderClient.createDatapoint(
                    goalSlug: datapoint.goalSlug,
                    value: datapoint.value,
                    timestamp: datapoint.timestamp,
                    comment: datapoint.comment,
                    requestid: datapoint.id.uuidString
                )
                // Success - remove from queue
                queueManager.dequeue(id: datapoint.id)
                lastSuccessPerGoal[datapoint.goalSlug] = Date()
            } catch {
                // Failure - mark attempt and keep in queue
                queueManager.markAttempt(id: datapoint.id, error: error.localizedDescription)
            }

            sendingDatapoints.remove(datapoint.id)
        }

        networkStatus = .online
        isFlushing = false
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

        // If online, try to send immediately
        if isOnline {
            sendingDatapoints.insert(datapoint.id)

            do {
                try await BeeminderClient.createDatapoint(
                    goalSlug: datapoint.goalSlug,
                    value: datapoint.value,
                    timestamp: datapoint.timestamp,
                    comment: datapoint.comment,
                    requestid: datapoint.id.uuidString
                )
                // Success - remove from queue
                queueManager.dequeue(id: datapoint.id)
                sendingDatapoints.remove(datapoint.id)
                lastSuccessPerGoal[goalSlug] = Date()
                return .success(Date())
            } catch {
                // Failed but still queued
                queueManager.markAttempt(id: datapoint.id, error: error.localizedDescription)
                sendingDatapoints.remove(datapoint.id)
                return .queued(queueManager.pendingCount(for: goalSlug))
            }
        } else {
            // Offline - item stays in queue
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
