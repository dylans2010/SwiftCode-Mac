import Foundation
import SwiftUI

// Go to line, adapted from Legacy's `SwiftCode/Views/Editor/GoToLineView.swift`.
// The destination editor has no go-to-line sheet, so this is a small
// real one: a sheet that validates the entered line against the file's
// line count and reports the chosen line back through `onJump`. It
// owns no editor state itself — the host wires `onJump` to its editor.

/// A sheet that jumps the editor to a line number.
struct GoToLineSheet: View {
    /// The total number of lines in the file (1-based maximum).
    var lineCount: Int
    /// Called with the validated 1-based line number when the user jumps.
    var onJump: (Int) -> Void
    /// Called when the sheet is dismissed without jumping.
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
