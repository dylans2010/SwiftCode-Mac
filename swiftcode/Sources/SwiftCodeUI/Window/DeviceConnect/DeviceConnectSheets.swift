// DeviceConnectSheets.swift
//
// Ported from Legacy `SwiftCode/Views/Build/DeviceConnectKit/Views/Sheets/DeviceConnectSheets.swift` (SwiftCode-Mac migration, Views/UI worklist).
// Worklist verdict: PARTIAL.
// Missing behaviour ported: diagnostics sheet presentation; Copy to Clipboard action
// Legacy source: in-repo SwiftCode-Legacy/ lacks this file; ported from the earlier staging copy at ~/SwiftCode-Migration-Workspace/staging/SwiftCode/Views/Build/DeviceConnectKit/Views/Sheets/DeviceConnectSheets.swift (derived from Legacy).
// Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
import SwiftUI

struct DeviceDiagnosticsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let reportText: String

    var body: some View {
        NavigationStack {
            VStack {
                ScrollView {
                    Text(reportText)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding()

                HStack {
                    Button("Copy to Clipboard") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(reportText, forType: .string)
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.bottom)
                .liquidGlass(style: .subtle, cornerRadius: 12)
            }
            .navigationTitle("Diagnostics Analyzer")
        }
        .frame(width: 500, height: 600)
    }
}
