//
//  AuthService.swift
//  beemed
//

import AuthenticationServices
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthContextProvider()
    private override init() { super.init() }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApplication.shared.windows.first { $0.isKeyWindow }
            ?? NSApplication.shared.windows.first
            ?? NSWindow()
        #else
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first ?? UIWindow()
        #endif
    }
}

enum AuthService {
    private static let clientID = "6nuc31fv1a8qdl30e5rrz5wan"
    private static let redirectURI = "beemed://oauth-callback/"
    private static let callbackScheme = "beemed"
    private static var currentSession: ASWebAuthenticationSession?

    struct AuthResult {
        let accessToken: String
        let username: String
    }

    static func signIn() async throws -> AuthResult {
        let authURL = URL(string: "https://www.beeminder.com/apps/authorize?client_id=\(clientID)&redirect_uri=\(redirectURI)&response_type=token")!

        let contextProvider = WebAuthContextProvider.shared

        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                currentSession = nil
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let callbackURL = callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: AuthError.noCallback)
                }
            }

            session.presentationContextProvider = contextProvider
            session.prefersEphemeralWebBrowserSession = false
            currentSession = session
            session.start()
        }

        return try parseCallback(url: callbackURL)
    }

    private static func parseCallback(url: URL) throws -> AuthResult {
        // The callback URL format is: beemed://oauth-callback/?access_token=TOKEN&username=USERNAME
        guard let query = url.query else {
            throw AuthError.invalidCallback
        }

        var params: [String: String] = [:]
        for pair in query.split(separator: "&") {
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
