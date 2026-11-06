// ThemeGalleryView.swift
//
// Ported from Legacy `SwiftCode/Views/ThemeGalleryView.swift` (SwiftCode-Mac migration, Views/UI worklist).
// Worklist verdict: PARTIAL.
// Missing behaviour ported: visual card grid gallery of themes
// References legacy types absent from the destination and from this worklist (wiring/integration gaps): ThemeViewModel.
// Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
import SwiftUI

struct ThemeGalleryView: View {
    @Bindable var viewModel: ThemeViewModel

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 20) {
                ForEach(viewModel.themes) { theme in
                    Button {
                        viewModel.currentTheme = theme
                    } label: {
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
                        .padding(10)
                        .liquidGlass(
                            style: viewModel.currentTheme.id == theme.id ? .prominent : .standard,
                            cornerRadius: 14,
                            tint: viewModel.currentTheme.id == theme.id ? .accentColor : nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .liquidGlass(style: .sheet, cornerRadius: 0)
        .navigationTitle("Theme Gallery")
    }
}
