//
//  QueueStore.swift
//  beemed
//

import Foundation
import os

actor QueueStore: QueueStoreProtocol {
    private var queue: [QueuedDatapoint] = []
    private let stuckThreshold = 10

    private static let fileName = "datapoint_queue.json"

    private static var queueFileURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let appDirectory = appSupport.appendingPathComponent("beemed", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        return appDirectory.appendingPathComponent(fileName)
    }

    init() {
        loadFromDisk()
    }

    func loadSnapshot() async throws -> QueueSnapshot {
        QueueSnapshot(items: queue)
    }

    func enqueue(_ item: QueuedDatapoint) async throws {
        queue.append(item)
        saveToDisk()
    }

    func markAttempt(_ id: UUID, error: UploadError) async throws {
        if let index = queue.firstIndex(where: { $0.id == id }) {
            var item = queue[index]
            item.recordFailure(
                error: error.message,
                httpStatus: error.httpStatus,
                isRetryable: error.isRetryable
            )
            queue[index] = item
            saveToDisk()
        }
    }

    func remove(_ id: UUID) async throws {
        queue.removeAll { $0.id == id }
        saveToDisk()
    }

    func removeMultiple(_ ids: Set<UUID>) async throws {
        guard !ids.isEmpty else { return }
        queue.removeAll { ids.contains($0.id) }
        saveToDisk()
        Logger.persistence.debug("Batch removed \(ids.count) items from queue")
    }

    func allPending(oldestFirst: Bool) async throws -> [QueuedDatapoint] {
        if oldestFirst {
            return queue.sorted { $0.createdAt < $1.createdAt }
        }
        return queue
    }

    func itemsReadyToRetry() async throws -> [QueuedDatapoint] {
        queue.filter { $0.isReadyToRetry }
    }

    func clearStuck() async throws {
        queue.removeAll { $0.attemptCount >= stuckThreshold }
        saveToDisk()
        Logger.persistence.info("Cleared stuck items from queue")
    }

    func clearAll() async throws {
        queue = []
        if let url = Self.queueFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func pendingCount(for goalSlug: String) -> Int {
        queue.filter { $0.goalSlug == goalSlug }.count
    }

    func pendingDatapoints(for goalSlug: String) -> [QueuedDatapoint] {
        queue.filter { $0.goalSlug == goalSlug }
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
