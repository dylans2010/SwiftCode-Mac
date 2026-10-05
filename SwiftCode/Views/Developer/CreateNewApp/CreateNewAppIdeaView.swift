import SwiftUI

public struct CreateNewAppIdeaView: View {
    @Binding public var config: CreateAppConfiguration

    public init(config: Binding<CreateAppConfiguration>) {
        self._config = config
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("1. Describe Your Application Idea")
                .font(.title2.bold())

            Text("Describe what you want Assist to build. You can be as concise or detailed as you like.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $config.applicationDescription)
                .font(.body)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .frame(minHeight: 180)

            VStack(alignment: .leading, spacing: 8) {
                Text("Inspiration & Ideas:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ExampleChip(title: "Notes App with Markdown & Local JSON") {
                        config.applicationDescription = "Build a lightweight notes app with a sidebar list, search filter, rich Markdown editor, auto-saving local JSON storage, and dark mode support."
                        if config.appName.isEmpty { config.appName = "My Notes" }
                    }
                    ExampleChip(title: "Weather Dashboard with Forecast Cards") {
                        config.applicationDescription = "Build a weather utility application featuring location selection, current condition summary cards, hourly scrollable forecast, and daily forecast table."
                        if config.appName.isEmpty { config.appName = "WeatherNow" }
                    }
                    ExampleChip(title: "Task & Project Manager") {
                        config.applicationDescription = "Build a task manager with project folders, task priorities, due dates, filterable completed list, search, and local persistence."
                        if config.appName.isEmpty { config.appName = "TaskFlow" }
                    }
                }
            }

            Spacer()
        }
    }
}

private struct ExampleChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .foregroundStyle(.blue)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
