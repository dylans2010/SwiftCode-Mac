import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "app.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("__APP_NAME__")
                .font(.title)
            Text("A SwiftCode standalone project. This is your own code — build, sign, and ship it with the normal Xcode workflow.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(minWidth: 380, minHeight: 240)
    }
}

#Preview {
    ContentView()
}
