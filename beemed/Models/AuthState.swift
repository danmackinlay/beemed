//
//  AuthState.swift
//  beemed
//

import SwiftUI

@Observable
final class AuthState {
    var isSignedIn: Bool = false
    var username: String = ""
    var isLoading: Bool = false
    var error: Error?

    private let usernameKey = "beeminder_username"

    init() {
        // Check if we have a stored token and username
        if KeychainHelper.loadToken() != nil {
            isSignedIn = true
            username = UserDefaults.standard.string(forKey: usernameKey) ?? ""
        }
    }

    func signIn() async {
        isLoading = true
        error = nil

        do {
            let result = try await AuthService.signIn()

            // Save token to Keychain
            try KeychainHelper.saveToken(result.accessToken)

            // Save username to UserDefaults
            UserDefaults.standard.set(result.username, forKey: usernameKey)

            isSignedIn = true
            username = result.username
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func signOut() {
        AuthService.signOut()
        UserDefaults.standard.removeObject(forKey: usernameKey)
        isSignedIn = false
        username = ""
    }
}
