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

    enum CodingKeys: String, CodingKey {
        case slug
        case title
        case updatedAt = "updated_at"
    }
}
