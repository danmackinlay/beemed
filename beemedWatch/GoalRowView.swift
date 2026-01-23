//
//  GoalRowView.swift
//  beemedWatch
//

import SwiftUI

struct GoalRowView: View {
    let goal: GoalSummary
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                // Urgency indicator
                Circle()
                    .fill(goal.urgencyColor)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.headline)
                        .lineLimit(2)

                    Text(goal.slug)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("+1")
                    .font(.headline)
                    .foregroundStyle(.blue)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    List {
        GoalRowView(
            goal: GoalSummary(
                slug: "exercise",
                title: "Daily Exercise",
                losedate: Int(Date().addingTimeInterval(3600 * 5).timeIntervalSince1970)
            ),
            onTap: {}
        )
        GoalRowView(
            goal: GoalSummary(
                slug: "reading",
                title: "Read Books",
                losedate: Int(Date().addingTimeInterval(3600 * 48).timeIntervalSince1970)
            ),
            onTap: {}
        )
    }
}
