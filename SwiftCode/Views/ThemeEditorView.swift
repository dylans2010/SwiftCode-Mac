import SwiftUI

struct ThemeEditorView: View {
    @State var theme: EditorTheme

    var body: some View {
        Form {
            Section("Colors") {
                ColorPicker("Background", selection: .constant(.black))
                ColorPicker("Foreground", selection: .constant(.white))
                ColorPicker("Keyword", selection: .constant(.blue))
                ColorPicker("String", selection: .constant(.orange))
            }
            Section("Info") {
                TextField("Name", text: .constant(theme.name))
            }
        }
        .padding()
    }
}
