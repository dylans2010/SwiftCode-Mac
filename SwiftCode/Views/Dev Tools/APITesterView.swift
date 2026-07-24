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
    var requestName: String = "Untitled Request"
    var method: String = "GET"
    var url: String = "https://api.github.com"
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
        let current = getCurrentRequestRepresentation(name: "Request to \(getHostFromUrl(url))")
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
            responseBody = "Error: Invalid URL"
            responseStatus = nil
            responseStatusText = nil
            elapsedMs = nil
            responseSize = 0
            return
        }

        isLoading = true
        responseBody = "Sending request..."
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
                        // INVARIANT: comp.url is guaranteed to be non-nil because comp is initialized from a valid requestUrl.
                        request.url = comp.url!
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

            // Format response body
            if let json = try? JSONSerialization.jsonObject(with: data, options: []),
               let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                self.responseBody = prettyString
            } else {
                self.responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response body (Binary/Data)"
            }

            // Add to execution history
            addCurrentToHistory()

        } catch {
            let duration = Date().timeIntervalSince(startTime) * 1000.0
            self.elapsedMs = duration
            self.responseBody = "Error: \(error.localizedDescription)"
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
            // Sidebar: History & Collections
            sidebarPanel
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
                .background(.ultraThinMaterial)

            // Main Request Workspace & Response Panel
            VSplitView {
                requestWorkspacePanel
                    .frame(minHeight: 280, idealHeight: 380)

                responsePanel
                    .frame(minHeight: 200, idealHeight: 300)
            }
            .frame(minWidth: 400, idealWidth: 600)
        }
        .navigationTitle("API Tester (Postman for SwiftCode)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newRequestName = store.requestName
                    showingSaveSheet = true
                } label: {
                    Label("Save to Collection", systemImage: "folder.badge.plus")
                }
                .help("Save current request to a collection")
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
            // Section header with collections action
            HStack {
                Text("Saved Collections")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    newCollectionName = ""
                    showingNewCollectionDialog = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Create New Collection")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)

            if showingNewCollectionDialog {
                HStack {
                    TextField("Collection Name", text: $newCollectionName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                    Button("Create") {
                        store.createCollection(name: newCollectionName)
                        showingNewCollectionDialog = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("Cancel") {
                        showingNewCollectionDialog = false
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            // Collections list
            List {
                if store.collections.isEmpty {
                    Text("No collections saved yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(store.collections) { collection in
                        DisclosureGroup {
                            if collection.requests.isEmpty {
                                Text("Empty Collection")
                                    .font(.system(size: 10, weight: .light))
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 12)
                                    .padding(.vertical, 2)
                            } else {
                                ForEach(collection.requests) { req in
                                    Button {
                                        store.selectRequest(req)
                                    } label: {
                                        HStack(spacing: 6) {
                                            methodBadge(req.method)
                                            Text(req.name)
                                                .font(.system(size: 11))
                                                .lineLimit(1)
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("Delete Request") {
                                            store.deleteRequestFromCollection(collectionId: collection.id, requestId: req.id)
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 12))
                                Text(collection.name)
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                            }
                        }
                        .contextMenu {
                            Button("Delete Collection") {
                                store.deleteCollection(collection.id)
                            }
                        }
                    }
                }

                // History Header Section
                Section(header: Text("HISTORY").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)) {
                    if store.history.isEmpty {
                        Text("No request history")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(store.history) { req in
                            Button {
                                store.selectRequest(req)
                            } label: {
                                HStack(spacing: 6) {
                                    methodBadge(req.method)
                                    Text(req.url)
                                        .font(.system(size: 11, design: .monospaced))
                                        .lineLimit(1)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
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
        VStack(spacing: 12) {
            // Title Bar
            HStack {
                TextField("Request Name", text: $store.requestName)
                    .font(.headline)
                    .textFieldStyle(.plain)
                Spacer()
            }
            .padding([.top, .horizontal])

            // URL & Method Input Bar
            HStack(spacing: 8) {
                Picker("", selection: $store.method) {
                    ForEach(methods, id: \.self) { method in
                        Text(method)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)

                TextField("Enter URL path (e.g. https://api.github.com/users/octocat)", text: $store.url)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit {
                        store.parseUrlQueryParams()
                        Task { await store.executeRequest() }
                    }

                Button {
                    store.parseUrlQueryParams()
                    Task { await store.executeRequest() }
                } label: {
                    HStack {
                        if store.isLoading {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text("Send")
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(store.isLoading)
            }
            .padding(.horizontal)

            // Tab Options Bar
            HStack {
                tabButton(id: "params", label: "Params")
                tabButton(id: "headers", label: "Headers")
                tabButton(id: "auth", label: "Authorization")
                tabButton(id: "body", label: "Body")
                Spacer()
            }
            .padding(.horizontal)

            Divider()
                .padding(.horizontal)

            // Tab Contents Container
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch store.activeTab {
                    case "params":
                        keyValueParamsEditor(
                            title: "Query Parameters",
                            pairs: $store.queryParams,
                            onChanged: { store.rebuildUrlWithQueryParams() }
                        )
                    case "headers":
                        keyValueParamsEditor(
                            title: "Headers",
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
                .padding(.horizontal)
            }
        }
    }

    private func tabButton(id: String, label: String) -> some View {
        Button {
            store.activeTab = id
        } label: {
            Text(label)
                .font(.system(size: 12, weight: store.activeTab == id ? .semibold : .regular))
                .foregroundColor(store.activeTab == id ? .orange : .secondary)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(store.activeTab == id ? Color.orange.opacity(0.12) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func keyValueParamsEditor(title: String, pairs: Binding<[KeyValuePair]>, onChanged: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Clear All") {
                    pairs.wrappedValue = [KeyValuePair()]
                    onChanged()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            VStack(spacing: 4) {
                ForEach(pairs.indices, id: \.self) { idx in
                    HStack(spacing: 6) {
                        Toggle("", isOn: pairs[idx].isEnabled)
                            .toggleStyle(.checkbox)
                            .onChange(of: pairs[idx].isEnabled.wrappedValue) { _ in
                                onChanged()
                            }

                        TextField("Key", text: pairs[idx].key)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .onChange(of: pairs[idx].key.wrappedValue) { newValue in
                                // Add automatic blank row if writing in final line
                                if idx == pairs.count - 1 && !newValue.isEmpty {
                                    pairs.wrappedValue.append(KeyValuePair())
                                }
                                onChanged()
                            }

                        TextField("Value", text: pairs[idx].value)
                            .textFieldStyle(.roundedBorder)
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
                                .foregroundColor(.red)
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
            HStack {
                Text("Type")
                    .font(.caption.bold())
                    .frame(width: 80, alignment: .leading)

                Picker("", selection: $store.authType) {
                    ForEach(AuthType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
            }

            Divider()

            switch store.authType {
            case .none:
                Text("This request does not use any authorization headers or parameters.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .basic:
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Username")
                            .font(.caption)
                            .frame(width: 80, alignment: .leading)
                        TextField("Username", text: $store.authUsername)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                    HStack {
                        Text("Password")
                            .font(.caption)
                            .frame(width: 80, alignment: .leading)
                        SecureField("Password", text: $store.authPassword)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                }
            case .bearer:
                HStack {
                    Text("Token")
                        .font(.caption)
                        .frame(width: 80, alignment: .leading)
                    TextField("Bearer Token String", text: $store.authToken)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 400)
                }
            case .apiKey:
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Key")
                            .font(.caption)
                            .frame(width: 80, alignment: .leading)
                        TextField("Header or Query Key", text: $store.authKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                    HStack {
                        Text("Value")
                            .font(.caption)
                            .frame(width: 80, alignment: .leading)
                        TextField("Header or Query Value", text: $store.authValue)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                    HStack {
                        Text("Add to")
                            .font(.caption)
                            .frame(width: 80, alignment: .leading)
                        Picker("", selection: $store.authAddTo) {
                            Text("Headers").tag("Headers")
                            Text("Query Params").tag("Query Params")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                }
            }
        }
        .padding(.vertical, 8)
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
                Text("This request does not send an HTTP body payload.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .formData:
                keyValueParamsEditor(
                    title: "Form-Data Parameters",
                    pairs: $store.bodyFormData,
                    onChanged: {}
                )
            case .urlencoded:
                keyValueParamsEditor(
                    title: "x-www-form-urlencoded Parameters",
                    pairs: $store.bodyUrlencoded,
                    onChanged: {}
                )
            case .rawJSON, .rawText, .rawXML:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Raw Body Payload Input")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    TextEditor(text: $store.bodyRaw)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 140)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Response Panel View

extension APITesterView {

    private var responsePanel: some View {
        VStack(spacing: 0) {
            Divider()

            // Response Panel Header with Stats Dashboard
            HStack {
                Label("Response Panel", systemImage: "arrow.down.right.circle")
                    .font(.system(size: 12, weight: .bold))

                Spacer()

                if let status = store.responseStatus {
                    HStack(spacing: 12) {
                        // Colored Status Badge
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor(status))
                                .frame(width: 8, height: 8)
                            Text("Status: \(status) \(store.responseStatusText ?? "")")
                                .font(.caption.bold())
                                .foregroundColor(statusColor(status))
                        }

                        if let ms = store.elapsedMs {
                            Text("Time: \(String(format: "%.0f ms", ms))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text("Size: \(formatByteSize(store.responseSize))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.thinMaterial)

            // Tab Selection for Body vs. Headers
            HStack {
                Button {
                    store.responseTab = "body"
                } label: {
                    Text("Response Body")
                        .font(.system(size: 11, weight: store.responseTab == "body" ? .semibold : .regular))
                        .foregroundColor(store.responseTab == "body" ? .blue : .secondary)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(store.responseTab == "body" ? Color.blue.opacity(0.1) : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Button {
                    store.responseTab = "headers"
                } label: {
                    Text("Response Headers (\(store.responseHeaders.count))")
                        .font(.system(size: 11, weight: store.responseTab == "headers" ? .semibold : .regular))
                        .foregroundColor(store.responseTab == "headers" ? .blue : .secondary)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(store.responseTab == "headers" ? Color.blue.opacity(0.1) : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Spacer()

                if store.responseTab == "body" && !store.responseBody.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.responseBody, forType: .string)
                    } label: {
                        Label("Copy Body", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()

            // Body / Headers Details
            ZStack {
                if store.responseTab == "body" {
                    TextEditor(text: .constant(store.responseBody))
                        .font(.system(.body, design: .monospaced))
                        .cornerRadius(0)
                } else {
                    List {
                        if store.responseHeaders.isEmpty {
                            Text("No headers returned.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(store.responseHeaders) { header in
                                HStack(alignment: .top) {
                                    Text(header.key)
                                        .font(.system(.caption, design: .monospaced))
                                        .fontWeight(.bold)
                                        .foregroundColor(.secondary)
                                        .frame(width: 200, alignment: .leading)

                                    Text(header.value)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.primary)

                                    Spacer()
                                }
                                .padding(.vertical, 1)
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
        VStack(spacing: 16) {
            Text("Save Current Request")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Request Name")
                    .font(.caption.bold())
                TextField("Enter Request Name", text: $newRequestName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Select Destination Collection")
                    .font(.caption.bold())

                if store.collections.isEmpty {
                    Text("No collections exist. Create one in the sidebar first.")
                        .font(.caption)
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
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(height: 150)
                    .border(Color.secondary.opacity(0.2))
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    showingSaveSheet = false
                }
                .buttonStyle(.bordered)

                Button("Save to Workspace") {
                    store.requestName = newRequestName
                    store.addCurrentToHistory()
                    showingSaveSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
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
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color)
            .cornerRadius(4)
            .frame(width: 50)
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

