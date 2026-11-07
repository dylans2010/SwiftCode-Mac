import SwiftUI

enum PhoneModel {
    static let title = "HostPhone"
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
            Text(PhoneModel.title)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
