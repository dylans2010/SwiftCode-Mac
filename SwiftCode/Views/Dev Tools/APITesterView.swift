import SwiftUI
import os.log

// MARK: - Models

struct KeyValuePair: Identifiable, Codable, Hashable {
    var id = UUID()
    var isEnabled: Bool = true
    var key: String = ""
    var value: String = ""
}

enum AuthType: String, Codable, CaseIterable, Identifiable {
    case none = "No Auth"
    case basic = "Basic Auth"
    case bearer = "Bearer Token"
    case apiKey = "API Key"

    var id: String { rawValue }
}

enum BodyType: String, Codable, CaseIterable, Identifiable {
    case none = "none"
    case formData = "form-data"
    case urlencoded = "x-www-form-urlencoded"
    case rawJSON = "raw (JSON)"
    case rawText = "raw (Text)"
    case rawXML = "raw (XML)"

    var id: String { rawValue }
}

struct SavedRequest: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var method: String
    var url: String
    var queryParams: [KeyValuePair]
    var headers: [KeyValuePair]
    var authType: AuthType
    var authUsername: String
    var authPassword: String
    var authToken: String
    var authKey: String
    var authValue: String
    var authAddTo: String // "Headers" or "Query Params"
    var bodyType: BodyType
    var bodyFormData: [KeyValuePair]
    var bodyUrlencoded: [KeyValuePair]
    var bodyRaw: String
    var timestamp: Date = Date()
}

struct SavedCollection: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var requests: [SavedRequest]
}

// MARK: - State Store

@MainActor
@Observable
final class APITesterStore {
    private static let logger = Logger(subsystem: "com.swiftcode.devtools", category: "APITesterStore")

    var history: [SavedRequest] = []
    var collections: [SavedCollection] = []

    // Current Active Workspace Request State
    var requestName: String = "Fetch Octocat Details"
    var method: String = "GET"
    var url: String = "https://api.github.com/users/octocat"
    var queryParams: [KeyValuePair] = [KeyValuePair()]
    var headers: [KeyValuePair] = [KeyValuePair(isEnabled: true, key: "User-Agent", value: "SwiftCode-APITester")]

    // Auth State
    var authType: AuthType = .none
    var authUsername: String = ""
    var authPassword: String = ""
    var authToken: String = ""
    var authKey: String = ""
    var authValue: String = ""
    var authAddTo: String = "Headers"

    // Body State
    var bodyType: BodyType = .none
    var bodyFormData: [KeyValuePair] = [KeyValuePair()]
    var bodyUrlencoded: [KeyValuePair] = [KeyValuePair()]
    var bodyRaw: String = ""

    // Execution State
    var isLoading: Bool = false
    var elapsedMs: Double? = nil
    var responseStatus: Int? = nil
    var responseStatusText: String? = nil
    var responseBody: String = ""
    var responseHeaders: [KeyValuePair] = []
    var responseSize: Int64 = 0

    // UI selection
    var activeTab: String = "params"
    var responseTab: String = "body"

    init() {
        loadData()
    }

    private func loadData() {
        let defaults = UserDefaults.standard
        if let historyData = defaults.data(forKey: "com.swiftcode.api.history") {
            do {
                self.history = try JSONDecoder().decode([SavedRequest].self, from: historyData)
            } catch {
                Self.logger.error("Failed to decode history: \(error.localizedDescription)")
            }
        }
        if let collectionsData = defaults.data(forKey: "com.swiftcode.api.collections") {
            do {
                self.collections = try JSONDecoder().decode([SavedCollection].self, from: collectionsData)
            } catch {
                Self.logger.error("Failed to decode collections: \(error.localizedDescription)")
            }
        }

        if history.isEmpty {
            // Seed a sample history item
            let sample = SavedRequest(
                name: "Get Octocat Details",
                method: "GET",
                url: "https://api.github.com/users/octocat",
                queryParams: [],
                headers: [KeyValuePair(isEnabled: true, key: "User-Agent", value: "SwiftCode-APITester")],
                authType: .none,
                authUsername: "",
                authPassword: "",
                authToken: "",
                authKey: "",
                authValue: "",
                authAddTo: "Headers",
                bodyType: .none,
                bodyFormData: [],
                bodyUrlencoded: [],
                bodyRaw: ""
            )
            history = [sample]
        }
    }

