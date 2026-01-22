//
//  CustomValueSheet.swift
//  beemed
//

import SwiftUI

struct CustomValueSheet: View {
    let goal: Goal
    let onSubmit: (Double, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var valueText: String = "1"
    @State private var comment: String = ""
    @FocusState private var isValueFocused: Bool

    private var value: Double? {
        Double(valueText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Value", text: $valueText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .focused($isValueFocused)
                } header: {
                    Text("Value")
                }

                Section {
                    TextField("Optional comment", text: $comment)
                } header: {
                    Text("Comment")
                }
            }
            .navigationTitle(goal.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        if let value {
                            onSubmit(value, comment)
                            dismiss()
                        }
                    }
                    .disabled(value == nil)
                }
            }
            .onAppear {
                isValueFocused = true
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    CustomValueSheet(
        goal: Goal(slug: "exercise", title: "Daily Exercise", updatedAt: Date()),
        onSubmit: { value, comment in
            print("Submitted \(value) with comment: \(comment)")
        }
    )
}
