import SwiftUI

public struct AssistDiffView: View {
    let plan: AssistPlan
    @Environment(\.dismiss) private var dismiss

    public init(plan: AssistPlan) {
        self.plan = plan
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(plan.steps) { step in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(step.description)
                                    .font(.headline)
                                    .foregroundStyle(.white)

                                ForEach(step.actions, id: \.path) { action in
                                    DiffActionView(action: action)
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Diff Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct DiffActionView: View {
    let action: AssistAction

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconForAction(action))
                    .foregroundStyle(colorForAction(action))
                Text(action.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                Spacer()
                Text(typeForAction(action))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(colorForAction(action))
            }

            if case .modifyFile(_, let patch) = action {
                Text(patch)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.green)
            } else if case .createFile(_, let content) = action {
                Text(content)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.green)
            }
        }
        .padding(.top, 4)
    }

    private func iconForAction(_ action: AssistAction) -> String {
        switch action {
        case .createFile: return "plus.circle.fill"
        case .modifyFile: return "pencil.circle.fill"
        case .deleteFile: return "trash.circle.fill"
        case .renameFile: return "arrow.right.circle.fill"
        case .runTest: return "play.circle.fill"
        }
    }

    private func colorForAction(_ action: AssistAction) -> Color {
        switch action {
        case .createFile: return .green
        case .modifyFile: return .blue
        case .deleteFile: return .red
        case .renameFile: return .purple
        case .runTest: return .orange
        }
    }

    private func typeForAction(_ action: AssistAction) -> String {
        switch action {
        case .createFile: return "CREATE"
        case .modifyFile: return "MODIFY"
        case .deleteFile: return "DELETE"
        case .renameFile: return "RENAME"
        case .runTest: return "TEST"
        }
    }
}
