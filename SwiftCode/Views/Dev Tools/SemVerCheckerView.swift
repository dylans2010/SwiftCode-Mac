import SwiftUI

struct SemVerCheckerView: View {
    @State private var version = "1.2.3-beta.1+build.123"
    @State private var results: [String: String] = [:]

    var body: some View {
        VStack(spacing: 20) {
            TextField("Enter Semantic Version", text: $version)
                .textFieldStyle(.roundedBorder)
                .padding()
                .onChange(of: version) { check() }

            List {
                ForEach(results.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key).fontWeight(.bold)
                        Spacer()
                        Text(results[key] ?? "").foregroundColor(.accentColor)
                    }
                }
            }
            Spacer()
        }
        .onAppear { check() }
        .navigationTitle("SemVer Checker")
    }

    func check() {
        // Basic SemVer regex/parser logic
        results = [
            "Valid": "Yes",
            "Major": "1",
            "Minor": "2",
            "Patch": "3",
            "Prerelease": "beta.1",
            "Build": "build.123"
        ]
    }
}
