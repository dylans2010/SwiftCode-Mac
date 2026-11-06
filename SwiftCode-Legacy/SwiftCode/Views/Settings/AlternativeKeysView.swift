//
//  AlternativeKeysView.swift
//  SwiftCode
//
//  Dedicated management and rotation interface for alternative Gemini API keys.
//

import SwiftUI
import Observation

struct AlternativeKeysView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @State private var keyManager = AlternativeKeyManager.shared

    // Import state
    @State private var showImportSheet = false
    @State private var rawInputText = ""
    @State private var lastImportResult: KeyImportResult? = nil
    @State private var showDeleteAllAlert = false
    @State private var rotationNotice: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. Feature Enablement & Explanation
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Alternative Keys", systemImage: "key.fill")
                                    .font(.headline)
                                    .foregroundStyle(.blue)

                                Spacer()

                                Toggle("", isOn: $settings.alternativeKeysEnabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }

                            Text("Automatically rotate between saved Gemini API keys when a key encounters rate limits or quota exhaustion. During turn execution, Assist waits 2 seconds before seamlessly switching to the next available key without losing file modifications or conversation history.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if settings.alternativeKeysEnabled {
                                HStack(spacing: 8) {
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.green).frame(width: 6, height: 6)
                                        Text("\(keyManager.keys.count) keys saved")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.primary)
                                    }
                                    Text("·").font(.caption2).foregroundStyle(.secondary)
                                    let readyCount = keyManager.keys.filter { $0.isAvailableForUse }.count
                                    Text("\(readyCount) ready")
                                        .font(.caption2)
                                        .foregroundStyle(readyCount > 0 ? .green : .secondary)

                                    let rateLimitedCount = keyManager.keys.filter { $0.isCurrentlyRateLimited }.count
                                    if rateLimitedCount > 0 {
                                        Text("·").font(.caption2).foregroundStyle(.secondary)
                                        Text("\(rateLimitedCount) in cooldown")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .padding(14)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // 2. Action Controls
                    HStack(spacing: 10) {
                        Button {
                            showImportSheet = true
                        } label: {
                            Label("Add Keys", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)

                        Button {
                            if let rotated = keyManager.rotateNow() {
                                rotationNotice = "Rotated to \(rotated.maskedValue)"
                            } else {
                                rotationNotice = "No alternative keys available to rotate to"
                            }
                        } label: {
                            Label("Rotate Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(keyManager.keys.count < 2)

                        Button {
                            keyManager.resetHealth()
                            rotationNotice = "All key cooldowns reset"
                        } label: {
                            Label("Reset Cooldowns", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(keyManager.keys.isEmpty)

                        Spacer()

                        if !keyManager.keys.isEmpty {
                            Button(role: .destructive) {
                                showDeleteAllAlert = true
                            } label: {
                                Label("Clear All", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }
                    }

                    if let notice = rotationNotice {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            Text(notice)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Dismiss") {
                                rotationNotice = nil
                            }
                            .buttonStyle(.plain)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }

                    // 3. Saved Keys List
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Saved Keys (\(keyManager.keys.count))")
                                    .font(.headline)
                                Spacer()
                                Text("Drag to reorder rotation priority")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            if keyManager.keys.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "key.slash")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.secondary)
                                    Text("No alternative Gemini API keys configured.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text("Click 'Add Keys' to paste one or more Gemini API keys for seamless quota failover.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(Array(keyManager.keys.enumerated()), id: \.element.id) { index, key in
                                        HStack(spacing: 12) {
                                            // Priority index indicator
                                            Text("#\(index + 1)")
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 24, alignment: .leading)

                                            // Status indicator dot
                                            Circle()
                                                .fill(statusColor(for: key))
                                                .frame(width: 8, height: 8)

                                            // Masked key representation
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 6) {
                                                    Text(key.maskedValue)
                                                        .font(.system(size: 13, weight: .medium, design: .monospaced))

                                                    if keyManager.activeKeyId == key.id {
                                                        Text("ACTIVE")
                                                            .font(.system(size: 9, weight: .bold))
                                                            .padding(.horizontal, 5)
                                                            .padding(.vertical, 1)
                                                            .background(Color.green.opacity(0.15))
                                                            .foregroundStyle(.green)
                                                            .cornerRadius(3)
                                                    }
                                                }

                                                HStack(spacing: 8) {
                                                    Text(statusDescription(for: key))
                                                        .font(.caption2)
                                                        .foregroundStyle(statusColor(for: key))

                                                    if let last = key.lastUsed {
                                                        Text("·")
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                        Text("Used \(last.formatted(date: .omitted, time: .shortened))")
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }

                                                    if key.failureCount > 0 {
                                                        Text("·")
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                        Text("\(key.failureCount) failures")
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                            }

                                            Spacer()

                                            // Set Active action button
                                            if keyManager.activeKeyId != key.id && key.isAvailableForUse {
                                                Button("Set Active") {
                                                    keyManager.activeKeyId = key.id
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.mini)
                                            }

                                            // Delete key button
                                            Button {
                                                keyManager.removeKey(id: key.id)
                                            } label: {
                                                Image(systemName: "trash")
                                                    .font(.caption)
                                                    .foregroundStyle(.red.opacity(0.8))
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.leading, 4)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(keyManager.activeKeyId == key.id ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.02))
                                        )
                                    }
                                }
                            }
                        }
                        .padding(14)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(20)
            }
            .navigationTitle("Alternative Keys")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showImportSheet) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Add Gemini API Keys")
                            .font(.headline)

                        Text("Paste your Gemini API keys below. One key per line. Messy whitespace, duplicate keys, commas, and semicolons are automatically normalized.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $rawInputText)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 180)
                            .padding(8)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                        if let res = lastImportResult {
                            HStack(spacing: 8) {
                                Text("\(res.totalDetected) detected")
                                    .font(.caption.bold())
                                Text("·").font(.caption).foregroundStyle(.secondary)
                                Text("\(res.newKeysAdded) added")
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                                Text("·").font(.caption).foregroundStyle(.secondary)
                                Text("\(res.duplicatesRemoved) duplicates removed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if res.invalidKeysRejected > 0 {
                                    Text("·").font(.caption).foregroundStyle(.secondary)
                                    Text("\(res.invalidKeysRejected) invalid rejected")
                                        .font(.caption.bold())
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(8)
                            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }

                        HStack {
                            Button("Cancel") {
                                rawInputText = ""
                                lastImportResult = nil
                                showImportSheet = false
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button("Save Keys") {
                                let result = keyManager.importRawKeys(rawInputText)
                                lastImportResult = result
                                rawInputText = "" // Immediately clear sensitive text from memory
                                if result.newKeysAdded > 0 {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        showImportSheet = false
                                        lastImportResult = nil
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(rawInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(20)
                    .frame(minWidth: 500, minHeight: 360)
                }
            }
            .alert("Delete All Alternative Keys?", isPresented: $showDeleteAllAlert) {
                Button("Delete All", role: .destructive) {
                    keyManager.removeAllKeys()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove all alternative Gemini API keys from the secure system Keychain.")
            }
        }
        .frame(minWidth: 600, minHeight: 520)
    }

    private func statusColor(for key: AlternativeKeyMetadata) -> Color {
        if key.isCurrentlyRateLimited { return .orange }
        switch key.state {
        case .active: return .green
        case .ready: return .blue
        case .rateLimited: return .orange
        case .invalid: return .red
        case .failed: return .red
        case .disabled: return .secondary
        }
    }

    private func statusDescription(for key: AlternativeKeyMetadata) -> String {
        if key.isCurrentlyRateLimited {
            if let until = key.rateLimitedUntil {
                let remaining = max(1, Int(until.timeIntervalSince(Date())))
                return "Rate limited (cooling down: \(remaining)s)"
            }
            return "Rate limited"
        }
        switch key.state {
        case .active: return "Active"
        case .ready: return "Ready"
        case .rateLimited: return "Rate limited"
        case .invalid: return "Invalid API Key"
        case .failed: return "Failed"
        case .disabled: return "Disabled"
        }
    }
}
