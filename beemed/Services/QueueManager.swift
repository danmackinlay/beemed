//
//  QueueManager.swift
//  beemed
//

import Foundation
import os

@MainActor
@Observable
final class QueueManager {
    private(set) var queue: [QueuedDatapoint] = []

    private static let fileName = "datapoint_queue.json"

    private static var queueFileURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let appDirectory = appSupport.appendingPathComponent("beemed", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        return appDirectory.appendingPathComponent(fileName)
    }

    init() {
        loadFromDisk()
    }

    func enqueue(goalSlug: String, value: Double, timestamp: Date = Date(), comment: String? = nil) -> QueuedDatapoint {
        let datapoint = QueuedDatapoint(
            goalSlug: goalSlug,
            value: value,
            timestamp: timestamp,
            comment: comment
        )
        queue.append(datapoint)
        saveToDisk()
        return datapoint
    }

    func dequeue(id: UUID) {
        queue.removeAll { $0.id == id }
        saveToDisk()
    }

    /// Batch dequeue multiple items - saves only once at the end
    func dequeueMultiple(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        queue.removeAll { ids.contains($0.id) }
        saveToDisk()
        Logger.persistence.debug("Batch dequeued \(ids.count) items")
    }

    func markAttempt(id: UUID, error: String?, httpStatus: Int? = nil, isRetryable: Bool = true) {
        if let index = queue.firstIndex(where: { $0.id == id }) {
            queue[index].recordFailure(error: error ?? "Unknown error", httpStatus: httpStatus, isRetryable: isRetryable)
            saveToDisk()
        }
    }

    /// Batch result for updating multiple items
    struct BatchResult {
        let id: UUID
        let success: Bool
        let error: String?
        let httpStatus: Int?
        let isRetryable: Bool

        static func success(id: UUID) -> BatchResult {
            BatchResult(id: id, success: true, error: nil, httpStatus: nil, isRetryable: true)
        }

        static func failure(id: UUID, error: String, httpStatus: Int? = nil, isRetryable: Bool = true) -> BatchResult {
            BatchResult(id: id, success: false, error: error, httpStatus: httpStatus, isRetryable: isRetryable)
        }
    }

    /// Batch update multiple items - saves only once at the end
    func applyBatchResults(_ results: [BatchResult]) {
        guard !results.isEmpty else { return }

        var removeIds = Set<UUID>()

        for result in results {
            if result.success {
                removeIds.insert(result.id)
            } else if !result.isRetryable {
                // Non-retryable failures (e.g., auth expired) - remove from queue
                removeIds.insert(result.id)
            } else if let index = queue.firstIndex(where: { $0.id == result.id }) {
                // Retryable failure - record for backoff
                queue[index].recordFailure(
                    error: result.error ?? "Unknown error",
                    httpStatus: result.httpStatus,
                    isRetryable: result.isRetryable
                )
            }
        }

        // Remove successful and non-retryable items
        if !removeIds.isEmpty {
            queue.removeAll { removeIds.contains($0.id) }
        }

        saveToDisk()
        let successCount = results.filter { $0.success }.count
        Logger.persistence.debug("Batch processed \(results.count) items: \(successCount) succeeded, \(removeIds.count - successCount) dropped")
    }

    private let stuckThreshold = 10

    var stuckCount: Int {
        queue.filter { $0.attemptCount >= stuckThreshold }.count
    }

    var stuckItems: [QueuedDatapoint] {
        queue.filter { $0.attemptCount >= stuckThreshold }
    }

    func clearStuckItems() {
        queue.removeAll { $0.attemptCount >= stuckThreshold }
        saveToDisk()
        Logger.persistence.info("Cleared stuck items")
    }

    func itemsReadyToRetry() -> [QueuedDatapoint] {
        queue.filter { $0.isReadyToRetry }
    }

    func pendingCount(for goalSlug: String) -> Int {
        queue.filter { $0.goalSlug == goalSlug }.count
    }

    var totalPendingCount: Int {
        queue.count
    }

    func pendingDatapoints(for goalSlug: String) -> [QueuedDatapoint] {
        queue.filter { $0.goalSlug == goalSlug }
    }

    func clearQueue() {
        queue = []
        if let url = Self.queueFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func loadFromDisk() {
        guard let url = Self.queueFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        do {
            let data = try Data(contentsOf: url)
            queue = try decoder.decode([QueuedDatapoint].self, from: data)
        } catch {
            Logger.persistence.error("Failed to load queue: \(error.localizedDescription)")
        }
    }

    private func saveToDisk() {
        guard let url = Self.queueFileURL else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970

        do {
            let data = try encoder.encode(queue)
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.persistence.error("Failed to save queue: \(error.localizedDescription)")
        }
    }
}
