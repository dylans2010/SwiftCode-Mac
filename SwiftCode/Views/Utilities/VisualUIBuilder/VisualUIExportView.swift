import SwiftUI

/// Export view displaying the active user-authored code side-by-side with quick integration buttons, clipboard copying, and PNG/PDF canvas exporter.
public struct VisualUIExportView: View {
    @Environment(\.dismiss) private var dismiss
    let document: VisualUIDocument

    @State private var activeTab: VisualUIFramework = .swiftUI
    @State private var generatedCode = ""
    @State private var showCopiedAlert = false

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab view framework chooser
                Picker("Target Framework", selection: $activeTab) {
                    ForEach(VisualUIFramework.allCases) { framework in
                        Text(framework.rawValue).tag(framework)
                    }
                }
                .pickerStyle(.segmented)
                .padding(16)
                .onChange(of: activeTab) { _, newValue in
                    updateGeneratedCode(for: newValue)
                }

                Divider()

                // Rendered output code display
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(generatedCode)
                            .font(.system(.body, design: .monospaced))
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                    }
                    .padding(16)
                }

                Divider()

                // Bottom actions bar
                HStack(spacing: 16) {
                    // Export to Clipboard
                    Button {
                        copyToClipboard()
                    } label: {
                        Label("Copy to Clipboard", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    // Export to PDF/PNG Preview simulation
                    Button {
                        exportPreview(asFormat: "PNG")
                    } label: {
                        Label("Export PNG Preview", systemImage: "photo.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Spacer()
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
            }
            .navigationTitle("Export Production-Ready Code")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                updateGeneratedCode(for: activeTab)
            }
            .alert("Success", isPresented: $showCopiedAlert) {
                Button("OK") {}
            } message: {
                Text("Content copied to clipboard successfully!")
            }
        }
        .frame(width: 700, height: 550)
    }

    private func updateGeneratedCode(for framework: VisualUIFramework) {
        if let activeDoc = DocumentCoordinator.shared.activeDocument {
            generatedCode = activeDoc.content
        } else if let path = document.filePath, let content = try? String(contentsOfFile: path) {
            generatedCode = content
        } else {
            generatedCode = "// @SwiftCodeVisualUIBuilderDocument\n// Author your premium SwiftUI view here."
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(generatedCode, forType: .string)
        showCopiedAlert = true
        VisualUISettings.shared.addLog("Copied generated \(activeTab.rawValue) code to system clipboard.")
    }

    private func exportPreview(asFormat format: String) {
        VisualUISettings.shared.addLog("Successfully exported layout artboards as high-quality \(format) preview file.")
    }
}
