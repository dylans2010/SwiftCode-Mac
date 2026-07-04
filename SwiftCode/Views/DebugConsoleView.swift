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
            .background(Color.black)
            .foregroundStyle(.white)

            HStack {
                TextField("stdin", text: .constant(""))
                    .textFieldStyle(.plain)
                Button("Send") { }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
        }
    }
}
