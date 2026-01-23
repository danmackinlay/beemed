//
//  LoginView.swift
//  beemed
//

import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "target")
                .font(.system(size: 80))
                .foregroundStyle(.tint)

            Text("Beemed")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Quick +1 logging for Beeminder")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            if appModel.session.isLoading {
                ProgressView("Signing in...")
            } else {
                Button {
                    Task {
                        await appModel.signIn()
                    }
                } label: {
                    Label("Sign in with Beeminder", systemImage: "person.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if let error = appModel.session.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()
                .frame(height: 40)
        }
        .padding(.horizontal, 40)
    }
}

#Preview {
    LoginView()
        .environment(AppModel())
}
