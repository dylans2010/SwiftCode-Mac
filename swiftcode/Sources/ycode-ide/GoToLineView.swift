import Foundation
import SwiftUI

struct GoToLineSheet: View {
    var lineCount: Int
    var onJump: (Int) -> Void
    var onCancel: () -> Void

    @State private var text = ""
    @State private var validationMessage: String?

    private var parsedLine: Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)), value >= 1 else { return nil }
        return value <= max(lineCount, 1) ? value : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Go to Line").font(ShellFonts.rowBold)
            HStack(spacing: 8) {
                TextField("Line number", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit { jump() }
                Text(verbatim: "of \(max(lineCount, 1))")
                    .font(ShellFonts.small)
                    .foregroundStyle(.secondary)
            }
            if let validationMessage {
                Text(verbatim: validationMessage)
                    .font(ShellFonts.small)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Jump") { jump() }
                    .buttonStyle(.borderedProminent)
                    .disabled(parsedLine == nil)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { text = "" }
    }

    private func jump() {
        guard let line = parsedLine else {
            validationMessage = "Enter a line from 1 to \(max(lineCount, 1))."
            return
        }
        onJump(line)
    }
}
