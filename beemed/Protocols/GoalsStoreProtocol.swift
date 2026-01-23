//
//  GoalsStoreProtocol.swift
//  beemed
//

import Foundation

struct GoalsSnapshot: Sendable {
    let goals: [Goal]
    let pinned: Set<String>
    let lastRefresh: Date?

    static let empty = GoalsSnapshot(goals: [], pinned: [], lastRefresh: nil)
}

protocol GoalsStoreProtocol: Sendable {
    func load() async throws -> GoalsSnapshot
    func saveGoals(_ goals: [Goal], at date: Date) async throws
    func savePinned(_ pinned: Set<String>) async throws
    func clear() async throws
}
