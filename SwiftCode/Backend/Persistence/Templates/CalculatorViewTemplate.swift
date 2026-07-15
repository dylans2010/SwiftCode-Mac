import Foundation

public struct CalculatorViewTemplate: ProjectScaffoldTemplate {
    public let name = "Calculator View"
    public let description = "A simple mathematical utility grid with number inputs and operators."
    public let icon = "divide.circle"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct CalculatorApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack(spacing: 12) {\n            Text(\"0\").font(.system(size: 48)).frame(maxWidth: .infinity, alignment: .trailing).padding()\n            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {\n                ForEach([\"7\",\"8\",\"9\",\"/\",\"4\",\"5\",\"6\",\"*\",\"1\",\"2\",\"3\",\"-\",\"0\",\".\",\"=\",\"+\"], id: \\.self) { btn in\n                    Text(btn).font(.title).frame(width: 48, height: 48).background(Color.secondary.opacity(0.15)).cornerRadius(10)\n                }\n            }\n        }\n        .frame(width: 240)\n        .padding()\n    }\n}")
    ]
}
