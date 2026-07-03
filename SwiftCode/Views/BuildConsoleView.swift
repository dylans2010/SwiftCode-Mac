import SwiftUI

struct BuildConsoleView: View {
    @State var viewModel: BuildViewModel

    var body: some View {
        ScrollView {
            Text(viewModel.buildLog)
                .font(.monospacedSystemFont(ofSize: 11, weight: .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(Color.black)
        .foregroundStyle(.white)
    }
}
