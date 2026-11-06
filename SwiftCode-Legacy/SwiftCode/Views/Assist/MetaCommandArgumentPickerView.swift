//
//  MetaCommandArgumentPickerView.swift
//  SwiftCode
//
//  Interactive UI for selecting arguments for Meta Code slash commands,
//  relieving users from manually typing command arguments.
//

import SwiftUI

public struct MetaCommandArgumentPickerView: View {
    public let command: MetaSlashCommand
    public let onSelect: (String) -> Void
    public let onDismiss: () -> Void

    @State private var selectedOption: String = ""
    @State private var textInput: String = ""

    public init(
        command: MetaSlashCommand,
        onSelect: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.command = command
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: command.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.orange)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(command.name)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.orange)

                        Text(command.category)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }

                    Text(command.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Arguments UI
            ForEach(command.arguments) { arg in
                switch arg {
                case .options(let name, let choices, let defaultValue):
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Select \(name):")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)

                        // Choices Grid / Flow Layout
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], spacing: 6) {
                            ForEach(choices, id: \.self) { choice in
                                Button {
                                    selectedOption = choice
                                    onSelect(choice)
                                } label: {
                                    HStack(spacing: 4) {
                                        if selectedOption == choice || (selectedOption.isEmpty && choice == defaultValue) {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 9, weight: .bold))
                                        }
                                        Text(choice)
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .background(
                                        (selectedOption == choice || (selectedOption.isEmpty && choice == defaultValue))
                                            ? Color.orange
                                            : Color.secondary.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                                    .foregroundStyle(
                                        (selectedOption == choice || (selectedOption.isEmpty && choice == defaultValue))
                                            ? Color.white
                                            : Color.primary
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                case .text(let name, let placeholder, let isOptional):
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(name)
                                .font(.system(size: 11, weight: .semibold))
                            if isOptional {
                                Text("(optional)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 6) {
                            TextField(placeholder, text: $textInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                                .onSubmit {
                                    let val = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !val.isEmpty || isOptional {
                                        onSelect(val)
                                    }
                                }

                            Button {
                                let val = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                onSelect(val)
                            } label: {
                                Text("Apply")
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 6))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .disabled(!isOptional && textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }

            // Syntax helper
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text("Syntax: \(command.syntax)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(width: 360)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
        .onAppear {
            for arg in command.arguments {
                if case .options(_, _, let def) = arg, let d = def {
                    selectedOption = d
                }
            }
        }
    }
}
