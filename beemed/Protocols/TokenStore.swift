//
//  TokenStore.swift
//  beemed
//

import Foundation

protocol TokenStore: Sendable {
    func load() async -> String?
    func save(_ token: String) async throws
    func loadUsername() async -> String?
    func saveUsername(_ username: String) async throws
    func clear() async throws
}
