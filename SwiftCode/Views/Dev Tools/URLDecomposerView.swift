import SwiftUI

struct URLDecomposerView: View {
    @State private var urlString = "https://user:pass@example.com:8080/path/to/resource?query=value#fragment"
    @State private var components: [String: String] = [:]

    var body: some View {
        VStack(spacing: 20) {
            TextField("Enter URL", text: $urlString)
                .textFieldStyle(.roundedBorder)
                .padding()
                .onChange(of: urlString) { decompose() }

            List {
                ForEach(components.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key)
                            .fontWeight(.bold)
                            .frame(width: 100, alignment: .leading)
                        Text(components[key] ?? "")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.accentColor)
                    }
                }
            }

            Spacer()
        }
        .onAppear { decompose() }
        .navigationTitle("URL Decomposer")
    }

    func decompose() {
        guard let url = URL(string: urlString) else {
            components = ["Error": "Invalid URL"]
            return
        }

        components = [
            "Scheme": url.scheme ?? "",
            "Host": url.host ?? "",
            "Port": url.port != nil ? "\(url.port!)" : "",
            "Path": url.path,
            "Query": url.query ?? "",
            "Fragment": url.fragment ?? "",
            "User": url.user ?? "",
            "Password": url.password ?? ""
        ]
    }
}
