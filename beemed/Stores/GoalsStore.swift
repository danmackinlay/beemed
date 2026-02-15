//
//  GoalsStore.swift
//  beemed
//

import Foundation
import os

actor GoalsStore: GoalsStoreProtocol {
    private var goals: [Goal] = []
    private var pinned: Set<String> = []
    private var lastRefresh: Date?

    nonisolated private static let goalsFileName = "cached_goals.json"
    nonisolated private static let pinnedFileName = "pinned_goals.json"
    nonisolated private static let lastRefreshFileName = "goals_last_refresh.json"

    nonisolated private static var appDirectory: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("beemed", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated private static var goalsFileURL: URL? { appDirectory?.appendingPathComponent(goalsFileName) }
    nonisolated private static var pinnedFileURL: URL? { appDirectory?.appendingPathComponent(pinnedFileName) }
    nonisolated private static var lastRefreshFileURL: URL? { appDirectory?.appendingPathComponent(lastRefreshFileName) }

    init() {}

    func hydrate() async {
        loadFromDisk()
    }

    func load() async throws -> GoalsSnapshot {
        GoalsSnapshot(goals: goals, pinned: pinned, lastRefresh: lastRefresh)
    }

    func saveGoals(_ newGoals: [Goal], at date: Date) async throws {
        goals = newGoals
        lastRefresh = date

        guard let goalsURL = Self.goalsFileURL,
              let refreshURL = Self.lastRefreshFileURL else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970

        do {
            let goalsData = try encoder.encode(goals)
            try goalsData.write(to: goalsURL, options: .atomic)

            let refreshData = try encoder.encode(date)
            try refreshData.write(to: refreshURL, options: .atomic)
        } catch {
            Logger.persistence.error("Failed to save goals: \(error.localizedDescription)")
            throw error
        }
    }

    func savePinned(_ newPinned: Set<String>) async throws {
        pinned = newPinned

        guard let url = Self.pinnedFileURL else { return }

        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(Array(pinned))
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.persistence.error("Failed to save pinned goals: \(error.localizedDescription)")
            throw error
        }
    }

    func clear() async throws {
        goals = []
        pinned = []
        lastRefresh = nil

        if let goalsURL = Self.goalsFileURL {
            try? FileManager.default.removeItem(at: goalsURL)
        }
        if let refreshURL = Self.lastRefreshFileURL {
            try? FileManager.default.removeItem(at: refreshURL)
        }
        if let pinnedURL = Self.pinnedFileURL {
            try? FileManager.default.removeItem(at: pinnedURL)
        }
    }

    private func loadFromDisk() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        // Load goals
        if let url = Self.goalsFileURL,
           FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                goals = try decoder.decode([Goal].self, from: data)
            } catch {
                Logger.persistence.error("Failed to load goals cache: \(error.localizedDescription)")
            }
        }

        // Load pinned
        if let url = Self.pinnedFileURL,
           FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let array = try JSONDecoder().decode([String].self, from: data)
                pinned = Set(array)
            } catch {
                Logger.persistence.error("Failed to load pinned goals: \(error.localizedDescription)")
            }
        }

        // Load last refresh
        if let url = Self.lastRefreshFileURL,
           FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                lastRefresh = try decoder.decode(Date.self, from: data)
            } catch {
                Logger.persistence.error("Failed to load last refresh: \(error.localizedDescription)")
            }
        }
    }
}
