import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct AdvancedToolScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content()
                }
                .padding(20)
            }
            .background {
                #if canImport(AppKit)
                VisualEffectView(material: .contentBackground, blendingMode: .withinWindow)
                #else
                Color(uiColor: .systemBackground)
                #endif
            }
            .navigationTitle(title)
        }
    }
}

struct AdvancedToolCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(style: .standard, cornerRadius: 14)
    }
}

struct MetricPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(style: .subtle, cornerRadius: 12, tint: .accentColor)
    }
}
