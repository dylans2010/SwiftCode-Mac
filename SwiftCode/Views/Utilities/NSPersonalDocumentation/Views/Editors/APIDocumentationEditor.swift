import SwiftUI

public struct APIDocumentationEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var endpointMethod = "GET"
    @State private var endpointPath = "/api/v1/resource"
    @State private var apiVersion = "v1"
    @State private var requestContentType = "application/json"
    @State private var authScheme = "Bearer Token"
    @State private var rateLimit = "100 req/min"
    @State private var isDeprecated = false

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    private var validationMessage: String? {
        if endpointPath.isEmpty {
            return "Endpoint path is required"
        }
        return nil
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .apiDocumentation,
            documentID: documentID,
            specializedToolbar: {
                HStack(spacing: 8) {
                    Button {
                        insertTemplate()
                    } label: {
                        Label("API Template", systemImage: "network")
                    }
                    .buttonStyle(.bordered)
                    .help("Insert high fidelity API Endpoint template")
                }
            },
            specializedMetadata: {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("HTTP Method:")
                            .font(.caption.bold())
                        Picker("", selection: $endpointMethod) {
                            Text("GET").tag("GET")
                            Text("POST").tag("POST")
                            Text("PUT").tag("PUT")
                            Text("PATCH").tag("PATCH")
                            Text("DELETE").tag("DELETE")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 250)

                        Text("Version:")
                            .font(.caption.bold())
                        TextField("API Version", text: $apiVersion)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }

                    GridRow {
                        Text("Endpoint Path:")
                            .font(.caption.bold())
                        TextField("Path (e.g. /users)", text: $endpointPath)
                            .textFieldStyle(.roundedBorder)
                            .gridCellColumns(3)
                    }

                    GridRow {
                        Text("Content Type:")
                            .font(.caption.bold())
                        Picker("", selection: $requestContentType) {
                            Text("application/json").tag("application/json")
                            Text("application/x-www-form-urlencoded").tag("application/x-www-form-urlencoded")
                            Text("multipart/form-data").tag("multipart/form-data")
                            Text("text/plain").tag("text/plain")
                        }
                        .frame(width: 250)

                        Text("Auth Scheme:")
                            .font(.caption.bold())
                        Picker("", selection: $authScheme) {
                            Text("Bearer Token").tag("Bearer Token")
                            Text("API Key").tag("API Key")
                            Text("OAuth2").tag("OAuth2")
                            Text("No Auth").tag("No Auth")
                        }
                        .frame(width: 150)
                    }

                    GridRow {
                        Text("Rate Limit:")
                            .font(.caption.bold())
                        TextField("e.g. 60 req/min", text: $rateLimit)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 250)

                        Toggle("Deprecated", isOn: $isDeprecated)
                            .help("Mark this endpoint as deprecated")
                            .gridCellColumns(2)
                    }
                }
            },
            validationMessage: validationMessage
        )
    }

    private func insertTemplate() {
        let deprecationWarning = isDeprecated ? "\n> ⚠️ **DEPRECATED**: This endpoint is scheduled for removal in future releases.\n" : ""
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
        | Name | Type | Required | Description |
        | :--- | :--- | :--- | :--- |
        | id | String | Yes | The resource unique identifier |

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
}
