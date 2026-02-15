//
//  ContentView.swift
//  beemedWatch
//

import SwiftUI

struct ContentView: View {
    @Environment(WatchState.self) private var watchState

    var body: some View {
        NavigationStack {
            ZStack {
                if watchState.goals.isEmpty {
                    ContentUnavailableView {
                        Label("No Goals", systemImage: "target")
                    } description: {
                        Text("Pin goals in the iPhone app to see them here.")
                    }
                } else {
                    List(watchState.goals) { goal in
                        GoalRowView(goal: goal) {
                            watchState.sendPlusOne(goalSlug: goal.slug)
                        }
                    }
                }

                // Confirmation overlay
                if watchState.showingConfirmation {
                    ConfirmationOverlay()
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .navigationTitle("Beemed")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        watchState.requestPinnedGoals()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: watchState.showingConfirmation)
        }
    }
}

struct ConfirmationOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.green)
                Text("+1 Sent")
                    .font(.headline)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(WatchState())
}
