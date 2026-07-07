import SwiftUI

struct MIMETypeLookupView: View {
    @State private var query = ".png"
    @State private var result = "image/png"

    var body: some View {
        VStack(spacing: 20) {
            TextField("Search extension (e.g. .json) or MIME type (e.g. application/pdf)", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding()
                .onChange(of: query) { lookup() }

            VStack(alignment: .leading, spacing: 10) {
                Text("Result:")
                    .font(.headline)
                Text(result)
                    .font(.system(.title2, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding()

            Spacer()
        }
        .navigationTitle("MIME Type Lookup")
    }

    func lookup() {
        let mapping = [
            ".html": "text/html",
            ".css": "text/css",
            ".js": "application/javascript",
            ".json": "application/json",
            ".png": "image/png",
            ".jpg": "image/jpeg",
            ".pdf": "application/pdf",
            ".zip": "application/zip",
            ".txt": "text/plain"
        ]
        result = mapping[query.lowercased()] ?? "Unknown MIME type"
    }
}
