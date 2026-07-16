import SwiftUI

struct InstalledOfflineModelsView: View {
    @ObservedObject var manager = OfflineModelManager.shared

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if manager.installedModelRecords.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "externaldrive.badge.xmark")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("No Local Models Installed")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Download models from Hugging Face or via direct link.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
            } else {
                ForEach(manager.installedModelRecords) { model in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.modelName)
                                    .font(.title3.bold())
                                    .foregroundStyle(.primary)

                                HStack(spacing: 8) {
                                    Label(model.folderName, systemImage: "folder")
                                    Text("•")
                                    Label("Tokens: \(model.metadata.tokenCount)", systemImage: "number")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()

                            Text(model.sizeDescription)
                                .font(.subheadline.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.blue)
                        }

                        Divider()

                        HStack {
                            Label("Installed: \(dateFormatter.string(from: model.installDate))", systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        if let validation = model.validationStatus {
                            HStack(spacing: 6) {
                                Image(systemName: validation.hasPrefix("Error") ? "exclamationmark.octagon.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(validation.hasPrefix("Error") ? .red : .green)
                                Text(validation)
                                    .font(.caption)
                                    .foregroundStyle(validation.hasPrefix("Error") ? .red : .secondary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(validation.hasPrefix("Error") ? Color.red.opacity(0.08) : Color.green.opacity(0.06))
                            .cornerRadius(8)
                        }

                        HStack(spacing: 12) {
                            Button {
                                Task {
                                    await testModel(model)
                                }
                            } label: {
                                Label("Run Diagnostics", systemImage: "waveform.path.ecg")
                                    .font(.subheadline.bold())
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)

                            Button(role: .destructive) {
                                deleteModel(model)
                            } label: {
                                Label("Remove Model", systemImage: "trash")
                                    .font(.subheadline.bold())
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }
                        .padding(.top, 4)
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 2)
                }
            }
        }
    }

    private func deleteModel(_ model: InstalledOfflineModelRecord) {
        let metadata = OfflineModelMetadata(
            modelName: model.modelName,
            providerName: "Offline",
            description: "Locally Stored Model",
            modelSize: model.sizeDescription,
            modelSizeBytes: model.metadata.totalSize,
            tags: ["offline", "installed"],
            downloadCount: 0,
            modelURL: URL(fileURLWithPath: model.localModelPath),
            files: [],
            isQuantized: false
        )
        manager.removeModel(metadata)
    }

    private func testModel(_ model: InstalledOfflineModelRecord) async {
        do {
            try await OfflineModelRunner.shared.loadModel(at: URL(fileURLWithPath: model.localModelPath))
            let reply = try await OfflineModelRunner.shared.generateResponse(prompt: "Hello from SwiftCode")
            let trimmedReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedReply.isEmpty {
                manager.updateValidationStatus(for: model.modelName, status: "Error: Empty response", clearLocalPath: false)
            } else {
                manager.updateValidationStatus(for: model.modelName, status: "Valid: \(trimmedReply.prefix(60))", clearLocalPath: false)
            }
        } catch {
            manager.updateValidationStatus(for: model.modelName, status: "Error: \(error.localizedDescription)", clearLocalPath: false)
        }
    }
}
