//
//  QueueManager.swift
//  beemed
//

import Foundation

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

    func markAttempt(id: UUID, error: String?) {
        if let index = queue.firstIndex(where: { $0.id == id }) {
            queue[index].recordFailure(error: error ?? "Unknown error")
            saveToDisk()
        }
    }

    func markAuthFailure(id: UUID) {
        // Remove the item - user must re-authenticate
        // Don't spin forever on expired tokens
        queue.removeAll { $0.id == id }
        saveToDisk()
    }

    func cleanupStaleItems() {
        let maxAttempts = 10
        queue.removeAll { $0.attemptCount >= maxAttempts }
        saveToDisk()
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
            print("Failed to load queue: \(error)")
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
            print("Failed to save queue: \(error)")
        }
    }
}