    func saveData() {
        let defaults = UserDefaults.standard
        do {
            let historyData = try JSONEncoder().encode(history)
            defaults.set(historyData, forKey: "com.swiftcode.api.history")

            let collectionsData = try JSONEncoder().encode(collections)
            defaults.set(collectionsData, forKey: "com.swiftcode.api.collections")
        } catch {
            Self.logger.error("Failed to save APITester data: \(error.localizedDescription)")
        }
    }

    func selectRequest(_ saved: SavedRequest) {
        requestName = saved.name
        method = saved.method
        url = saved.url
        queryParams = saved.queryParams.isEmpty ? [KeyValuePair()] : saved.queryParams
        headers = saved.headers.isEmpty ? [KeyValuePair()] : saved.headers
        authType = saved.authType
        authUsername = saved.authUsername
        authPassword = saved.authPassword
        authToken = saved.authToken
        authKey = saved.authKey
        authValue = saved.authValue
        authAddTo = saved.authAddTo
        bodyType = saved.bodyType
        bodyFormData = saved.bodyFormData.isEmpty ? [KeyValuePair()] : saved.bodyFormData
        bodyUrlencoded = saved.bodyUrlencoded.isEmpty ? [KeyValuePair()] : saved.bodyUrlencoded
        bodyRaw = saved.bodyRaw
    }

    func addCurrentToHistory() {
        let current = getCurrentRequestRepresentation(name: requestName.isEmpty ? "Request to \(getHostFromUrl(url))" : requestName)
        // De-duplicate: remove older entry with exact method/url/body if exists
        history.removeAll { $0.method == current.method && $0.url == current.url && $0.bodyRaw == current.bodyRaw }
        history.insert(current, at: 0)
        if history.count > 50 {
            history.removeLast()
        }
        saveData()
    }

    func createCollection(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newCol = SavedCollection(name: trimmed, requests: [])
        collections.append(newCol)
        saveData()
    }

    func addCurrentToCollection(_ collectionId: UUID) {
        let current = getCurrentRequestRepresentation(name: requestName)
        if let index = collections.firstIndex(where: { $0.id == collectionId }) {
            collections[index].requests.append(current)
            saveData()
        }
    }

    func deleteHistoryItem(_ id: UUID) {
        history.removeAll { $0.id == id }
        saveData()
    }

    func deleteCollection(_ id: UUID) {
        collections.removeAll { $0.id == id }
        saveData()
    }

    func deleteRequestFromCollection(collectionId: UUID, requestId: UUID) {
        if let index = collections.firstIndex(where: { $0.id == collectionId }) {
            collections[index].requests.removeAll { $0.id == requestId }
            saveData()
        }
    }

    private func getHostFromUrl(_ urlString: String) -> String {
        if let urlObj = URL(string: urlString), let host = urlObj.host {
            return host
        }
        return "API"
    }

    private func getCurrentRequestRepresentation(name: String) -> SavedRequest {
        SavedRequest(
            name: name,
            method: method,
            url: url,
            queryParams: queryParams.filter { !$0.key.isEmpty },
            headers: headers.filter { !$0.key.isEmpty },
            authType: authType,
            authUsername: authUsername,
            authPassword: authPassword,
            authToken: authToken,
            authKey: authKey,
            authValue: authValue,
            authAddTo: authAddTo,
            bodyType: bodyType,
            bodyFormData: bodyFormData.filter { !$0.key.isEmpty },
            bodyUrlencoded: bodyUrlencoded.filter { !$0.key.isEmpty },
            bodyRaw: bodyRaw
        )
    }

    // Parse query params out of the URL input field
    func parseUrlQueryParams() {
        guard let urlComponents = URLComponents(string: url) else { return }
        if let queryItems = urlComponents.queryItems, !queryItems.isEmpty {
            var newParams: [KeyValuePair] = []
            for item in queryItems {
                newParams.append(KeyValuePair(isEnabled: true, key: item.name, value: item.value ?? ""))
            }
            newParams.append(KeyValuePair()) // blank line at end
            self.queryParams = newParams
        }
    }

