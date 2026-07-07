import SwiftUI

struct JWTDecoderView: View {
    @State private var jwtInput = ""
    @State private var header = ""
    @State private var payload = ""
    @State private var error = ""

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading) {
                Text("JWT Token")
                    .font(.headline)
                TextEditor(text: $jwtInput)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 150)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .onChange(of: jwtInput) { decodeJWT() }
            }

            if !error.isEmpty {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Header")
                        .font(.headline)
                    TextEditor(text: .constant(header))
                        .font(.system(.body, design: .monospaced))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }

                VStack(alignment: .leading) {
                    Text("Payload")
                        .font(.headline)
                    TextEditor(text: .constant(payload))
                        .font(.system(.body, design: .monospaced))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
            }
        }
        .padding()
        .navigationTitle("JWT Decoder")
    }

    func decodeJWT() {
        error = ""
        header = ""
        payload = ""

        let segments = jwtInput.components(separatedBy: ".")
        guard segments.count == 3 else {
            if !jwtInput.isEmpty { error = "JWT must have 3 segments separated by dots" }
            return
        }

        header = decodeSegment(segments[0]) ?? "Invalid Header"
        payload = decodeSegment(segments[1]) ?? "Invalid Payload"
    }

    func decodeSegment(_ segment: String) -> String? {
        var base64 = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let length = Double(base64.lengthOfBytes(using: .utf8))
        let requiredLength = 4 * ceil(length / 4.0)
        let paddingLength = Int(requiredLength) - base64.count
        if paddingLength > 0 {
            base64 += String(repeating: "=", count: paddingLength)
        }

        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return String(data: data, encoding: .utf8)
        }

        return prettyString
    }
}
