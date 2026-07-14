import SwiftUI

public struct APIDocumentationEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    // Custom Interactive State Variables
    @State private var endpointMethod = "GET"
    @State private var endpointPath = "/api/v1/resource"
    @State private var apiVersion = "v1"
    @State private var requestContentType = "application/json"
    @State private var authScheme = "Bearer Token"
    @State private var rateLimit = "100 req/min"
    @State private var isDeprecated = false

    // Request parameters interactive model
    @State private var parameterName = ""
    @State private var parameterType = "String"
    @State private var parameterRequired = true
    @State private var parameterDescription = ""
    @State private var customParameters: [APIParameter] = []

    // Response code preset simulator
    @State private var simulatedResponseCode = "200"

    struct APIParameter: Identifiable, Hashable {
        let id = UUID()
        var name: String
        var type: String
        var isRequired: Bool
        var description: String
    }

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    private var validationMessage: String? {
        if endpointPath.isEmpty {
            return "Endpoint path is required"
        }
        if !endpointPath.hasPrefix("/") {
            return "Endpoint path must start with '/'"
        }
        return nil
    }

    private var methodColor: Color {
        switch endpointMethod {
        case "GET": return .green
        case "POST": return .blue
        case "PUT", "PATCH": return .orange
        case "DELETE": return .red
        default: return .purple
        }
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .apiDocumentation,
            documentID: documentID,
            specializedToolbar: {
                HStack(spacing: 6) {
                    Button {
                        insertTemplate()
                    } label: {
                        Label("Endpoint Spec", systemImage: "network")
                    }
                    .help("Insert full high-fidelity Endpoint Specification template")

                    Button {
                        insertCurlCommand()
                    } label: {
                        Label("Curl Command", systemImage: "terminal")
                    }
                    .help("Generate and insert curl execution sample")
                }
            },
            specializedMetadata: {
                VStack(alignment: .leading, spacing: 12) {
                    // Header Status Info
                    HStack(spacing: 8) {
                        Text(endpointMethod)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(methodColor.opacity(0.15))
                            .foregroundStyle(methodColor)
                            .cornerRadius(4)

                        Text(endpointPath.isEmpty ? "No Path Specified" : endpointPath)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }
                    .padding(.bottom, 4)

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Method:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $endpointMethod) {
                                Text("GET").tag("GET")
                                Text("POST").tag("POST")
                                Text("PUT").tag("PUT")
                                Text("PATCH").tag("PATCH")
                                Text("DELETE").tag("DELETE")
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .gridCellColumns(3)
                        }

                        GridRow {
                            Text("Path:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("e.g. /users", text: $endpointPath)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .gridCellColumns(3)
                        }

                        GridRow {
                            Text("Version:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("v1", text: $apiVersion)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)

                            Text("Rate Limit:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("60 req/min", text: $rateLimit)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                        }

                        GridRow {
                            Text("Content:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $requestContentType) {
                                Text("JSON").tag("application/json")
                                Text("Form").tag("application/x-www-form-urlencoded")
                                Text("Multipart").tag("multipart/form-data")
                                Text("Plain").tag("text/plain")
                            }
                            .controlSize(.small)

                            Text("Auth Scheme:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $authScheme) {
                                Text("Bearer").tag("Bearer Token")
                                Text("API Key").tag("API Key")
                                Text("OAuth2").tag("OAuth2")
                                Text("No Auth").tag("No Auth")
                            }
                            .controlSize(.small)
                        }
                    }

                    Toggle("Deprecated Endpoint", isOn: $isDeprecated)
                        .font(.system(size: 10))
                        .controlSize(.small)

                    Divider().padding(.vertical, 4)

                    // Interactive Parameter Builder
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PARAMETER BUILDER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                            GridRow {
                                TextField("Name", text: $parameterName)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)

                                Picker("", selection: $parameterType) {
                                    Text("String").tag("String")
                                    Text("Int").tag("Integer")
                                    Text("Bool").tag("Boolean")
                                    Text("JSON").tag("Object")
                                }
                                .controlSize(.small)

                                Toggle("Req", isOn: $parameterRequired)
                                    .font(.system(size: 10))
                                    .controlSize(.small)
                            }

                            GridRow {
                                TextField("Description", text: $parameterDescription)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                                    .gridCellColumns(2)

                                Button {
                                    addParameter()
                                } label: {
                                    Image(systemName: "plus")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }

                        // Added Parameters list
                        if !customParameters.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(customParameters) { param in
                                    HStack {
                                        Text(param.name)
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        Text("(\(param.type))")
                                            .font(.system(size: 8))
                                            .foregroundStyle(.secondary)
                                        if param.isRequired {
                                            Text("Required")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.red)
                                        }
                                        Spacer()
                                        Button {
                                            customParameters.removeAll(where: { $0.id == param.id })
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(4)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // Mock Response Code Preset Simulator
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MOCK RESPONSE TEMPLATE SELECTOR")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        Picker("", selection: $simulatedResponseCode) {
                            Text("200 OK").tag("200")
                            Text("400 Bad Request").tag("400")
                            Text("401 Unauthorized").tag("401")
                            Text("500 Error").tag("500")
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)

                        Button("Insert Selected Mock JSON") {
                            insertMockJSON()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            },
            validationMessage: validationMessage
        )
    }

    private func addParameter() {
        let name = parameterName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let param = APIParameter(
            name: name,
            type: parameterType,
            isRequired: parameterRequired,
            description: parameterDescription.isEmpty ? "Field description" : parameterDescription
        )
        customParameters.append(param)
        parameterName = ""
        parameterDescription = ""
    }

    private func insertMockJSON() {
        let json: String
        switch simulatedResponseCode {
        case "200":
            json = """
            ```json
            {
              "status": "success",
              "code": 200,
              "data": {
                "id": "item_8932ac",
                "object": "api_resource",
                "version": "\(apiVersion)",
                "active": true
              }
            }
            ```
            """
        case "400":
            json = """
            ```json
            {
              "status": "fail",
              "code": 400,
              "error": {
                "type": "invalid_request_error",
                "message": "Missing required query parameters or malformed JSON payload."
              }
            }
            ```
            """
        case "401":
            json = """
            ```json
            {
              "status": "fail",
              "code": 401,
              "error": {
                "type": "authentication_error",
                "message": "Invalid auth credentials. Verification via \(authScheme) failed."
              }
            }
            ```
            """
        default:
            json = """
            ```json
            {
              "status": "error",
              "code": 500,
              "error": {
                "type": "internal_server_error",
                "message": "An unexpected server condition was encountered."
              }
            }
            ```
            """
        }
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": "\n#### Mock Response (\(simulatedResponseCode))\n" + json]
        )
    }

    private func insertTemplate() {
        let deprecationWarning = isDeprecated ? "\n> ⚠️ **DEPRECATED**: This endpoint is scheduled for removal in future releases.\n" : ""

        var parametersMarkdown = "| Name | Type | Required | Description |\n| :--- | :--- | :--- | :--- |\n"
        if customParameters.isEmpty {
            parametersMarkdown += "| id | String | Yes | Unique resource identifier |\n"
        } else {
            for param in customParameters {
                parametersMarkdown += "| \(param.name) | \(param.type) | \(param.isRequired ? "Yes" : "No") | \(param.description) |\n"
            }
        }

        let template = """

        ### API Endpoint: `\(endpointMethod)` `\(endpointPath)`
        \(deprecationWarning)
        **API Version:** `\(apiVersion)`
        **Authentication:** `\(authScheme)`
        **Content-Type:** `\(requestContentType)`
        **Rate Limit:** `\(rateLimit)`

        #### Description
        Retrieve or manipulate resources at this path.

        #### Request Headers
        | Name | Type | Required | Description |
        | :--- | :--- | :--- | :--- |
        | Content-Type | String | Yes | Must be `\(requestContentType)` |
        | Authorization | String | \(authScheme == "No Auth" ? "No" : "Yes") | \(authScheme) credentials |

        #### Request Parameters
        \(parametersMarkdown)

        #### Response (200 OK)
        ```json
        {
          "status": "success",
          "data": {
            "id": "res_983ac2",
            "name": "Sample Resource",
            "version": "\(apiVersion)",
            "deprecated": \(isDeprecated)
          }
        }
        ```
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }

    private func insertCurlCommand() {
        let authHeader = authScheme != "No Auth" ? " -H \"Authorization: \(authScheme) <TOKEN>\"" : ""
        let contentHeader = " -H \"Content-Type: \(requestContentType)\""
        let dataParam = endpointMethod != "GET" ? " -d '{\"key\":\"value\"}'" : ""

        let curl = """

        #### Sample Curl Execution Command
        ```bash
        curl -X \(endpointMethod) "https://api.project.com\(endpointPath)"\\
        \(contentHeader)\\
        \(authHeader)\(dataParam)
        ```
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": curl]
        )
    }
}
