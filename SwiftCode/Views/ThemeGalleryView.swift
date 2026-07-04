import SwiftUI

struct ThemeGalleryView: View {
    @Bindable var viewModel: ThemeViewModel

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 20) {
                ForEach(viewModel.themes) { theme in
                    VStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: theme.background))
                            .frame(height: 120)
                            .overlay(
                                VStack(spacing: 8) {
                                    Text("Aa")
                                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color(hex: theme.foreground))

                                    HStack(spacing: 4) {
                                        Circle().fill(Color(hex: theme.keywordColor)).frame(width: 8, height: 8)
                                        Circle().fill(Color(hex: theme.stringColor)).frame(width: 8, height: 8)
                                        Circle().fill(Color(hex: theme.typeColor)).frame(width: 8, height: 8)
                                    }
                                }
                            )
                            .shadow(radius: 2)

                        Text(theme.name)
                            .font(.headline)
                    }
                    .onTapGesture {
                        viewModel.currentTheme = theme
                    }
                    .padding(8)
                    .background(viewModel.currentTheme.id == theme.id ? Color.accentColor.opacity(0.1) : Color.clear)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(viewModel.currentTheme.id == theme.id ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Theme Gallery")
    }
}
