//
//  GoalRowView.swift
//  beemed
//

import SwiftUI

extension Goal {
    var urgencyColor: Color {
        let hours = timeToDerail / 3600
        if hours < 24 { return .red }
        if hours < 72 { return .orange }
        return .yellow
    }
}

struct GoalRowView: View {
    let goal: Goal
    let datapointState: DatapointState
    let pendingCount: Int
    let onPlusOne: () -> Void
    let onCustomValue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.headline)
                    Text(goal.slug)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Urgency badge
                Text(goal.urgencyLabel)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(goal.urgencyColor.opacity(0.2))
                    .foregroundStyle(goal.urgencyColor)
                    .clipShape(Capsule())

                // Pending count badge
                if pendingCount > 0 {
                    Text("\(pendingCount) pending")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button(action: onCustomValue) {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .tint(.secondary)

                Button(action: onPlusOne) {
                    Text("+1")
                        .font(.title2)
                        .fontWeight(.bold)
                        .frame(minWidth: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(datapointState == .sending)

                Spacer()

                // Status indicator
                statusView
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusView: some View {
        switch datapointState {
        case .idle:
            EmptyView()
        case .sending:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("sending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .success(let date):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("updated \(date.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .queued(let count):
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.orange)
                Text("\(count) queued")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let error):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    List {
        GoalRowView(
            goal: Goal(
                slug: "exercise",
                title: "Daily Exercise",
                losedate: Int(Date().addingTimeInterval(3600 * 5).timeIntervalSince1970),
                updatedAt: Date()
            ),
            datapointState: .idle,
            pendingCount: 0,
            onPlusOne: {},
            onCustomValue: {}
        )
        GoalRowView(
            goal: Goal(
                slug: "reading",
                title: "Read Books",
                losedate: Int(Date().addingTimeInterval(3600 * 48).timeIntervalSince1970),
                updatedAt: Date()
            ),
            datapointState: .success(Date()),
            pendingCount: 0,
            onPlusOne: {},
            onCustomValue: {}
        )
        GoalRowView(
            goal: Goal(
                slug: "writing",
                title: "Write Words",
                losedate: Int(Date().addingTimeInterval(3600 * 96).timeIntervalSince1970),
                updatedAt: Date()
            ),
            datapointState: .queued(2),
            pendingCount: 2,
            onPlusOne: {},
            onCustomValue: {}
        )
    }
}
