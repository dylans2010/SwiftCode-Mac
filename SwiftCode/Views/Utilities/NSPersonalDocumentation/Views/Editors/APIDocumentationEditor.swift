import SwiftUI

public struct APIDocumentationEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var endpointMethod = "GET"
    @State private var endpointPath = "/api/v1/resource"
    @State private var apiVersion = "v1"

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
                            Text("DELETE").tag("DELETE")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)

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
                }
            },
            validationMessage: validationMessage
        )
    }

    private func insertTemplate() {
        let template = """

        ### API Endpoint: `\(endpointMethod)` `\(endpointPath)`

        **API Version:** `\(apiVersion)`

        #### Description
        Retrieve or manipulate resources at this path.

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
            "version": "\(apiVersion)"
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