    // Assemble the parameters into URL query string bidirectionally
    func rebuildUrlWithQueryParams() {
        guard var urlComponents = URLComponents(string: url) else { return }
        let activeParams = queryParams.filter { $0.isEnabled && !$0.key.isEmpty }
        if activeParams.isEmpty {
            urlComponents.queryItems = nil
        } else {
            urlComponents.queryItems = activeParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        if let newUrl = urlComponents.url?.absoluteString {
            self.url = newUrl
        }
    }

    // MARK: - Network Request Execution

    func executeRequest() async {
        guard let requestUrl = URL(string: url) else {
            responseBody = "Error: Invalid URL format"
            responseStatus = nil
            responseStatusText = nil
            elapsedMs = nil
            responseSize = 0
            return
        }

        isLoading = true
        responseBody = "Sending request to \(url)..."
        responseHeaders = []
        responseStatus = nil
        responseStatusText = nil
        elapsedMs = nil
        responseSize = 0

        var request = URLRequest(url: requestUrl)
        request.httpMethod = method

        // 1. Compile Headers
        for header in headers where header.isEnabled && !header.key.isEmpty {
            request.setValue(header.value, forHTTPHeaderField: header.key)
        }

        // 2. Add Authentication
        switch authType {
        case .none:
            break
        case .basic:
            let credential = "\(authUsername):\(authPassword)"
            if let credentialData = credential.data(using: .utf8) {
                let base64 = credentialData.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        case .bearer:
            if !authToken.isEmpty {
                request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            }
        case .apiKey:
            if !authKey.isEmpty {
                if authAddTo == "Headers" {
                    request.setValue(authValue, forHTTPHeaderField: authKey)
                } else {
                    // Add to query params
                    if var comp = URLComponents(url: requestUrl, resolvingAgainstBaseURL: false) {
                        var items = comp.queryItems ?? []
                        items.append(URLQueryItem(name: authKey, value: authValue))
                        comp.queryItems = items
                        if let finalUrl = comp.url {
                            request.url = finalUrl
                        }
                    }
                }
            }
        }

        // 3. Compile Request Body
        if method != "GET" && method != "HEAD" {
            switch bodyType {
            case .none:
                break
            case .formData:
                let boundary = "Boundary-\(UUID().uuidString)"
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                var bodyData = Data()
                for param in bodyFormData where param.isEnabled && !param.key.isEmpty {
                    bodyData.append("--\(boundary)\r\n".data(using: .utf8) ?? Data())
                    bodyData.append("Content-Disposition: form-data; name=\"\(param.key)\"\r\n\r\n".data(using: .utf8) ?? Data())
                    bodyData.append("\(param.value)\r\n".data(using: .utf8) ?? Data())
                }
                bodyData.append("--\(boundary)--\r\n".data(using: .utf8) ?? Data())
                request.httpBody = bodyData
            case .urlencoded:
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                let activeBodyParams = bodyUrlencoded.filter { $0.isEnabled && !$0.key.isEmpty }
                let queryParts = activeBodyParams.compactMap { param -> String? in
                    guard let encKey = param.key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                          let encVal = param.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
                    return "\(encKey)=\(encVal)"
                }
                request.httpBody = queryParts.joined(separator: "&").data(using: .utf8)
            case .rawJSON:
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = bodyRaw.data(using: .utf8)
            case .rawText:
                request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
                request.httpBody = bodyRaw.data(using: .utf8)
            case .rawXML:
                request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
                request.httpBody = bodyRaw.data(using: .utf8)
            }
        }

        let startTime = Date()

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let duration = Date().timeIntervalSince(startTime) * 1000.0
            self.elapsedMs = duration
            self.responseSize = Int64(data.count)

            if let httpResponse = response as? HTTPURLResponse {
                self.responseStatus = httpResponse.statusCode
                self.responseStatusText = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)

                // Parse headers
                var parsedHeaders: [KeyValuePair] = []
                for (key, value) in httpResponse.allHeaderFields {
                    parsedHeaders.append(KeyValuePair(isEnabled: true, key: "\(key)", value: "\(value)"))
                }
                self.responseHeaders = parsedHeaders.sorted(by: { $0.key < $1.key })
            }

            // Format response body nicely
            if let json = try? JSONSerialization.jsonObject(with: data, options: []),
               let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                self.responseBody = prettyString
            } else {
                self.responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response (Binary Data)"
            }

            // Add to execution history
            addCurrentToHistory()

        } catch {
            let duration = Date().timeIntervalSince(startTime) * 1000.0
            self.elapsedMs = duration
            self.responseBody = "Network Error: \(error.localizedDescription)"
            self.responseStatus = nil
            self.responseStatusText = nil
            self.responseSize = 0
            Self.logger.error("Request failed: \(error.localizedDescription)")
        }

