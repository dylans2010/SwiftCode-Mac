import SwiftUI

struct TemplatePickerView: View {
    @Binding var selected: String
    let templates = [
        TemplateInfo(name: "SwiftUI App", icon: "app"),
        TemplateInfo(name: "macOS App", icon: "desktopcomputer"),
        TemplateInfo(name: "Swift Package", icon: "shippingbox"),
        TemplateInfo(name: "Command Line Tool", icon: "terminal"),
        TemplateInfo(name: "Framework", icon: "briefcase")
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 15) {
                ForEach(templates, id: \.name) { template in
                    VStack {
                        Image(systemName: template.icon)
                            .font(.system(size: 30))
                            .frame(width: 60, height: 60)
                            .background(selected == template.name ? Color.accentColor : Color.secondary.opacity(0.1))
                            .foregroundColor(selected == template.name ? .white : .primary)
                            .cornerRadius(10)

                        Text(template.name)
                            .font(.caption)
                    }
                    .onTapGesture {
                        selected = template.name
                    }
                }
            }
            .padding(.vertical, 5)
        }
    }
}

struct TemplateInfo {
    let name: String
    let icon: String
}
