import SwiftUI

struct ThemeGalleryView: View {
    @State var viewModel: ThemeViewModel

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 20) {
                ForEach(viewModel.themes) { theme in
                    VStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: theme.background))
                            .frame(height: 120)
                            .overlay(
                                Text("Aa")
                                    .font(.title)
                                    .foregroundStyle(Color(hex: theme.foreground))
                            )
                        Text(theme.name)
                    }
                    .onTapGesture {
                        viewModel.currentTheme = theme
                    }
                    .padding(8)
                    .background(viewModel.currentTheme.id == theme.id ? Color.accentColor.opacity(0.1) : Color.clear)
                    .cornerRadius(12)
                }
            }
            .padding()
        }
    }
}
