//
//  MainView.swift
//  beemed
//

import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var appModel
    @State private var searchText: String = ""
    @State private var showingSettings: Bool = false
    @State private var selectedGoalForCustomValue: Goal?
    @State private var localSendingState: [String: DatapointState] = [:]  // Brief local override during send
    @State private var showNetworkToast: Bool = false
    @State private var networkToastMessage: String = ""

    private var pinnedGoals: [Goal] {
        appModel.pinnedGoals
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
                    if appModel.goals.isLoading && appModel.goals.goals.isEmpty {
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
                                datapointState: localSendingState[goal.slug] ?? appModel.datapointStateFor(goal.slug),
                                pendingCount: appModel.pendingCountByGoal[goal.slug] ?? 0,
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
                            await appModel.refreshGoals()
                        }
                    }
                }

                // Network status toast
                VStack {
                    Spacer()
                    if showNetworkToast {
                        NetworkToastView(message: networkToastMessage, status: appModel.networkStatus)
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
                if appModel.queue.queuedCount > 0 {
                    ToolbarItem(placement: .status) {
                        HStack(spacing: 4) {
                            if appModel.networkStatus == .syncing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "clock.fill")
                                    .foregroundStyle(.orange)
                            }
                            Text("Queued: \(appModel.queue.queuedCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environment(appModel)
            }
            .sheet(item: $selectedGoalForCustomValue) { goal in
                CustomValueSheet(goal: goal) { value, comment in
                    logDatapoint(goal: goal, value: value, comment: comment)
                }
            }
            .task {
                if appModel.goals.goals.isEmpty {
                    await appModel.refreshGoals()
                }
            }
            .onChange(of: appModel.networkStatus) { oldValue, newValue in
                handleNetworkStatusChange(from: oldValue, to: newValue)
            }
            .onChange(of: appModel.goals.pinned) {
                // Send updated pinned goals to watch
                #if os(iOS)
                WatchSessionManager.shared.sendPinnedGoals(pinnedGoals)
                #endif
            }
            .onChange(of: appModel.goals.goals) {
                // Send pinned goals when goals are refreshed
                #if os(iOS)
                WatchSessionManager.shared.sendPinnedGoals(pinnedGoals)
                #endif
            }
        }
    }

    private func logDatapoint(goal: Goal, value: Double, comment: String = "") {
        Task {
            // Show sending state immediately via local override
            localSendingState[goal.slug] = .sending

            let result = await appModel.addDatapoint(
                goalSlug: goal.slug,
                value: value,
                comment: comment.isEmpty ? nil : comment
            )

            // Show result briefly
            localSendingState[goal.slug] = result

            // Clear local override after delay so AppModel becomes source of truth
            try? await Task.sleep(for: .seconds(3))
            localSendingState.removeValue(forKey: goal.slug)
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
            if oldValue == .syncing && appModel.queue.queuedCount == 0 {
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
        .environment(AppModel())
}
