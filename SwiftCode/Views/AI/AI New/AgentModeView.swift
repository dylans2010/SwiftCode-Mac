import SwiftUI

struct AgentModeView: View {
    var body: some View {
        VStack(spacing: 20) {
            ToolExecutionView()
            CodeChangesView()
            Spacer()
        }
    }
}
