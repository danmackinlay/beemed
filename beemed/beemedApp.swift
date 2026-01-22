//
//  beemedApp.swift
//  beemed
//
//  Created by Daniel Mackinlay on 22/1/2026.
//

import SwiftUI

@main
struct beemedApp: App {
    @State private var authState = AuthState()

    var body: some Scene {
        WindowGroup {
            Group {
                if authState.isSignedIn {
                    MainView()
                } else {
                    LoginView()
                }
            }
            .environment(authState)
        }
    }
}
