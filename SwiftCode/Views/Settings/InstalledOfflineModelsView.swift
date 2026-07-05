import SwiftUI

struct InstalledOfflineModelsView: View {
    @ObservedObject var manager = OfflineModelManager.shared

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        Section("Installed Models") {
            if manager.installedModelRecords.isEmpty {
                Text("No Local Models Installed")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(manager.installedModelRecords) { model in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.modelName)
                            .font(.subheadline.weight(.semibold))

                        HStack {
                            Label(model.folderName, systemImage: "folder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(model.sizeDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Label("Added: \(dateFormatter.string(from: model.installDate))", systemImage: "calendar")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Label("Tokens: \(model.metadata.tokenCount)", systemImage: "number")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        if let validation = model.validationStatus {
                            Text(validation)
                                .font(.caption2)
                                .foregroundStyle(validation.hasPrefix("Error") ? .red : .secondary)
                        }

                        HStack(spacing: 8) {
                            Button {
                                Task {
                                    await testModel(model)
                                }
                            } label: {
                                Label("Test", systemImage: "waveform.path.ecg")
                            }
                            .buttonStyle(.bordered)

                            Button(role: .destructive) {
                                deleteModel(model)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 2)
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
