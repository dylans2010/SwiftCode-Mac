import SwiftUI

struct TemplatePickerView: View {
    @Binding var selected: ProjectTemplate
    let templates: [ProjectTemplate] = [
        MacOSAppTemplate(),
        MultiplatformAppTemplate(),
        DocumentAppTemplate(),
        MenuBarAppTemplate(),
        SwiftPackageTemplate(),
        CommandLineToolTemplate(),
        FrameworkTemplate(),
        GameMetalTemplate(),
        GameSpriteKitTemplate(),
        SwiftMacroTemplate(),
        SafariExtensionTemplate(),
        SystemExtensionTemplate(),
        SwiftUIViewLibraryTemplate(),
        StaticLibraryTemplate()
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    ForEach(templates, id: \.name) { template in
                        VStack {
                            Image(systemName: template.icon)
                                .font(.system(size: 30))
                                .frame(width: 60, height: 60)
                                .background(selected.name == template.name ? Color.accentColor : Color.secondary.opacity(0.1))
                                .foregroundColor(selected.name == template.name ? .white : .primary)
                                .cornerRadius(10)

                            Text(template.name)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .frame(width: 80)
                        .onTapGesture {
                            selected = template
                        }
                    }
                }
                .padding(.vertical, 5)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(selected.name)
                    .font(.headline)
                Text(selected.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 5)
        }
    }
}
