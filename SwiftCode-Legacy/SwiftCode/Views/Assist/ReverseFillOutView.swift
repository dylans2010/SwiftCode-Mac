//
//  ReverseFillOutView.swift
//  SwiftCode
//
//  Compact popover Form for configuring @Reverse static reverse engineering analysis.
//

import SwiftUI
import AppKit

public struct ReverseFillOutView: View {
    @Binding public var isPresented: Bool
    public var onInsert: ((String) -> Void)?
    public var onSubmit: ((String) -> Void)?

    @State private var targetPath: String = ""
    @State private var operation: ReverseOperation = .inspectArtifact
    @State private var objdumpOperation: ReverseObjdumpOperation = .fileHeaders
    @State private var symbol: String = ""
    @State private var investigationQuery: String = ""

    public init(
        isPresented: Binding<Bool>,
        initialPath: String = "",
        onInsert: ((String) -> Void)? = nil,
        onSubmit: ((String) -> Void)? = nil
    ) {
        self._isPresented = isPresented
        self._targetPath = State(initialValue: initialPath)
        self.onInsert = onInsert
        self.onSubmit = onSubmit
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Reverse Static Analysis")
                        .font(.system(size: 12, weight: .bold))
                    Text("Configure @Reverse command parameters")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            Divider()

            // Form
            Form {
                Section("Target Artifact") {
                    HStack(spacing: 6) {
                        TextField("Absolute path to binary / file", text: $targetPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))

                        Button("Browse...") {
                            chooseFile()
                        }
                        .font(.system(size: 10.5))
                        .buttonStyle(.bordered)
                    }
                }

                Section("Analysis Operation") {
                    Picker("Operation", selection: $operation) {
                        ForEach(ReverseOperation.allCases, id: \.self) { op in
                            Text(op.displayName).tag(op)
                        }
                    }
                    .font(.system(size: 11))

                    if operation == .inspectWithObjdump {
                        Picker("Objdump Mode", selection: $objdumpOperation) {
                            ForEach(ReverseObjdumpOperation.allCases, id: \.self) { sub in
                                Text(sub.rawValue).tag(sub)
                            }
                        }
                        .font(.system(size: 11))
                    }

                    if operation == .demangleSwift || operation == .inspectManagedMembers {
                        TextField("Symbol / Member (optional)", text: $symbol)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                    }
                }

                Section("Investigation Query") {
                    TextField("What to investigate (e.g. check entitlements, exported symbols)", text: $investigationQuery)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }
            }
            .formStyle(.grouped)
            .font(.system(size: 11))
            .padding(.vertical, -4)

            Divider()

            // Footer
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .font(.system(size: 11))
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    let cmd = buildCommand()
                    onInsert?(cmd)
                    isPresented = false
                } label: {
                    Label("Insert", systemImage: "text.append")
                        .font(.system(size: 11, weight: .medium))
                }
                .disabled(targetPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    let cmd = buildCommand()
                    onSubmit?(cmd)
                    isPresented = false
                } label: {
                    Label("Run Analysis", systemImage: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(targetPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .frame(width: 360, height: 350)
    }

    private func buildCommand() -> String {
        var parts: [String] = ["@Reverse"]
        let trimmedPath = targetPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPath.isEmpty {
            parts.append(trimmedPath)
        }

        if operation == .inspectWithObjdump {
            parts.append("objdump \(objdumpOperation.rawValue)")
        } else if operation != .inspectArtifact {
            parts.append("op=\(operation.rawValue)")
        }

        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSymbol.isEmpty {
            parts.append("symbol=\(trimmedSymbol)")
        }

        let trimmedQuery = investigationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            parts.append(trimmedQuery)
        }

        return parts.joined(separator: " ")
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Artifact"
        if panel.runModal() == .OK, let url = panel.url {
            targetPath = url.path
        }
    }
}
