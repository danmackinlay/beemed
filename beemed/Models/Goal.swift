//
//  Goal.swift
//  beemed
//

import Foundation

struct Goal: Identifiable, Codable, Hashable, Sendable {
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
        let total = timeToDerail
        if total < 0 { return "derailed" }

        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60

        if hours >= 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)d \(remainingHours)h"
        }
        if hours >= 1 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
