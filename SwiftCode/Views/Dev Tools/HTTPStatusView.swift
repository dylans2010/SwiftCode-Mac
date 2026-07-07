import SwiftUI

struct HTTPStatusView: View {
    @State private var searchText = ""

    let statuses = [
        (100, "Continue", "The server has received the request headers and the client should proceed to send the request body."),
        (101, "Switching Protocols", "The requester has asked the server to switch protocols."),
        (200, "OK", "Standard response for successful HTTP requests."),
        (201, "Created", "The request has been fulfilled, resulting in the creation of a new resource."),
        (202, "Accepted", "The request has been accepted for processing, but the processing has not been completed."),
        (204, "No Content", "The server successfully processed the request and is not returning any content."),
        (301, "Moved Permanently", "This and all future requests should be directed to the given URI."),
        (302, "Found", "The resource was found, but at a different URI."),
        (304, "Not Modified", "Indicates that the resource has not been modified since the version specified by the request headers."),
        (400, "Bad Request", "The server cannot or will not process the request due to an apparent client error."),
        (401, "Unauthorized", "Similar to 403 Forbidden, but specifically for use when authentication is required and has failed or has not yet been provided."),
        (403, "Forbidden", "The request was valid, but the server is refusing action."),
        (404, "Not Found", "The requested resource could not be found but may be available in the future."),
        (405, "Method Not Allowed", "A request method is not supported for the requested resource."),
        (500, "Internal Server Error", "A generic error message, given when an unexpected condition was encountered and no more specific message is suitable."),
        (502, "Bad Gateway", "The server was acting as a gateway or proxy and received an invalid response from the upstream server."),
        (503, "Service Unavailable", "The server is currently unavailable (because it is overloaded or down for maintenance)."),
        (504, "Gateway Timeout", "The server was acting as a gateway or proxy and did not receive a timely response from the upstream server.")
    ]

    var filteredStatuses: [(Int, String, String)] {
        if searchText.isEmpty {
            return statuses
        } else {
            return statuses.filter {
                "\($0.0)".contains(searchText) ||
                $0.1.lowercased().contains(searchText.lowercased())
            }
        }
    }

    var body: some View {
        VStack {
            TextField("Search status code or name...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding()

            List(filteredStatuses, id: \.0) { status in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(status.0)")
                            .font(.headline)
                            .foregroundColor(.blue)
                        Text(status.1)
                            .font(.headline)
                    }
                    Text(status.2)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("HTTP Status Codes")
    }
}
