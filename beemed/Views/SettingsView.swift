//
//  SettingsView.swift
//  beemed
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthState.self) private var authState
    @Environment(GoalsManager.self) private var goalsManager
    @AppStorage("pinnedGoalSlugs") private var pinnedGoalSlugsData: Data = Data()
    @State private var searchText: String = ""

    private var pinnedGoalSlugs: Set<String> {
        get {
            (try? JSONDecoder().decode(Set<String>.self, from: pinnedGoalSlugsData)) ?? []
        }
    }

    private func setPinnedGoalSlugs(_ slugs: Set<String>) {
        pinnedGoalSlugsData = (try? JSONEncoder().encode(slugs)) ?? Data()
    }

    private var allGoals: [Goal] {
        goalsManager.goals
    }

    private var filteredGoals: [Goal] {
        if searchText.isEmpty {
            return allGoals
        }
        return allGoals.filter { goal in
            goal.title.localizedCaseInsensitiveContains(searchText) ||
            goal.slug.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(filteredGoals) { goal in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(goal.title)
                                    .font(.body)
                                Text(goal.slug)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { pinnedGoalSlugs.contains(goal.slug) },
                                set: { isPinned in
                                    var slugs = pinnedGoalSlugs
                                    if isPinned {
                                        slugs.insert(goal.slug)
                                    } else {
                                        slugs.remove(goal.slug)
                                    }
                                    setPinnedGoalSlugs(slugs)
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                } header: {
                    Text("Pin Goals")
                } footer: {
                    Text("Pinned goals appear on the main screen for quick logging.")
                }

                Section {
                    LabeledContent("Connected as", value: authState.username)
                    Button {
                        Task {
                            await goalsManager.fetchGoals()
                        }
                    } label: {
                        HStack {
                            Text("Refresh Goals")
                            Spacer()
                            if goalsManager.isLoading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(goalsManager.isLoading)
                    Button("Sign Out", role: .destructive) {
                        goalsManager.clearCache()
                        authState.signOut()
                        dismiss()
                    }
                } header: {
                    Text("Account")
                }
            }
            .formStyle(.grouped)
            .searchable(text: $searchText, prompt: "Search goals")
            .navigationTitle("Settings")
            .frame(minWidth: 400, minHeight: 300)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthState())
        .environment(GoalsManager())
}