        self.isLoading = false
    }
}

// MARK: - APITesterView Main View

struct APITesterView: View {
    @State private var store = APITesterStore()
    @State private var showingSaveSheet = false
    @State private var newRequestName = ""
    @State private var showingNewCollectionDialog = false
    @State private var newCollectionName = ""

    let methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]

    var body: some View {
        HSplitView {
            // Sidebar: History & Collections with visual headers
            sidebarPanel
                .frame(minWidth: 240, idealWidth: 270, maxWidth: 320)
                .background(.ultraThinMaterial)

            // Main Request Workspace & Response Panel (Stretches smoothly)
            VSplitView {
                requestWorkspacePanel
                    .frame(minHeight: 380, idealHeight: 440)

                responsePanel
                    .frame(minHeight: 250, idealHeight: 380)
            }
            .frame(minWidth: 500, idealWidth: 800)
        }
        .navigationTitle("APITester Studio")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newRequestName = store.requestName
                    showingSaveSheet = true
                } label: {
                    Label("Save to Collection", systemImage: "folder.badge.plus")
                }
                .help("Save current request configuration to a collection")
            }
        }
        .sheet(isPresented: $showingSaveSheet) {
            saveRequestSheet
        }
    }
}

// MARK: - Sidebar Layout Panel

extension APITesterView {

