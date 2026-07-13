import SwiftUI
import os.log

@Observable
@MainActor
final class BezierCurveVisualizerViewModel {
    var p0 = CGPoint(x: 20, y: 150)
    var p1 = CGPoint(x: 100, y: 50)
    var p2 = CGPoint(x: 200, y: 50)
    var p3 = CGPoint(x: 280, y: 150)

    var cubicCode: String {
        "Path { path in\n    path.move(to: CGPoint(x: \(Int(p0.x)), y: \(Int(p0.y))))\n    path.addCurve(to: CGPoint(x: \(Int(p3.x)), y: \(Int(p3.y))),\n                  control1: CGPoint(x: \(Int(p1.x)), y: \(Int(p1.y))),\n                  control2: CGPoint(x: \(Int(p2.x)), y: \(Int(p2.y))))\n}"
    }
}

struct BezierCurveVisualizerDevToolView: View {
    @State private var viewModel = BezierCurveVisualizerViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Visually configure Bezier curves by dragging anchor and control points, generating SwiftUI Path code.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Canvas visual editor
                VStack {
                    ZStack {
                        Color(NSColor.controlBackgroundColor)

                        // Draw curves
                        Path { path in
                            path.move(to: viewModel.p0)
                            path.addCurve(to: viewModel.p3, control1: viewModel.p1, control2: viewModel.p2)
                        }
                        .stroke(Color.blue, lineWidth: 3)

                        // Handle lines
                        Path { path in
                            path.move(to: viewModel.p0)
                            path.addLine(to: viewModel.p1)
                            path.move(to: viewModel.p3)
                            path.addLine(to: viewModel.p2)
                        }
                        .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4]))

                        // Handles
                        controlPoint(point: $viewModel.p0, color: .green)
                        controlPoint(point: $viewModel.p1, color: .orange)
                        controlPoint(point: $viewModel.p2, color: .orange)
                        controlPoint(point: $viewModel.p3, color: .green)
                    }
                    .frame(height: 250)
                    .border(Color.secondary.opacity(0.2))
                    .cornerRadius(8)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("SwiftUI Code Output")
                        .font(.headline)
                    TextEditor(text: .constant(viewModel.cubicCode))
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 120)
                        .border(Color.secondary.opacity(0.15))
                }
            }
            .padding()
        }
        .navigationTitle("Bezier Curve Visualizer")
    }

    @ViewBuilder
    private func controlPoint(point: Binding<CGPoint>, color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .position(point.wrappedValue)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        point.wrappedValue = value.location
                    }
            )
    }
}
