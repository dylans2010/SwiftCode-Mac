import SwiftUI

struct DebugConsoleView: View {
    @State var viewModel: DebugSessionViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(viewModel.consoleOutput)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .liquidGlass(style: .hud, cornerRadius: 0)
            .foregroundStyle(.white)

            HStack(spacing: 8) {
                TextField("stdin", text: .constant(""))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .liquidGlass(style: .subtle, cornerRadius: 6)
                Button("Send") { }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(8)
            .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
        }
    }
}
