import Foundation
import SwiftUI

struct OllamaInstalledModel: Identifiable, Equatable, Hashable {
    var id: String { name }
    var name: String
    var size: Int64
    var modifiedAt: Date?
}

struct OllamaModelsView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var baseURL = OllamaModelsClient.defaultBaseURL
    @State private var models: [OllamaInstalledModel] = []
    @State private var selected: OllamaInstalledModel?
    @State private var downloadName = ""
    @State private var downloadProgress: Double?
    @State private var downloadStatus = ""
    @State private var isDownloading = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var serverReachable: Bool?
    @State private var downloadTask: Task<Void, Never>?

    var body: some View {
        let c = ShellColors(scheme)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Offline Models").font(ShellFonts.rowBold)
                Spacer()
                if let reachable = serverReachable {
                    Label(reachable ? "Ollama running" : "Ollama not reachable",
                          systemImage: reachable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(ShellFonts.small)
                        .foregroundStyle(reachable ? .green : .red)
                }
                Button("Refresh") { refresh() }
                    .disabled(isLoading)
            }
            .padding(10)
            HStack(spacing: 8) {
                TextField("Ollama URL", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(ShellFonts.small)
                Button("Apply") { refresh() }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            if let error = errorMessage {
                Text(verbatim: error)
                    .font(ShellFonts.small)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
            if serverReachable == false {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Install Ollama, then start it — this view talks to the local server at the URL above.")
                        .font(ShellFonts.small)
                        .foregroundStyle(c.secondaryLabel)
                    Text("macOS: download Ollama from ollama.com, or run `brew install ollama && ollama serve`. Then pull a model below, for example `qwen2.5-coder`.")
                        .font(ShellFonts.small)
                        .foregroundStyle(c.secondaryLabel)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            Hairline(color: c.separator)
            if models.isEmpty && serverReachable != false {
                ContentUnavailableView(
                    "No offline models",
                    systemImage: "cpu",
                    description: Text("No models are installed in Ollama yet. Pull one below to use it offline with the coding assistant.")
                )
            } else if !models.isEmpty {
                List {
                    ForEach(models) { model in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: model.name).font(ShellFonts.rowBold)
                            Text(verbatim: "\(ByteCountFormatter.string(fromByteCount: model.size, countStyle: .file))\(model.modifiedAt.map { " · \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")")
                                .font(ShellFonts.small)
                                .foregroundStyle(c.secondaryLabel)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selected = model }
                        .contextMenu {
                            Button("Delete Model", role: .destructive) { deleteModel(model) }
                        }
                    }
                }
                .listStyle(.plain)
            }
            Hairline(color: c.separator)
            VStack(alignment: .leading, spacing: 8) {
                Text("Download a model").font(ShellFonts.rowBold)
                HStack(spacing: 8) {
                    TextField("Model name, e.g. qwen2.5-coder", text: $downloadName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isDownloading)
                    if isDownloading {
                        Button("Cancel") { downloadTask?.cancel() }
                    } else {
                        Button("Pull") { startDownload() }
                            .buttonStyle(.borderedProminent)
                            .disabled(downloadName.trimmingCharacters(in: .whitespaces).isEmpty || serverReachable == false)
                    }
                    if selected != nil {
                        Button("Delete", role: .destructive) {
                            if let selected { deleteModel(selected) }
                        }
                        .disabled(isDownloading)
                    }
                }
                if let progress = downloadProgress {
                    ProgressView(value: progress)
                    Text(verbatim: downloadStatus)
                        .font(ShellFonts.small)
                        .foregroundStyle(c.secondaryLabel)
                } else if !downloadStatus.isEmpty {
                    Text(verbatim: downloadStatus)
                        .font(ShellFonts.small)
                        .foregroundStyle(c.secondaryLabel)
                }
            }
            .padding(10)
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let listed = try await OllamaModelsClient(baseURL: baseURL).listModels()
                models = listed
                serverReachable = true
            } catch {
                models = []
                serverReachable = false
                errorMessage = "Could not reach Ollama at \(baseURL): \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    private func startDownload() {
        let name = downloadName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isDownloading = true
        downloadProgress = 0
        downloadStatus = "Starting download of \(name)…"
        errorMessage = nil
        downloadTask = Task {
            do {
                try await OllamaModelsClient(baseURL: baseURL).pullModel(name: name) { progress, status in
                    downloadProgress = progress
                    downloadStatus = status
                }
                downloadStatus = "Downloaded \(name)."
                downloadProgress = nil
                downloadName = ""
                refresh()
            } catch is CancellationError {
                downloadStatus = "Download cancelled."
                downloadProgress = nil
            } catch {
                errorMessage = "Download failed: \(error.localizedDescription)"
                downloadProgress = nil
                downloadStatus = ""
            }
            isDownloading = false
        }
    }

    private func deleteModel(_ model: OllamaInstalledModel) {
        Task {
            do {
                try await OllamaModelsClient(baseURL: baseURL).deleteModel(name: model.name)
                if selected == model { selected = nil }
                refresh()
            } catch {
                errorMessage = "Could not delete \(model.name): \(error.localizedDescription)"
            }
        }
    }
}

struct OllamaModelsClient {
    static let defaultBaseURL = "http://127.0.0.1:11434"
    var baseURL: String

    func listModels() async throws -> [OllamaInstalledModel] {
        let url = URL(string: baseURL + "/api/tags")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "OllamaModelsClient", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Ollama returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1) for /api/tags"
            ])
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawModels = root["models"] as? [[String: Any]] else {
            return []
        }
        let formatter = ISO8601DateFormatter()
        return rawModels.compactMap { raw in
            guard let name = raw["name"] as? String else { return nil }
            var modified: Date?
            if let text = raw["modified_at"] as? String {
                modified = formatter.date(from: text)
            }
            return OllamaInstalledModel(
                name: name,
                size: (raw["size"] as? NSNumber)?.int64Value ?? 0,
                modifiedAt: modified)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func deleteModel(name: String) async throws {
        let url = URL(string: baseURL + "/api/delete")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "OllamaModelsClient", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Ollama returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1) for /api/delete"
            ])
        }
    }

    func pullModel(name: String, onProgress: @escaping @MainActor @Sendable (Double?, String) -> Void) async throws {
        let url = URL(string: baseURL + "/api/pull")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "stream": true])
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "OllamaModelsClient", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Ollama returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1) for /api/pull"
            ])
        }
        var buffer = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            buffer += line
            guard let data = buffer.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            buffer = ""
            if let error = event["error"] as? String, !error.isEmpty {
                throw NSError(domain: "OllamaModelsClient", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: error
                ])
            }
            let status = event["status"] as? String ?? ""
            if let total = event["total"] as? NSNumber, total.int64Value > 0,
               let completed = event["completed"] as? NSNumber {
                await onProgress(Double(completed.int64Value) / Double(total.int64Value), status)
            } else if !status.isEmpty {
                await onProgress(nil, status)
            }
            if status == "success" { return }
        }
    }
}
