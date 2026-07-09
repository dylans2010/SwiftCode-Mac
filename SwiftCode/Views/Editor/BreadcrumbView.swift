import SwiftUI

struct BreadcrumbView: View {
    let url: URL
    let projectRoot: URL?

    private var relativeComponents: [String] {
        guard let projectRoot = projectRoot else { return url.pathComponents }
        let rootPath = projectRoot.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path

        if filePath.hasPrefix(rootPath) {
            let relative = String(filePath.dropFirst(rootPath.count))
            return relative.split(separator: "/").map(String.init)
        }
        return url.pathComponents
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(relativeComponents.indices, id: \.self) { index in
                let component = relativeComponents[index]
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(component)
                    .font(.subheadline)
                    .foregroundStyle(index == url.pathComponents.count - 1 ? .primary : .secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.05))
        .cornerRadius(4)
    }
}
