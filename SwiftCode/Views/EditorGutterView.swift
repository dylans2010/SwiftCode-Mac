import SwiftUI

struct EditorGutterView: View {
    let lineCount: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(1...lineCount, id: \.self) { line in
                Text("\(line)")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(height: 18)
            }
        }
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.05))
    }
}
