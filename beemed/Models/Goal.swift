//
//  Goal.swift
//  beemed
//

import Foundation

struct Goal: Identifiable, Codable, Hashable {
    let slug: String
    let title: String
    let updatedAt: Date

    var id: String { slug }

    static let dummyData: [Goal] = [
        Goal(slug: "exercise", title: "Daily Exercise", updatedAt: Date()),
        Goal(slug: "meditation", title: "Meditation Minutes", updatedAt: Date().addingTimeInterval(-3600)),
        Goal(slug: "reading", title: "Pages Read", updatedAt: Date().addingTimeInterval(-7200)),
        Goal(slug: "water", title: "Glasses of Water", updatedAt: Date().addingTimeInterval(-10800)),
        Goal(slug: "writing", title: "Words Written", updatedAt: Date().addingTimeInterval(-14400)),
        Goal(slug: "sleep", title: "Hours of Sleep", updatedAt: Date().addingTimeInterval(-18000)),
    ]
}
