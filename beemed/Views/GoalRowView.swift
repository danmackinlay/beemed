//
//  GoalRowView.swift
//  beemed
//

import SwiftUI

struct GoalRowView: View {
    let goal: Goal
    let onPlusOne: () -> Void
    let onCustomValue: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.title)
                    .font(.headline)
                Text(goal.slug)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

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
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    List {
        GoalRowView(
            goal: Goal(slug: "exercise", title: "Daily Exercise", updatedAt: Date()),
            onPlusOne: {},
            onCustomValue: {}
        )
    }
}
