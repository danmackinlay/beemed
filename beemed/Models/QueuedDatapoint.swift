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
    }
}
