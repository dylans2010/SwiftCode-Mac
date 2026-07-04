import SwiftUI

struct QuestionsHandleView: View {
    let questionSet: AgentPendingQuestionSet
    @Bindable var viewModel: AgentViewModel
    @State private var answers: [UUID: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clarifying Questions")
                .font(.headline)

            ForEach(questionSet.questions) { question in
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.question)
                        .font(.subheadline)

                    switch question.inputType {
                    case .text:
                        TextField("Answer...", text: Binding(
                            get: { answers[question.id] ?? "" },
                            set: { answers[question.id] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    case .selection(let options):
                        Picker("", selection: Binding(
                            get: { answers[question.id] },
                            set: { answers[question.id] = $0 }
                        )) {
                            Text("Select an option").tag(nil as String?)
                            ForEach(options, id: \.self) { option in
                                Text(option).tag(option as String?)
                            }
                        }
                    }
                }
            }

            Button("Submit All") {
                viewModel.submitMultipleAnswers(answers)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!allAnswered)
        }
        .padding()
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(8)
    }

    private var allAnswered: Bool {
        questionSet.questions.allSatisfy { q in
            if let ans = answers[q.id], !ans.isEmpty {
                return true
            }
            return false
        }
    }
}
