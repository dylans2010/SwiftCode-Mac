import YcodeIDECore
import SwiftUI

@MainActor
public struct GitBlameExtensionView: View {
    @AppStorage("swiftcode.blame.showInline") private var showInlineBlame = false
    @AppStorage("swiftcode.blame.dateFormat") private var dateFormatRaw = GitBlameSettings.DateFormat.relative.rawValue
    @AppStorage("swiftcode.blame.showAuthorAvatar") private var showAuthorAvatar = false

    public init() {}

    public var body: some View {
        Form {
            Section("Inline Blame") {
                Toggle("Show Inline Blame", isOn: $showInlineBlame)
                Toggle("Show Author Avatar", isOn: $showAuthorAvatar)
                Picker("Date Format", selection: $dateFormatRaw) {
                    ForEach(GitBlameSettings.DateFormat.allCases, id: \.rawValue) { format in
                        Text(format.displayName).tag(format.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Text("Inline blame shows the last commit's author and date in the editor gutter. When Show Author Avatar is on, the author's initials appear beside each annotation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
