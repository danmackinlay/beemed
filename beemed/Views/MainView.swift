//
//  MainView.swift
//  beemed
//

import SwiftUI

struct MainView: View {
    @Environment(GoalsManager.self) private var goalsManager
    @Environment(AuthState.self) private var authState
    @AppStorage("pinnedGoalSlugs") private var pinnedGoalSlugsData: Data = Data()
    @State private var searchText: String = ""
    @State private var showingSettings: Bool = false
    @State private var selectedGoalForCustomValue: Goal?
    @State private var queuedCount: Int = 0

    private var pinnedGoalSlugs: Set<String> {
        get {
            (try? JSONDecoder().decode(Set<String>.self, from: pinnedGoalSlugsData)) ?? []
        }
    }

    private var allGoals: [Goal] {
        goalsManager.goals
    }

    private var pinnedGoals: [Goal] {
        allGoals.filter { pinnedGoalSlugs.contains($0.slug) }
    }

    private var filteredGoals: [Goal] {
        if searchText.isEmpty {
            return pinnedGoals
        }
        return pinnedGoals.filter { goal in
            goal.title.localizedCaseInsensitiveContains(searchText) ||
            goal.slug.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if goalsManager.isLoading && goalsManager.goals.isEmpty {
                    ProgressView("Loading goals...")
                } else if pinnedGoals.isEmpty {
                    ContentUnavailableView {
                        Label("No Pinned Goals", systemImage: "pin.slash")
                    } description: {
                        Text("Open Settings to pin goals for quick logging.")
                    } actions: {
                        Button("Open Settings") {
                            showingSettings = true
                        }
                    }
                } else {
                    List(filteredGoals) { goal in
                        GoalRowView(
                            goal: goal,
                            onPlusOne: {
                                logDatapoint(goal: goal, value: 1)
                            },
                            onCustomValue: {
                                selectedGoalForCustomValue = goal
                            }
                        )
                    }
                    .searchable(text: $searchText, prompt: "Search goals")
                    .refreshable {
                        await goalsManager.fetchGoals()
                    }
                }
            }
            .navigationTitle("Beemed")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
                if queuedCount > 0 {
                    ToolbarItem(placement: .status) {
                        Text("Queued: \(queuedCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environment(authState)
                    .environment(goalsManager)
            }
            .sheet(item: $selectedGoalForCustomValue) { goal in
                CustomValueSheet(goal: goal) { value, comment in
                    logDatapoint(goal: goal, value: value, comment: comment)
                }
            }
            .task {
                if goalsManager.goals.isEmpty {
                    await goalsManager.fetchGoals()
                }
            }
        }
    }

    private func logDatapoint(goal: Goal, value: Double, comment: String = "") {
        Task {
            do {
                try await BeeminderClient.createDatapoint(
                    goalSlug: goal.slug,
                    value: value,
                    comment: comment.isEmpty ? nil : comment
                )
                print("Successfully logged \(value) to \(goal.slug)")
            } catch {
                print("Failed to log datapoint: \(error)")
                // TODO: Milestone E will add offline queue here
            }
        }
    }
}

#Preview {
    MainView()
        .environment(AuthState())
        .environment(GoalsManager())
}
