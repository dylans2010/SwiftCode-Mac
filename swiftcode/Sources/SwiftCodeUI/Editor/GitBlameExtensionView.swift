import SwiftCodeIDECore
import SwiftUI

/// Ported from SwiftCode-Legacy `SwiftCode/Views/GitHub/GitBlameExtensionView.swift`
/// (Dylan's own code; direct port authorised under MIT).
///
/// Blame (Authors column) settings. Legacy's view kept its toggles in
/// un-persisted `@State`, so changing them did nothing; this port persists
/// every setting through `GitBlameSettings` (UserDefaults) and the settings
/// take real effect:
///
/// - Show Inline Blame: new editors open with the Authors column shown
///   (`GutterView.showsAuthors` defaults to the setting; the Editor ▸
///   Authors menu still toggles it per editor).
/// - Date Format: `GitBlame.annotation` renders the commit date as relative
///   ("2d ago"), absolute ("Nov 6, 2026 at 1:03 PM"), or the short hash.
/// - Show Author Avatar: persisted, but the gutter draws text annotations
///   today — rendering avatars in the gutter column needs an avatar column
///   in `GutterView.drawAuthors` plus an avatar cache, and is a remaining
///   wiring task (the setting is stored so the preference survives).
///
/// Hook: add this view to the editor/source-control settings pane.
@MainActor
public struct GitBlameExtensionView: View {
    // Literals match `GitBlameSettings`' keys (the keys are the single
    // source of truth; `@AppStorage` needs a literal key here).
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
                Text("Inline blame shows the last commit's author and date in the editor gutter. The avatar toggle is saved now; avatar drawing in the gutter is not implemented yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