    private var sidebarPanel: some View {
        VStack(spacing: 0) {
            // Main Sidebar Title
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                Text("API Collections")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    newCollectionName = ""
                    showingNewCollectionDialog = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("Create New Collection Folder")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            if showingNewCollectionDialog {
                VStack(spacing: 8) {
                    TextField("Enter folder name...", text: $newCollectionName)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Cancel") {
                            showingNewCollectionDialog = false
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        Button("Create Folder") {
                            store.createCollection(name: newCollectionName)
                            showingNewCollectionDialog = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)
                .padding(10)
            }

            List {
                Section(header: Text("COLLECTION LIST").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)) {
                    if store.collections.isEmpty {
                        Text("No custom collections folders defined. Click + to begin organizing.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(store.collections) { collection in
                            DisclosureGroup {
                                if collection.requests.isEmpty {
                                    Text("Folder is empty. Save requests here.")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 12)
                                        .padding(.vertical, 4)
                                } else {
                                    ForEach(collection.requests) { req in
                                        Button {
                                            store.selectRequest(req)
                                        } label: {
                                            HStack(spacing: 8) {
                                                methodBadge(req.method)
                                                Text(req.name)
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .lineLimit(1)
                                                Spacer()
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.vertical, 3)
                                        .contextMenu {
                                            Button("Delete Saved Request") {
                                                store.deleteRequestFromCollection(collectionId: collection.id, requestId: req.id)
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 13))
                                    Text(collection.name)
                                        .font(.system(size: 12, weight: .bold))
                                    Spacer()
                                }
                            }
                            .contextMenu {
                                Button("Delete Collection Folder") {
                                    store.deleteCollection(collection.id)
                                }
                            }
                        }
                    }
                }

                Section(header: Text("RECENT REQUEST HISTORY").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)) {
                    if store.history.isEmpty {
                        Text("No request history recorded yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(store.history) { req in
                            Button {
                                store.selectRequest(req)
                            } label: {
                                HStack(spacing: 8) {
                                    methodBadge(req.method)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(req.name)
                                            .font(.system(size: 11, weight: .semibold))
                                            .lineLimit(1)
                                        Text(req.url)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                            .contextMenu {
                                Button("Delete from History") {
                                    store.deleteHistoryItem(req.id)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

// MARK: - Main Request Panel

extension APITesterView {

    private var requestWorkspacePanel: some View {
        VStack(spacing: 0) {
            // Workspace Request Title Card
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Image(systemName: "globe")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    TextField("Enter request friendly name...", text: $store.requestName)
                        .font(.system(size: 15, weight: .bold))
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity)
                    Text("Design API request params, headers, payload and execute directly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            // URL & Method Input Bar (High Fidelity Unified Card Pattern)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    // Styled Picker Button
                    Picker("", selection: $store.method) {
                        ForEach(methods, id: \.self) { method in
                            Text(method).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 110)

                    TextField("Enter request target URL (e.g., https://api.github.com/users/octocat)", text: $store.url)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                        .onSubmit {
                            store.parseUrlQueryParams()
                            Task { await store.executeRequest() }
                        }

                    Button {
                        store.parseUrlQueryParams()
                        Task { await store.executeRequest() }
                    } label: {
                        HStack(spacing: 6) {
                            if store.isLoading {
                                ProgressView().scaleEffect(0.5)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text("Send Request")
                        }
                        .fontWeight(.bold)
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(store.isLoading)
                }
                .padding(12)
            }
            .background(Color.secondary.opacity(0.04))

            Divider()

            // Tab Navigation Pill Buttons Bar
            HStack(spacing: 10) {
                tabButton(id: "params", label: "Query Params (\(store.queryParams.filter { !$0.key.isEmpty }.count))", icon: "slider.horizontal.3")
                tabButton(id: "headers", label: "Request Headers (\(store.headers.filter { !$0.key.isEmpty }.count))", icon: "list.bullet")
                tabButton(id: "auth", label: "Authentication (\(store.authType.rawValue))", icon: "lock.shield")
                tabButton(id: "body", label: "Body Payload (\(store.bodyType.rawValue))", icon: "arrow.right.doc.on.clipboard")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.02))

            Divider()

            // Tab Contents Editor (Spans nicely with internal scrolling)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch store.activeTab {
                    case "params":
                        keyValueParamsEditor(
                            title: "Query Parameters (Appended directly to the end of URL string)",
                            pairs: $store.queryParams,
                            onChanged: { store.rebuildUrlWithQueryParams() }
                        )
                    case "headers":
                        keyValueParamsEditor(
                            title: "Custom Request HTTP Headers",
                            pairs: $store.headers,
                            onChanged: {}
                        )
                    case "auth":
                        authTabEditor
                    case "body":
                        bodyTabEditor
                    default:
                        EmptyView()
                    }
                }
                .padding(16)
            }
        }
    }

    private func tabButton(id: String, label: String, icon: String) -> some View {
        Button {
            store.activeTab = id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.system(size: 11, weight: store.activeTab == id ? .bold : .medium))
            }
            .foregroundColor(store.activeTab == id ? .white : .secondary)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(store.activeTab == id ? Color.blue : Color.secondary.opacity(0.12))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func keyValueParamsEditor(title: String, pairs: Binding<[KeyValuePair]>, onChanged: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Clear Fields") {
                    pairs.wrappedValue = [KeyValuePair()]
                    onChanged()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            // Structured Table Layout Grid
            VStack(spacing: 6) {
                ForEach(pairs.indices, id: \.self) { idx in
                    HStack(spacing: 8) {
                        Toggle("", isOn: pairs[idx].isEnabled)
                            .toggleStyle(.checkbox)
                            .onChange(of: pairs[idx].isEnabled.wrappedValue) { _ in
                                onChanged()
                            }

                        TextField("Key (e.g., Content-Type)", text: pairs[idx].key)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .controlSize(.small)
                            .onChange(of: pairs[idx].key.wrappedValue) { newValue in
                                if idx == pairs.count - 1 && !newValue.isEmpty {
                                    pairs.wrappedValue.append(KeyValuePair())
                                }
                                onChanged()
                            }

                        TextField("Value representation...", text: pairs[idx].value)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .controlSize(.small)
                            .onChange(of: pairs[idx].value.wrappedValue) { _ in
                                onChanged()
                            }

                        Button {
                            pairs.wrappedValue.remove(at: idx)
                            if pairs.wrappedValue.isEmpty {
                                pairs.wrappedValue.append(KeyValuePair())
                            }
                            onChanged()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Sub Tab Editors (Auth, Body)

extension APITesterView {

    private var authTabEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Authorization Method")
                    .font(.caption.bold())
                    .frame(width: 140, alignment: .leading)

                Picker("", selection: $store.authType) {
                    ForEach(AuthType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
            }

            Divider()

            switch store.authType {
            case .none:
                VStack(alignment: .leading, spacing: 6) {
                    Text("No Authentication Headers Added")
                        .font(.subheadline.bold())
                    Text("This request is dispatched as public. If the server throws authentication or access limit errors, select Basic Auth, Bearer Token or custom API Key coordinates above.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                }
                .padding(.vertical, 8)
            case .basic:
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Username")
                            .font(.caption)
                            .frame(width: 120, alignment: .leading)
                        TextField("Enter auth username...", text: $store.authUsername)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                    HStack {
                        Text("Password")
                            .font(.caption)
                            .frame(width: 120, alignment: .leading)
                        SecureField("Enter auth password...", text: $store.authPassword)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                }
            case .bearer:
                HStack {
                    Text("Bearer Token")
                        .font(.caption)
                        .frame(width: 120, alignment: .leading)
                    TextField("Enter bearer token string...", text: $store.authToken)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 400)
                }
            case .apiKey:
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("API Key Header Field")
                            .font(.caption)
                            .frame(width: 140, alignment: .leading)
                        TextField("e.g., X-API-KEY", text: $store.authKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                    HStack {
                        Text("API Key Value")
                            .font(.caption)
                            .frame(width: 140, alignment: .leading)
                        TextField("Enter secret value...", text: $store.authValue)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                    HStack {
                        Text("Incorporate Key Into")
                            .font(.caption)
                            .frame(width: 140, alignment: .leading)
                        Picker("", selection: $store.authAddTo) {
                            Text("HTTP Headers").tag("Headers")
                            Text("Query URL Params").tag("Query Params")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(8)
    }

    private var bodyTabEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Body Type Selector
            Picker("Body Format", selection: $store.bodyType) {
                ForEach(BodyType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 6)

            Divider()

            switch store.bodyType {
            case .none:
                VStack(alignment: .leading, spacing: 6) {
                    Text("No Body Sent with Request")
                        .font(.subheadline.bold())
                    Text("GET and HEAD requests ignore body formats. Use POST, PUT, or DELETE request methods to transmit form-data parameters or raw JSON objects to server controllers.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                }
                .padding(.vertical, 8)
            case .formData:
                keyValueParamsEditor(
                    title: "Form-Data Parameters (multipart/form-data boundary representation)",
                    pairs: $store.bodyFormData,
                    onChanged: {}
                )
            case .urlencoded:
                keyValueParamsEditor(
                    title: "URL-Encoded Parameters (application/x-www-form-urlencoded format)",
                    pairs: $store.bodyUrlencoded,
                    onChanged: {}
                )
            case .rawJSON, .rawText, .rawXML:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Raw Body Payload Input Editor")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    TextEditor(text: $store.bodyRaw)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 160)
                        .padding(8)
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                        )
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(8)
    }
}

// MARK: - Response Panel View

extension APITesterView {

    private var responsePanel: some View {
        VStack(spacing: 0) {
            Divider()

            // Response HUD Panel Header with Stats Dashboard
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.right.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Response Payload")
                        .font(.system(size: 13, weight: .bold))
                }

                Spacer()

                if let status = store.responseStatus {
                    HStack(spacing: 16) {
                        // Colored Status Badge with smooth background glow
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor(status))
                                .frame(width: 8, height: 8)
                            Text("STATUS: \(status) \(store.responseStatusText ?? "")")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(statusColor(status))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(statusColor(status).opacity(0.12))
                        .cornerRadius(6)

                        if let ms = store.elapsedMs {
                            Text("TIME: \(String(format: "%.0f ms", ms))")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        Text("SIZE: \(formatByteSize(store.responseSize))")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                } else if store.isLoading {
                    Text("EXECUTING REQUEST...")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                } else {
                    Text("NO ACTIVE RESPONSE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.thinMaterial)

            Divider()

            // Tab Selection for Body vs. Headers
            HStack {
                Button {
                    store.responseTab = "body"
                } label: {
                    Text("Response Body Payload")
                        .font(.system(size: 11, weight: store.responseTab == "body" ? .bold : .medium))
                        .foregroundColor(store.responseTab == "body" ? .white : .secondary)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 12)
                        .background(store.responseTab == "body" ? Color.blue : Color.secondary.opacity(0.12))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button {
                    store.responseTab = "headers"
                } label: {
                    Text("Response Headers (\(store.responseHeaders.count))")
                        .font(.system(size: 11, weight: store.responseTab == "headers" ? .bold : .medium))
                        .foregroundColor(store.responseTab == "headers" ? .white : .secondary)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 12)
                        .background(store.responseTab == "headers" ? Color.blue : Color.secondary.opacity(0.12))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Spacer()

                if store.responseTab == "body" && !store.responseBody.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.responseBody, forType: .string)
                    } label: {
                        Label("Copy Response Body", systemImage: "doc.on.doc.fill")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.02))

            Divider()

            // Body / Headers Details
            ZStack {
                if store.responseTab == "body" {
                    if store.responseBody.isEmpty {
                        ContentUnavailableView("No Response Loaded", systemImage: "arrow.up.circle")
                            .frame(maxHeight: .infinity)
                    } else {
                        TextEditor(text: .constant(store.responseBody))
                            .font(.system(.body, design: .monospaced))
                            .padding(10)
                            .background(Color.black.opacity(0.1))
                    }
                } else {
                    List {
                        if store.responseHeaders.isEmpty {
                            Text("No HTTP headers returned from server controller.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(store.responseHeaders) { header in
                                HStack(alignment: .top, spacing: 14) {
                                    Text(header.key)
                                        .font(.system(.caption, design: .monospaced))
                                        .fontWeight(.bold)
                                        .foregroundColor(.orange)
                                        .frame(width: 240, alignment: .leading)

                                    Text(header.value)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.primary)

                                    Spacer()
                                }
                                .padding(.vertical, 2)
                                .dividerBackground()
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
    }
}

// MARK: - Save Request Sheet Modal View

extension APITesterView {

    private var saveRequestSheet: some View {
        VStack(spacing: 20) {
            Text("Save API Request Configuration")
                .font(.headline)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Request Label")
                    .font(.caption.bold())
                TextField("Enter Request Name", text: $newRequestName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Select Destination Collection Folder")
                    .font(.caption.bold())

                if store.collections.isEmpty {
                    Text("No collection folders exist. Please click + on the sidebar first to create a folder.")
                        .font(.caption.bold())
                        .foregroundColor(.red)
                } else {
                    List {
                        ForEach(store.collections) { col in
                            Button {
                                store.requestName = newRequestName
                                store.addCurrentToCollection(col.id)
                                showingSaveSheet = false
                            } label: {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.orange)
                                    Text(col.name)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 6)
                        }
                    }
                    .frame(height: 160)
                    .border(Color.secondary.opacity(0.12))
                }
            }

            HStack {
                Button("Save to Quick History") {
                    store.requestName = newRequestName
                    store.addCurrentToHistory()
                    showingSaveSheet = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Cancel") {
                    showingSaveSheet = false
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

// MARK: - Utility View Helpers

extension APITesterView {

    @ViewBuilder
    private func methodBadge(_ method: String) -> some View {
        let color: Color = {
            switch method {
            case "GET": return .green
            case "POST": return .blue
            case "PUT": return .orange
            case "DELETE": return .red
            case "PATCH": return .purple
            default: return .secondary
            }
        }()

        Text(method)
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .cornerRadius(4)
            .frame(width: 55)
    }

    private func statusColor(_ status: Int) -> Color {
        switch status {
        case 200...299:
            return .green
        case 300...399:
            return .blue
        case 400...499:
            return .orange
        case 500...599:
            return .red
        default:
            return .secondary
        }
    }

    private func formatByteSize(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
}

// Custom view helper for divider lists
private extension View {
    func dividerBackground() -> some View {
        self.padding(.bottom, 3)
            .overlay(
                Divider()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 25),
                alignment: .bottom
            )
    }
}
