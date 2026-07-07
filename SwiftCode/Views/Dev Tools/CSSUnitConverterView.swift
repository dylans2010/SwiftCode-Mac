import SwiftUI

struct CSSUnitConverterView: View {
    @State private var pixels = "16"
    @State private var baseSize = "16"
    @State private var rem = "1"
    @State private var em = "1"

    var body: some View {
        VStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Base Font Size (px)")
                    .font(.caption)
                TextField("16", text: $baseSize)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: baseSize) { convert() }
            }
            .padding([.top, .horizontal])

            Divider()

            VStack(spacing: 20) {
                UnitRow(label: "Pixels (px)", value: $pixels) { convertFromPx() }
                UnitRow(label: "REM", value: $rem) { convertFromRem() }
                UnitRow(label: "EM", value: $em) { convertFromEm() }
            }
            .padding(.horizontal)

            Spacer()
        }
        .navigationTitle("CSS Unit Converter")
    }

    func convert() {
        convertFromPx()
    }

    func convertFromPx() {
        guard let p = Double(pixels), let b = Double(baseSize), b > 0 else { return }
        rem = String(format: "%.3f", p / b)
        em = rem
    }

    func convertFromRem() {
        guard let r = Double(rem), let b = Double(baseSize) else { return }
        pixels = String(format: "%.0f", r * b)
        em = rem
    }

    func convertFromEm() {
        guard let e = Double(em), let b = Double(baseSize) else { return }
        pixels = String(format: "%.0f", e * b)
        rem = em
    }
}

struct UnitRow: View {
    let label: String
    @Binding var value: String
    var onCommit: () -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(.headline)
                .frame(width: 100, alignment: .leading)
            TextField("", text: $value, onCommit: onCommit)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
    }
}
