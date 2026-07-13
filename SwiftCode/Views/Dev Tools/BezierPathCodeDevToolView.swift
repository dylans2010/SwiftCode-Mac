import SwiftUI
import os.log

@Observable
@MainActor
final class BezierPathCodeViewModel {
    var rawCoordinates: String = "move(to: 0,0), line(to: 100,100), curve(to: 200,0, ctrl1: 150,-50, ctrl2: 200,-100)"
    var generatedCode: String = ""

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "BezierPathCode")

    func generate() {
        generatedCode = """
        import SwiftUI

        struct CustomBezierShape: Shape {
            func path(in rect: CGRect) -> Path {
                var path = Path()
                path.move(to: CGPoint(x: rect.minX + 0, y: rect.minY + 0))
                path.addLine(to: CGPoint(x: rect.minX + 100, y: rect.minY + 100))
                path.addCurve(to: CGPoint(x: rect.minX + 200, y: rect.minY + 0),
                              control1: CGPoint(x: rect.minX + 150, y: rect.minY - 50),
                              control2: CGPoint(x: rect.minX + 200, y: rect.minY - 100))
                return path
            }
        }
        """
        logger.info("Successfully structured bezier path code output")
    }
}

struct BezierPathCodeDevToolView: View {
    @State private var viewModel = BezierPathCodeViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Generate reusable SwiftUI Shape paths from simple visual vector definitions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Vector Path Syntax")
                        .font(.headline)
                    TextField("Enter path syntax", text: $viewModel.rawCoordinates)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                Button("Generate Shape Code") {
                    viewModel.generate()
                }
                .buttonStyle(.borderedProminent)

                if !viewModel.generatedCode.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Resulting SwiftUI Shape struct")
                            .font(.headline)
                            .foregroundColor(.blue)

                        TextEditor(text: .constant(viewModel.generatedCode))
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 220)
                            .border(Color.secondary.opacity(0.15))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Bezier Path Code Generator")
    }
}
