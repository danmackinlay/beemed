//
//  BeeminderClient.swift
//  beemed
//

import Foundation

enum BeeminderClient {
    private static let baseURL = URL(string: "https://www.beeminder.com/api/v1/")!

    enum APIError: Error, LocalizedError {
        case unauthorized
        case networkError(Error)
        case invalidResponse
        case httpError(statusCode: Int)
        case decodingError(Error)

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Authentication required. Please sign in again."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from server."
            case .httpError(let statusCode):
                return "Server error (HTTP \(statusCode))."
            case .decodingError(let error):
                return "Failed to parse response: \(error.localizedDescription)"
            }
        }
    }

    static func getGoals() async throws -> [Goal] {
        guard let token = KeychainHelper.loadToken() else {
            throw APIError.unauthorized
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("users/me/goals.json"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "emaciated", value: "true")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        do {
            return try decoder.decode([Goal].self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    static func createDatapoint(
        goalSlug: String,
        value: Double,
        timestamp: Date = Date(),
        comment: String? = nil,
        requestid: String = UUID().uuidString
    ) async throws {
        guard let token = KeychainHelper.loadToken() else {
            throw APIError.unauthorized
        }

        let url = baseURL.appendingPathComponent("users/me/goals/\(goalSlug)/datapoints.json")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "value": value,
            "timestamp": Int(timestamp.timeIntervalSince1970),
            "requestid": requestid
        ]
        if let comment = comment, !comment.isEmpty {
            body["comment"] = comment
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
    }
}
