import SwiftUI

struct ProjectTreeRowView: View {
    let node: ProjectNode

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            Text(node.url.lastPathComponent)
        }
    }

    private var iconName: String {
        if node.kind == .folder {
            return "folder"
        }
        if let provider = LanguageManager.shared.provider(for: node.url) {
            return provider.iconName
        }
        return "doc"
    }

    private var iconColor: Color {
        if node.kind == .folder {
            return .blue
        }
        if let provider = LanguageManager.shared.provider(for: node.url) {
            return LanguageManager.shared.color(for: provider.iconColorName)
        }
        return .secondary
    }
}

