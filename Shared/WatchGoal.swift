//
//  WatchGoal.swift
//  beemed
//
//  Shared between iOS and watchOS targets

import Foundation

/// Lightweight goal structure for watch communication
struct WatchGoal: Identifiable, Codable, Sendable {
    let slug: String
    let title: String
    let losedate: Int

    var id: String { slug }
}

/// Urgency level based on time until derailment
enum WatchGoalUrgency {
    case critical  // < 24h
    case warning   // < 72h
    case safe      // >= 72h

    init(losedate: Int) {
        let hours = Date(timeIntervalSince1970: TimeInterval(losedate))
            .timeIntervalSinceNow / 3600
        if hours < 24 { self = .critical }
        else if hours < 72 { self = .warning }
        else { self = .safe }
    }
}
