import SwiftUI

struct AgentToolbar: View {
    @Binding var selectedTab: Int

    var body: some View {
        HStack(spacing: 20) {
            Button(action: { selectedTab = 0 }) {
                VStack {
                    Image(systemName: "bolt.fill")
                    Text("Agent")
                        .font(.caption)
                }
                .foregroundColor(selectedTab == 0 ? .blue : .secondary)
            }
            .buttonStyle(.plain)

            Button(action: { selectedTab = 1 }) {
                VStack {
                    Image(systemName: "message.fill")
                    Text("Chat")
                        .font(.caption)
                }
                .foregroundColor(selectedTab == 1 ? .blue : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}
