import SwiftUI

// MARK: - Project Notes tab (Wave 19 slice A)
//
// The Documentation Browser's Project Notes tab. Legacy's
// workspace had a Project Notes tab backed by
// `ProjectNotesWorkspaceView` — one of the 3 missing Legacy Swift
// files, owned by another slice. This tab does not reimplement it
// here (a duplicate would drift); it says so plainly and points
// at the owner.
//
// Spec: `specs/ide/wave19-docs.md` §6.

struct DocumentationProjectNotesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Project Notes")
                .font(.title2.bold())
            Text("Project Notes are not available in this browser yet.")
                .font(.callout)
            Text("The notes workspace (`ProjectNotesWorkspaceView`) is one of the remaining Legacy files being ported in its own slice; this tab will host it once it lands. Nothing is shown here in the meantime rather than a placeholder notes list.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
