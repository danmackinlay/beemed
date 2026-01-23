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
    private var backgroundUploader: BackgroundUploader?
    private var isFlushing = false

    init(queueManager: QueueManager) {
        self.queueManager = queueManager
        startMonitoring()
    }

    /// Set the background uploader to use for all uploads
    func setBackgroundUploader(_ uploader: BackgroundUploader) {
        self.backgroundUploader = uploader
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

        guard let uploader = backgroundUploader else {
            Logger.sync.warning("flush() called but no BackgroundUploader configured")
            return
        }

        isFlushing = true
        let previousStatus = networkStatus
        networkStatus = .syncing

        // Delegate all uploads to BackgroundUploader - single sending path
        await uploader.submitPendingUploads()

        networkStatus = previousStatus == .syncing ? .online : previousStatus
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

        Logger.sync.debug("Enqueued datapoint for \(goalSlug): value=\(value)")

        // Mark as sending and trigger uploader
        sendingDatapoints.insert(datapoint.id)

        // Trigger upload via BackgroundUploader
        if let uploader = backgroundUploader {
            await uploader.submitPendingUploads()
        }

        sendingDatapoints.remove(datapoint.id)

        // Check if it was successfully uploaded (no longer in queue)
        if queueManager.queue.first(where: { $0.id == datapoint.id }) == nil {
            lastSuccessPerGoal[goalSlug] = Date()
            return .success(Date())
        }

        // Still in queue (either failed or offline)
        return .queued(queueManager.pendingCount(for: goalSlug))
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
