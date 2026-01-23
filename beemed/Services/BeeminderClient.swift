//
//  BeeminderClient.swift
//  beemed
//

import Foundation

enum APIError: Error, LocalizedError, Equatable {
    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized): return true
        case (.invalidResponse, .invalidResponse): return true
        case (.httpError(let l), .httpError(let r)): return l == r
        case (.networkError, .networkError): return true  // Don't compare underlying errors
        case (.decodingError, .decodingError): return true
        default: return false
        }
    }

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

actor LiveBeeminderAPI: BeeminderAPI {
    private let baseURL = URL(string: "https://www.beeminder.com/api/v1/")!

    init() {}

    func fetchGoals(token: String) async throws -> [Goal] {
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

    private struct CreateDatapointBody: Encodable {
        let value: Double
        let timestamp: Int
        let requestid: String
        let comment: String?
    }

    func createDatapoint(token: String, request: CreateDatapointRequest) async throws {
        let url = baseURL.appendingPathComponent("users/me/goals/\(request.goalSlug)/datapoints.json")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = CreateDatapointBody(
            value: request.value,
            timestamp: Int(request.timestamp.timeIntervalSince1970),
            requestid: request.requestid,
            comment: request.comment?.isEmpty == false ? request.comment : nil
        )

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(body)

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await URLSession.shared.data(for: urlRequest)
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
