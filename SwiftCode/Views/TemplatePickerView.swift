import SwiftUI

struct TemplatePickerView: View {
    @Binding var selected: String
    let templates = ["macOS App", "Swift Package", "Command Line Tool", "Framework"]

    var body: some View {
        Picker("Template", selection: $selected) {
            ForEach(templates, id: \.self) {
                Text($0)
            }
        }
        .pickerStyle(.radioGroup)
    }
}
