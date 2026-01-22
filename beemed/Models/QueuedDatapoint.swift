//
//  QueuedDatapoint.swift
//  beemed
//

import Foundation

struct QueuedDatapoint: Codable, Identifiable {
    let id: UUID           // Also used as Beeminder requestid for idempotency
    let goalSlug: String
    let value: Double
    let timestamp: Date
    let comment: String?
    var attemptCount: Int
    var lastError: String?
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
        self.createdAt = Date()
        self.nextAttemptAt = nil
        self.lastAttemptAt = nil
    }

    var isReadyToRetry: Bool {
        guard let nextAttempt = nextAttemptAt else { return true }
        return Date() >= nextAttempt
    }

    // Backoff: 1m, 5m, 20m, 1h, 1h, 1h...
    mutating func recordFailure(error: String) {
        attemptCount += 1
        lastError = error
        lastAttemptAt = Date()

        let backoffMinutes: [Double] = [1, 5, 20, 60, 60, 60]
        let backoffIndex = min(attemptCount - 1, backoffMinutes.count - 1)
        let delay = backoffMinutes[backoffIndex] * 60
        nextAttemptAt = Date(timeIntervalSinceNow: delay)
    }

    mutating func recordSuccess() {
        lastAttemptAt = Date()
    }
}
