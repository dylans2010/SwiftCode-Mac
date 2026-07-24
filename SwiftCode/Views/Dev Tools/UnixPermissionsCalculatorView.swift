import SwiftUI

public struct UnixPermissionsCalculatorView: View {
    // Owner
    @State private var uRead = true
    @State private var uWrite = true
    @State private var uExec = true

    // Group
    @State private var gRead = true
    @State private var gWrite = false
    @State private var gExec = true

    // Others
    @State private var oRead = true
    @State private var oWrite = false
    @State private var oExec = false

    public init() {}

    private var ownerScore: Int {
        (uRead ? 4 : 0) + (uWrite ? 2 : 0) + (uExec ? 1 : 0)
    }

    private var groupScore: Int {
        (gRead ? 4 : 0) + (gWrite ? 2 : 0) + (gExec ? 1 : 0)
    }

    private var otherScore: Int {
        (oRead ? 4 : 0) + (oWrite ? 2 : 0) + (oExec ? 1 : 0)
    }

    private var octalNotation: String {
        "\(ownerScore)\(groupScore)\(otherScore)"
    }

    private var symbolicNotation: String {
        let owner = (uRead ? "r" : "-") + (uWrite ? "w" : "-") + (uExec ? "x" : "-")
        let group = (gRead ? "r" : "-") + (gWrite ? "w" : "-") + (gExec ? "x" : "-")
        let other = (oRead ? "r" : "-") + (oWrite ? "w" : "-") + (oExec ? "x" : "-")
        return owner + group + other
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("UNIX File Permissions Calculator")
                        .font(.title.bold())
                    Text("Interactively design file permission bits and calculate octal notations, symbolic codes, and chmod CLI flags.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 20) {
                    // Octal and Symbolic output display card
                    GroupBox {
                        VStack(spacing: 12) {
                            Text("Calculated Permission Flags")
                                .font(.headline)

                            HStack(spacing: 24) {
                                VStack {
                                    Text("OCTAL")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(octalNotation)
                                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                                        .foregroundColor(.orange)
                                }

                                Divider().frame(height: 50)

                                VStack {
                                    Text("SYMBOLIC")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(symbolicNotation)
                                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding()

                            Divider()

                            VStack(alignment: .leading, spacing: 6) {
                                Text("CHMOD SHELL COMMAND")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                                Text("chmod \(octalNotation) filepath.swift")
                                    .font(.system(.body, design: .monospaced))
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.15))
                                    .cornerRadius(6)
                            }
                        }
                        .padding(10)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                    .frame(width: 320)

                    // Selection columns
                    GroupBox {
                        HStack(alignment: .top, spacing: 24) {
                            // User
                            permissionColumn(title: "Owner (User)", r: $uRead, w: $uWrite, x: $uExec)
                            Divider()
                            // Group
                            permissionColumn(title: "Group", r: $gRead, w: $gWrite, x: $gExec)
                            Divider()
                            // Others
                            permissionColumn(title: "Others", r: $oRead, w: $oWrite, x: $oExec)
                        }
                        .padding(10)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func permissionColumn(title: String, r: Binding<Bool>, w: Binding<Bool>, x: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.orange)

            Toggle("Read (r, value 4)", isOn: r)
                .toggleStyle(.checkbox)
            Toggle("Write (w, value 2)", isOn: w)
                .toggleStyle(.checkbox)
            Toggle("Execute (x, value 1)", isOn: x)
                .toggleStyle(.checkbox)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
