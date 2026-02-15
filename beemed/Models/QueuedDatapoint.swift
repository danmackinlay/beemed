//
//  QueuedDatapoint.swift
//  beemed
//

import Foundation

nonisolated struct SyncError: Codable, Sendable {
    let message: String
    let httpStatus: Int?
    let isRetryable: Bool
    let timestamp: Date

    init(message: String, httpStatus: Int? = nil, isRetryable: Bool = true) {
        self.message = message
        self.httpStatus = httpStatus
        self.isRetryable = isRetryable
        self.timestamp = Date()
    }
}

nonisolated struct QueuedDatapoint: Codable, Identifiable, Sendable {
    let id: UUID           // Also used as Beeminder requestid for idempotency
    let goalSlug: String
    let value: Double
    let timestamp: Date
    let comment: String?
    var attemptCount: Int
    var lastError: String?
    var lastSyncError: SyncError?
    let createdAt: Date
    var nextAttemptAt: Date?
    var lastAttemptAt: Date?

    init(
        goalSlug: String,
        value: Double,
        timestamp: Date = Date(),
        comment: String? = nil
    ) {
        self.id = UUID()
        self.goalSlug = goalSlug
        self.value = value
        self.timestamp = timestamp
        self.comment = comment
        self.attemptCount = 0
        self.lastError = nil
        self.lastSyncError = nil
        self.createdAt = Date()
        self.nextAttemptAt = nil
        self.lastAttemptAt = nil
    }

    var isReadyToRetry: Bool {
        guard let nextAttempt = nextAttemptAt else { return true }
        return Date() >= nextAttempt
    }

    // Backoff: 1m, 5m, 20m, 1h, 1h, 1h...
    mutating func recordFailure(error: String, httpStatus: Int? = nil, isRetryable: Bool = true) {
        attemptCount += 1
        lastError = error
        lastSyncError = SyncError(message: error, httpStatus: httpStatus, isRetryable: isRetryable)
        lastAttemptAt = Date()

        let backoffMinutes: [Double] = [1, 5, 20, 60, 60, 60]
        let backoffIndex = min(attemptCount - 1, backoffMinutes.count - 1)
        let delay = backoffMinutes[backoffIndex] * 60
        nextAttemptAt = Date(timeIntervalSinceNow: delay)
    }

}
