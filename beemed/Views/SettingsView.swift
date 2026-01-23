//
//  SettingsView.swift
//  beemed
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @State private var searchText: String = ""

    private var allGoals: [Goal] {
        appModel.goals.goals
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
                                get: { appModel.goals.pinned.contains(goal.slug) },
                                set: { isPinned in
                                    Task {
                                        if isPinned {
                                            var newPinned = appModel.goals.pinned
                                            newPinned.insert(goal.slug)
                                            await appModel.setPinned(newPinned)
                                        } else {
                                            var newPinned = appModel.goals.pinned
                                            newPinned.remove(goal.slug)
                                            await appModel.setPinned(newPinned)
                                        }
                                    }
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
                    LabeledContent("Connected as", value: appModel.session.username)
                    Button {
                        Task {
                            await appModel.refreshGoals()
                        }
                    } label: {
                        HStack {
                            Text("Refresh Goals")
                            Spacer()
                            if appModel.goals.isLoading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(appModel.goals.isLoading)
                    Button("Sign Out", role: .destructive) {
                        Task {
                            await appModel.signOut()
                            dismiss()
                        }
                    }
                } header: {
                    Text("Account")
                }
            }
            .formStyle(.grouped)
            .searchable(text: $searchText, prompt: "Search goals")
            .navigationTitle("Settings")
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 300)
            #endif
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
        .environment(AppModel())
}
