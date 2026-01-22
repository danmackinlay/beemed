//
//  MainView.swift
//  beemed
//

import SwiftUI

struct MainView: View {
    @Environment(GoalsManager.self) private var goalsManager
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
        // Placeholder: will be implemented in Milestone D
        print("Logging \(value) to \(goal.slug) with comment: \(comment)")
    }
}

#Preview {
    MainView()
        .environment(AuthState())
        .environment(GoalsManager())
}
