//
//  MainView.swift
//  beemed
//

import SwiftUI

struct MainView: View {
    @Environment(GoalsManager.self) private var goalsManager
    @Environment(AuthState.self) private var authState
    @Environment(QueueManager.self) private var queueManager
    @Environment(SyncManager.self) private var syncManager
    @AppStorage("pinnedGoalSlugs") private var pinnedGoalSlugsData: Data = Data()
    @State private var searchText: String = ""
    @State private var showingSettings: Bool = false
    @State private var selectedGoalForCustomValue: Goal?
    @State private var datapointStates: [String: DatapointState] = [:]
    @State private var showNetworkToast: Bool = false
    @State private var networkToastMessage: String = ""

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
            ZStack {
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
                                datapointState: datapointStates[goal.slug] ?? syncManager.datapointState(for: goal.slug),
                                pendingCount: queueManager.pendingCount(for: goal.slug),
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

                // Network status toast
                VStack {
                    Spacer()
                    if showNetworkToast {
                        NetworkToastView(message: networkToastMessage, status: syncManager.networkStatus)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.bottom, 20)
                    }
                }
                .animation(.easeInOut, value: showNetworkToast)
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
                if queueManager.totalPendingCount > 0 {
                    ToolbarItem(placement: .status) {
                        HStack(spacing: 4) {
                            if syncManager.networkStatus == .syncing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "clock.fill")
                                    .foregroundStyle(.orange)
                            }
                            Text("Queued: \(queueManager.totalPendingCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
            .onChange(of: syncManager.networkStatus) { oldValue, newValue in
                handleNetworkStatusChange(from: oldValue, to: newValue)
            }
        }
    }

    private func logDatapoint(goal: Goal, value: Double, comment: String = "") {
        Task {
            // Show sending state immediately
            datapointStates[goal.slug] = .sending

            let result = await syncManager.submitDatapoint(
                goalSlug: goal.slug,
                value: value,
                comment: comment.isEmpty ? nil : comment
            )

            datapointStates[goal.slug] = result

            // Clear success state after a delay
            if case .success = result {
                try? await Task.sleep(for: .seconds(5))
                if case .success = datapointStates[goal.slug] {
                    datapointStates[goal.slug] = .idle
                }
            }
        }
    }

    private func handleNetworkStatusChange(from oldValue: NetworkState, to newValue: NetworkState) {
        switch newValue {
        case .offline:
            networkToastMessage = "No network — actions will be queued"
            showNetworkToast = true
        case .syncing:
            networkToastMessage = "Syncing..."
            showNetworkToast = true
        case .online:
            if oldValue == .syncing && queueManager.totalPendingCount == 0 {
                networkToastMessage = "All synced"
                showNetworkToast = true
                // Auto-dismiss after 2 seconds
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    if networkToastMessage == "All synced" {
                        showNetworkToast = false
                    }
                }
            } else if oldValue == .offline {
                showNetworkToast = false
            }
        }
    }
}

struct NetworkToastView: View {
    let message: String
    let status: NetworkState

    var body: some View {
        HStack(spacing: 8) {
            switch status {
            case .offline:
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.orange)
            case .syncing:
                ProgressView()
                    .controlSize(.small)
            case .online:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Text(message)
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}

#Preview {
    MainView()
        .environment(AuthState())
        .environment(GoalsManager())
        .environment(QueueManager())
        .environment(SyncManager())
}
