import SwiftUI

public struct DeviceConnectSidebar: View {
    @State private var searchField = ""

    // We bind to our global managers
    @State private var deviceManager = DeviceManager.shared
    @State private var sessionManager = SessionManager.shared
    @State private var environmentManager = EnvironmentManager.shared

    @Binding var currentSelection: String // "dashboard", "sessions", "environment", "settings"

    public init(currentSelection: Binding<String>) {
        self._currentSelection = currentSelection
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search devices...", text: $searchField)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding()

            List {
                Section(header: Text("Dashboard")) {
                    Button(action: { currentSelection = "dashboard" }) {
                        Label("Deployment Center", systemImage: "play.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(currentSelection == "dashboard" ? Color.accentColor : .primary)
                }

                Section(header: Text("Connected Devices")) {
                    if deviceManager.devices.isEmpty {
                        Text("No Devices Connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                    } else {
                        ForEach(deviceManager.devices.filter { searchField.isEmpty || $0.name.localizedCaseInsensitiveContains(searchField) }) { device in
                            Button(action: {
                                deviceManager.selectDevice(device)
                                currentSelection = "dashboard"
                            }) {
                                HStack {
                                    Image(systemName: "iphone")
                                        .font(.title3)
                                        .foregroundStyle(deviceManager.selectedDevice?.udid == device.udid ? .blue : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text("\(device.model) • OS \(device.osVersion)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if deviceManager.selectedDevice?.udid == device.udid {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section(header: Text("Diagnostics & Suite")) {
                    Button(action: { currentSelection = "sessions" }) {
                        Label("Deployment Sessions", systemImage: "doc.text.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(currentSelection == "sessions" ? Color.accentColor : .primary)

                    Button(action: { currentSelection = "environment" }) {
                        Label("System Environment", systemImage: "checkmark.seal.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(currentSelection == "environment" ? Color.accentColor : .primary)

                    Button(action: { currentSelection = "settings" }) {
                        Label("Preferences", systemImage: "gearshape.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(currentSelection == "settings" ? Color.accentColor : .primary)
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 200, maxWidth: .infinity)
    }
}
