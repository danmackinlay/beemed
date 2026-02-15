//
//  QueueStoreProtocol.swift
//  beemed
//

import Foundation

nonisolated struct QueueSnapshot: Sendable {
    let items: [QueuedDatapoint]

    init(items: [QueuedDatapoint]) {
        self.items = items
    }

    static let empty = QueueSnapshot(items: [])
}

nonisolated struct UploadError: Sendable {
    let message: String
    let httpStatus: Int?
    let isRetryable: Bool

    static func retryable(_ message: String, status: Int? = nil) -> UploadError {
        UploadError(message: message, httpStatus: status, isRetryable: true)
    }

    static func permanent(_ message: String, status: Int? = nil) -> UploadError {
        UploadError(message: message, httpStatus: status, isRetryable: false)
    }
}

protocol QueueStoreProtocol: Sendable {
    func hydrate() async
    func loadSnapshot() async throws -> QueueSnapshot
    func enqueue(_ item: QueuedDatapoint) async throws
    func markAttempt(_ id: UUID, error: UploadError) async throws
    func remove(_ id: UUID) async throws
    func removeMultiple(_ ids: Set<UUID>) async throws
    func allPending(oldestFirst: Bool) async throws -> [QueuedDatapoint]
    func itemsReadyToRetry() async throws -> [QueuedDatapoint]
    func clearAll() async throws
}
