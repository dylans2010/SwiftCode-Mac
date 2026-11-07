import SwiftUI

struct UUIDGeneratorView: View {
    @State private var count = 1
    @State private var uuids: [String] = [UUID().uuidString]
    @State private var useUppercase = true

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Stepper("Quantity: \(count)", value: $count, in: 1...50)

                Toggle("Uppercase", isOn: $useUppercase)
                    .padding(.leading)

                Spacer()

                Button("Generate") { generate() }
                    .buttonStyle(.borderedProminent)
            }
            .padding([.top, .horizontal])

            List(uuids, id: \.self) { uuid in
                Text(useUppercase ? uuid.uppercased() : uuid.lowercased())
                    .font(.system(.body, design: .monospaced))
                    .contextMenu {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(useUppercase ? uuid.uppercased() : uuid.lowercased(), forType: .string)
                        }
                    }
            }

            HStack {
                Button("Copy All") {
                    let all = uuids.map { useUppercase ? $0.uppercased() : $0.lowercased() }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(all, forType: .string)
                }
                Spacer()
            }
            .padding([.bottom, .horizontal])
        }
        .navigationTitle("UUID Generator")
    }

    func generate() {
        uuids = (0..<count).map { _ in UUID().uuidString }
    }
}
