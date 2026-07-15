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
        VStack(alignment: .leading, spacing: 12) {
            if manager.installedModelRecords.isEmpty {
                Text("No Local Models Installed")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(manager.installedModelRecords) { model in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(model.modelName)
                                .font(.headline)
                            Spacer()
                            Text(model.sizeDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 16) {
                            Label(model.folderName, systemImage: "folder")
                            Spacer()
                            Label("Tokens: \(model.metadata.tokenCount)", systemImage: "number")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        HStack {
                            Label("Added: \(dateFormatter.string(from: model.installDate))", systemImage: "calendar")
                            Spacer()
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                        if let validation = model.validationStatus {
                            Text(validation)
                                .font(.caption2)
                                .foregroundStyle(validation.hasPrefix("Error") ? .red : .secondary)
                                .padding(6)
                                .background(validation.hasPrefix("Error") ? Color.red.opacity(0.12) : Color.primary.opacity(0.06))
                                .cornerRadius(6)
                        }

                        HStack(spacing: 12) {
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
                        .padding(.top, 4)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(10)
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
