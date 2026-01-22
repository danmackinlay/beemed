//
//  Goal.swift
//  beemed
//

import Foundation

struct Goal: Identifiable, Codable, Hashable {
    let slug: String
    let title: String
    let losedate: Int  // Unix timestamp from Beeminder API
    let updatedAt: Date

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug
        case title
        case losedate
        case updatedAt = "updated_at"
    }

    var timeToDerail: TimeInterval {
        Date(timeIntervalSince1970: TimeInterval(losedate)).timeIntervalSinceNow
    }

    var urgencyLabel: String {
        let hours = timeToDerail / 3600
        if hours < 0 { return "derailed" }
        if hours < 24 { return "<24h" }
        let days = Int(hours / 24)
        let remainingHours = Int(hours) % 24
        return "\(days)d \(remainingHours)h"
    }
}
