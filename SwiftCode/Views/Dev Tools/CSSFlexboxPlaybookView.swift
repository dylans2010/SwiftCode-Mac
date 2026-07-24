import SwiftUI

public struct CSSFlexboxPlaybookView: View {
    @State private var flexDirection = "row"
    @State private var justifyContent = "flex-start"
    @State private var alignItems = "stretch"
    @State private var flexWrap = "nowrap"

    private let directions = ["row", "row-reverse", "column", "column-reverse"]
    private let justifies = ["flex-start", "flex-end", "center", "space-between", "space-around", "space-evenly"]
    private let alignments = ["stretch", "flex-start", "flex-end", "center", "baseline"]
    private let wraps = ["nowrap", "wrap", "wrap-reverse"]

    public init() {}

    private var generatedCSS: String {
        """
        .flex-container {
          display: flex;
          flex-direction: \(flexDirection);
          justify-content: \(justifyContent);
          align-items: \(alignItems);
          flex-wrap: \(flexWrap);
        }
        """
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CSS Flexbox Playbook")
                        .font(.title.bold())
                    Text("Interactive sandbox demonstrating CSS Flexible Box layout mechanics with generated styles.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack(alignment: .top, spacing: 20) {
                    // Left Control Card
                    VStack(alignment: .leading, spacing: 14) {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Flex Container Properties")
                                    .font(.headline)

                                Picker("flex-direction", selection: $flexDirection) {
                                    ForEach(directions, id: \.self) { d in Text(d).tag(d) }
                                }
                                .pickerStyle(.menu)

                                Picker("justify-content", selection: $justifyContent) {
                                    ForEach(justifies, id: \.self) { j in Text(j).tag(j) }
                                }
                                .pickerStyle(.menu)

                                Picker("align-items", selection: $alignItems) {
                                    ForEach(alignments, id: \.self) { a in Text(a).tag(a) }
                                }
                                .pickerStyle(.menu)

                                Picker("flex-wrap", selection: $flexWrap) {
                                    ForEach(wraps, id: \.self) { w in Text(w).tag(w) }
                                }
                                .pickerStyle(.menu)
                            }
                            .padding(8)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Generated CSS")
                                        .font(.headline)
                                    Spacer()
                                    Button("Copy") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(generatedCSS, forType: .string)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }

                                Text(generatedCSS)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.15))
                                    .cornerRadius(6)
                            }
                            .padding(8)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                    .frame(width: 320)

                    // Right Interactive Preview Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Interactive Layout Preview")
                                .font(.headline)

                            // Simulated flex container view
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.black.opacity(0.12))
                                    .frame(height: 250)

                                // Dynamically layout the boxes based on selections
                                let isColumn = flexDirection.contains("column")
                                let isReverse = flexDirection.contains("reverse")

                                if isColumn {
                                    VStack(alignment: flexAlignMap(alignItems), spacing: 10) {
                                        let items = [1, 2, 3]
                                        let orderedItems = isReverse ? items.reversed() : items
                                        ForEach(orderedItems, id: \.self) { idx in
                                            previewBox(idx)
                                        }
                                    }
                                    .padding()
                                } else {
                                    HStack(alignment: flexAlignMap(alignItems), spacing: 10) {
                                        let items = [1, 2, 3]
                                        let orderedItems = isReverse ? items.reversed() : items
                                        ForEach(orderedItems, id: \.self) { idx in
                                            previewBox(idx)
                                        }
                                    }
                                    .padding()
                                }
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func previewBox(_ num: Int) -> some View {
        Text("Item \(num)")
            .font(.caption.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange)
            .cornerRadius(6)
    }

    private func flexAlignMap(_ alignment: String) -> VerticalAlignment {
        switch alignment {
        case "flex-start": return .top
        case "flex-end": return .bottom
        case "center": return .center
        default: return .center
        }
    }

    private func flexAlignMap(_ alignment: String) -> HorizontalAlignment {
        switch alignment {
        case "flex-start": return .leading
        case "flex-end": return .trailing
        case "center": return .center
        default: return .center
        }
    }
}
