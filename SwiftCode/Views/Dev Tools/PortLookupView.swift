import SwiftUI

struct PortLookupView: View {
    @State private var searchText = ""

    let commonPorts = [
        (20, "FTP", "File Transfer Protocol (Data Transfer)"),
        (21, "FTP", "File Transfer Protocol (Control)"),
        (22, "SSH", "Secure Shell"),
        (23, "Telnet", "Unencrypted text messages"),
        (25, "SMTP", "Simple Mail Transfer Protocol"),
        (53, "DNS", "Domain Name System"),
        (80, "HTTP", "Hypertext Transfer Protocol"),
        (110, "POP3", "Post Office Protocol version 3"),
        (123, "NTP", "Network Time Protocol"),
        (143, "IMAP", "Internet Message Access Protocol"),
        (443, "HTTPS", "HTTP over TLS/SSL"),
        (445, "SMB", "Server Message Block"),
        (548, "AFP", "Apple Filing Protocol"),
        (3000, "React/Node", "Common development port"),
        (3306, "MySQL", "MySQL database system"),
        (5432, "PostgreSQL", "PostgreSQL database system"),
        (6379, "Redis", "Redis key-value store"),
        (8080, "HTTP Alt", "Alternative port for HTTP"),
        (27017, "MongoDB", "MongoDB NoSQL database")
    ]

    var filteredPorts: [(Int, String, String)] {
        if searchText.isEmpty {
            return commonPorts
        } else {
            return commonPorts.filter {
                "\($0.0)".contains(searchText) ||
                $0.1.lowercased().contains(searchText.lowercased()) ||
                $0.2.lowercased().contains(searchText.lowercased())
            }
        }
    }

    var body: some View {
        VStack {
            TextField("Search port, service or description...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding()

            List(filteredPorts, id: \.0) { port in
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text("\(port.0)")
                            .font(.system(.headline, design: .monospaced))
                            .foregroundColor(.orange)
                        Text(port.1)
                            .font(.headline)
                    }
                    .frame(width: 80, alignment: .leading)

                    Text(port.2)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Port Lookup")
    }
}
