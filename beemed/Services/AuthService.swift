//
//  AuthService.swift
//  beemed
//

import AuthenticationServices
import Foundation

enum AuthService {
    private static let clientID = "4l7yrd4esmb0hgi5hgc6u2huy"
    private static let redirectURI = "beemed://oauth-callback"
    private static let callbackScheme = "beemed"

    struct AuthResult {
        let accessToken: String
        let username: String
    }

    static func signIn() async throws -> AuthResult {
        let authURL = URL(string: "https://www.beeminder.com/apps/authorize?client_id=\(clientID)&redirect_uri=\(redirectURI)&response_type=token")!

        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let callbackURL = callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: AuthError.noCallback)
                }
            }

            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        return try parseCallback(url: callbackURL)
    }

    private static func parseCallback(url: URL) throws -> AuthResult {
        // The callback URL format is: beemed://oauth-callback#access_token=TOKEN&username=USERNAME
        guard let fragment = url.fragment else {
            throw AuthError.invalidCallback
        }

        var params: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let components = pair.split(separator: "=", maxSplits: 1)
            if components.count == 2 {
                let key = String(components[0])
                let value = String(components[1])
                    .removingPercentEncoding ?? String(components[1])
                params[key] = value
            }
        }

        guard let accessToken = params["access_token"],
              let username = params["username"] else {
            throw AuthError.missingCredentials
        }

        return AuthResult(accessToken: accessToken, username: username)
    }

    static func signOut() {
        KeychainHelper.deleteToken()
    }
}

enum AuthError: Error, LocalizedError {
    case noCallback
    case invalidCallback
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .noCallback:
            return "No callback received from Beeminder"
        case .invalidCallback:
            return "Invalid callback URL format"
        case .missingCredentials:
            return "Missing access token or username in callback"
        }
    }
}
