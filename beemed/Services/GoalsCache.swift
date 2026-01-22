//
//  GoalsCache.swift
//  beemed
//

import Foundation

enum GoalsCache {
    private static let fileName = "cached_goals.json"

    private static var cacheFileURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let appDirectory = appSupport.appendingPathComponent("beemed", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        return appDirectory.appendingPathComponent(fileName)
    }

    static func save(_ goals: [Goal]) {
        guard let url = cacheFileURL else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970

        do {
            let data = try encoder.encode(goals)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save goals cache: \(error)")
        }
    }

    static func load() -> [Goal]? {
        guard let url = cacheFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([Goal].self, from: data)
        } catch {
            print("Failed to load goals cache: \(error)")
            return nil
        }
    }

    static func clear() {
        guard let url = cacheFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
