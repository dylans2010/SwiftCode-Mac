import SwiftUI

struct AgentModeView: View {
    var body: some View {
        VStack(spacing: 20) {
            AIToolExecutionView()
            CodeChangesView()
            Spacer()
        }
        .padding()
        .liquidGlass(style: .standard, cornerRadius: 16)
    }
}
