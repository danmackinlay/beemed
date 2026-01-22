//
//  GoalsManager.swift
//  beemed
//

import SwiftUI

@Observable
final class GoalsManager {
    var goals: [Goal] = []
    var isLoading: Bool = false
    var error: Error?

    init() {
        // Load cached goals on init
        if let cached = GoalsCache.load() {
            goals = cached
        }
    }

    func fetchGoals() async {
        isLoading = true
        error = nil

        do {
            let fetchedGoals = try await BeeminderClient.getGoals()
            goals = fetchedGoals.sorted { $0.updatedAt > $1.updatedAt }
            GoalsCache.save(goals)
        } catch {
            self.error = error
            // Keep existing cached goals on error
        }

        isLoading = false
    }

    func clearCache() {
        goals = []
        GoalsCache.clear()
    }
}
