import SwiftUI

public struct PlanUserAskView: View {
    @ObservedObject private var questionManager = PlanQuestionManager.shared
    @State private var selectedChoices: Set<String> = []
    @State private var freeFormText: String = ""
    @State private var isSubmitting = false

    public init() {}

    public var body: some View {
        if let question = questionManager.currentQuestion {
            questionContent(question)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func questionContent(_ question: PlanQuestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Decision Required", systemImage: "exclamationmark.bubble.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
            }
            .padding()
            .background(.thinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(question.question)
                        .font(.body)
                        .fontWeight(.medium)
                        .fixedSize(horizontal: false, vertical: true)

                    if !question.choices.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            if question.allowsMultipleAnswers {
                                Text("Select one or more:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Select one:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(question.choices) { choice in
                                choiceRow(choice, question: question)
                            }
                        }
                    }

                    if question.userSpecification {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Or type your answer:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Type in your answer...", text: $freeFormText, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(3...6)
                        }
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Button("Cancel") {
                    PlanQuestionManager.shared.cancel(questionID: question.id)
                }
                .buttonStyle(.borderless)
                .disabled(isSubmitting)

                Spacer()

                Button {
                    submitAnswer(question: question)
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Submit")
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit(question: question) || isSubmitting)
            }
            .padding()
        }
        .frame(maxWidth: 500)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func choiceRow(_ choice: PlanQuestionChoice, question: PlanQuestion) -> some View {
        let isSelected = selectedChoices.contains(choice.choice)

        Button {
            if question.allowsMultipleAnswers {
                if isSelected {
                    selectedChoices.remove(choice.choice)
                } else {
                    selectedChoices.insert(choice.choice)
                }
            } else {
                selectedChoices = [choice.choice]
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? (question.allowsMultipleAnswers ? "checkmark.square.fill" : "largecircle.fill.circle") : (question.allowsMultipleAnswers ? "square" : "circle"))
                    .font(.body)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                Text(choice.choice)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                if choice.assistRecommended {
                    Text("Recommended")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func canSubmit(question: PlanQuestion) -> Bool {
        if question.userSpecification && !freeFormText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if !selectedChoices.isEmpty {
            return true
        }
        return false
    }

    private func submitAnswer(question: PlanQuestion) {
        isSubmitting = true

        let answer: PlanQuestionAnswer
        if question.userSpecification && !freeFormText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            answer = .freeForm(freeFormText.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            answer = .selectedChoices(Array(selectedChoices))
        }

        PlanQuestionManager.shared.resolve(questionID: question.id, answer: answer)
        isSubmitting = false
    }
}
