//
//  BeeminderAPI.swift
//  beemed
//

import Foundation

struct CreateDatapointRequest: Sendable {
    let goalSlug: String
    let value: Double
    let timestamp: Date
    let comment: String?
    let requestid: String
}

protocol BeeminderAPI: Sendable {
    func fetchGoals(token: String) async throws -> [Goal]
    func createDatapoint(token: String, request: CreateDatapointRequest) async throws
}
