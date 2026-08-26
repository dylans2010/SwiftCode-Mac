import SwiftUI

struct ConnectSettingsView: View {
    @State private var trustStore = TrustStore.shared
    @State private var connectServer = ConnectServer.shared
    @State private var bonjour = BonjourAdvertiser.shared
    @State private var discovery = IOSDiscoveryService.shared
    @State private var diagnostics = ConnectDiagnostics.shared

    @State private var portInputString: String = ""
    @State private var manualHostInput: String = ""
    @State private var manualPortInput: String = "\(ConnectProtocol.defaultPort)"
    @State private var isConnectingManual: Bool = false
    @State private var manualErrorMessage: String?
    @State private var showPortErrorAlert: Bool = false
    @State private var portErrorMessage: String = ""
    @State private var showDiagnostics: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                thisMacSection
                nearbyDevicesSection
                manualConnectSection
                connectedDevicesSection
                trustedDevicesSection
                diagnosticsSection
            }
            .padding()
        }
        .onAppear {
            portInputString = "\(connectServer.configuredPort)"
            diagnostics.refreshLocalIP()
            if !connectServer.isRunning {
                Task {
                    do {
                        try await connectServer.startServer()
                    } catch {
                        portErrorMessage = error.localizedDescription
                    }
                }
            }
        }
        .alert("Port Unavailable", isPresented: $showPortErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(portErrorMessage)
        }
        .sheet(item: Binding(
            get: { PairingManager.shared.activePairingRequest },
            set: { _ in }
        )) { _ in
            ConnectPairingApprovalSheet()
        }
    }

    // MARK: - 1. This Mac Section
    private var thisMacSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                        .font(.system(size: 24))
                        .foregroundColor(connectServer.isRunning ? .green : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("This Mac — SwiftCode Connect Host")
                            .font(.headline)
                        Text(connectServer.isRunning ? "Advertising as '\(bonjour.macName)' on \(diagnostics.localIPAddress)" : "Service is stopped")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle(connectServer.isRunning ? "Active" : "Disabled", isOn: Binding(
                        get: { connectServer.isRunning },
                        set: { newValue in
                            Task {
                                if newValue {
                                    do {
                                        try await connectServer.startServer()
                                    } catch {
                                        portErrorMessage = error.localizedDescription
                                        showPortErrorAlert = true
                                    }
                                } else {
                                    connectServer.stopServer()
                                }
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                }

                Divider()

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connection Port")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            TextField("Port", text: $portInputString)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)

                            Button("Apply") {
                                applyPortChange()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(portInputString.isEmpty)
                        }
                    }

                    Divider()
                        .frame(height: 36)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Listener Status")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(connectServer.isRunning ? Color.green : Color.secondary)
                                .frame(width: 8, height: 8)
                            Text(connectServer.isRunning ? "Listening (Port \(connectServer.activePort ?? connectServer.configuredPort))" : "Stopped")
                                .font(.subheadline)
                        }
                    }

                    Divider()
                        .frame(height: 36)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bonjour Discovery")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(bonjour.isAdvertising ? Color.blue : Color.secondary)
                                .frame(width: 8, height: 8)
                            Text(bonjour.isAdvertising ? "Advertising (\(ConnectProtocol.serviceType))" : "Inactive")
                                .font(.subheadline)
                        }
                    }

                    Spacer()
                }
            }
            .padding(12)
        }
    }

    // MARK: - 2. Nearby Devices (Discovered iOS)
    private var nearbyDevicesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Nearby iOS Devices", systemImage: "iphone.radiowaves.left.and.right")
                        .font(.headline)

                    Spacer()

                    if discovery.isScanning {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    Button {
                        discovery.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Refresh discovered iOS devices")
                }

                if discovery.discoveredDevices.isEmpty {
                    Text("No SwiftCode iOS devices detected on your network.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(discovery.discoveredDevices) { device in
                        HStack {
                            Image(systemName: "iphone")
                                .font(.title2)
                                .foregroundColor(.blue)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(device.name)
                                        .font(.body).bold()
                                    Text("v\(device.protocolVersion)")
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .background(Color.blue.opacity(0.15))
                                        .cornerRadius(4)
                                }
                                Text("\(device.host):\(device.port)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                Text("Available")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.trailing, 8)

                            Button("Connect") {
                                connectToDiscovered(device)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - 3. Manual Connection Section
    private var manualConnectSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Manual Device Connection", systemImage: "cable.connector")
                    .font(.headline)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Host / IP Address")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g. 192.168.1.40", text: $manualHostInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 160)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Port")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Port", text: $manualPortInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(" ")
                            .font(.caption)
                        Button(isConnectingManual ? "Connecting…" : "Connect") {
                            connectManual()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(manualHostInput.isEmpty || manualPortInput.isEmpty || isConnectingManual)
                    }

                    Spacer()
                }

                if let error = manualErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(12)
        }
    }

    // MARK: - 4. Connected Devices Section
    private var connectedDevicesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Connected Devices (\(connectServer.activeSessions.count))", systemImage: "link.circle.fill")
                        .font(.headline)
                    Spacer()
                }

                if connectServer.activeSessions.isEmpty {
                    Text("No iOS devices currently connected.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(connectServer.activeSessions) { session in
                        HStack {
                            Image(systemName: "iphone.badge.checkmark")
                                .font(.title2)
                                .foregroundColor(.green)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(session.deviceName ?? "iOS Device")
                                        .font(.body).bold()
                                    Text("● \(session.state.rawValue.capitalized)")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                                Text("Remote: \(session.remoteHost ?? "0.0.0.0"):\(session.remotePort ?? 0) • Session: \(session.id.uuidString.prefix(8))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                HStack(spacing: 6) {
                                    ForEach(Array(session.grantedPermissions).prefix(4), id: \.self) { perm in
                                        Text(perm.rawValue)
                                            .font(.system(size: 9))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(3)
                                    }
                                }
                                .padding(.top, 2)
                            }

                            Spacer()

                            Button("Disconnect") {
                                session.disconnect()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - 5. Trusted Devices Section
    private var trustedDevicesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Trusted iOS Devices (\(trustStore.trustedDevices.count))", systemImage: "lock.shield")
                        .font(.headline)
                    Spacer()
                }

                if trustStore.trustedDevices.isEmpty {
                    Text("No paired devices registered.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(trustStore.trustedDevices) { device in
                        HStack {
                            Image(systemName: device.isRevoked ? "iphone.slash" : "iphone")
                                .font(.title3)
                                .foregroundColor(device.isRevoked ? .red : .green)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(device.name)
                                        .font(.body).bold()
                                    if device.isRevoked {
                                        Text("Revoked")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .background(Color.red.opacity(0.2))
                                            .foregroundColor(.red)
                                            .cornerRadius(4)
                                    }
                                }
                                Text("Model: \(device.model) • Paired: \(device.pairingDate.formatted(date: .numeric, time: .omitted))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if device.isRevoked {
                                Button("Trust") {
                                    trustStore.registerDevice(TrustedDevice(
                                        id: device.id,
                                        name: device.name,
                                        model: device.model,
                                        pairingDate: device.pairingDate,
                                        lastConnection: Date(),
                                        sessionToken: device.sessionToken,
                                        permissions: device.permissions,
                                        isRevoked: false
                                    ))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            } else {
                                Button("Revoke") {
                                    trustStore.revokeDevice(deviceID: device.id)
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                .controlSize(.small)
                            }

                            Button(role: .destructive) {
                                trustStore.deleteDevice(deviceID: device.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - 6. Diagnostics Section
    private var diagnosticsSection: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $showDiagnostics) {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()

                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                        GridRow {
                            Text("Local Host:").bold()
                            Text(diagnostics.localIPAddress)
                        }
                        GridRow {
                            Text("Local Port:").bold()
                            Text("\(connectServer.activePort ?? connectServer.configuredPort)")
                        }
                        GridRow {
                            Text("Listener Status:").bold()
                            Text(connectServer.isRunning ? "Active (Port \(connectServer.activePort ?? connectServer.configuredPort))" : "Stopped")
                        }
                        GridRow {
                            Text("Bonjour Service:").bold()
                            Text(bonjour.isAdvertising ? "Advertising (\(ConnectProtocol.serviceType))" : "Stopped")
                        }
                        GridRow {
                            Text("Protocol Version:").bold()
                            Text("v\(ConnectProtocolVersion.current)")
                        }
                    }
                    .font(.caption)

                    let sessionDiagnostics = diagnostics.getDiagnostics(server: connectServer, bonjour: bonjour, discovery: discovery)
                    if !sessionDiagnostics.isEmpty {
                        Divider()
                        Text("Active Session Details")
                            .font(.caption.bold())

                        ForEach(sessionDiagnostics) { diag in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(diag.deviceName) (\(diag.deviceType))")
                                    .font(.caption.bold())
                                Text("Remote: \(diag.remoteHost):\(diag.remotePort) • Local: \(diag.localHost):\(diag.localPort)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text("Transport: \(diag.transport) • Auth: \(diag.authStatus) • State: \(diag.sessionState)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(6)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Developer Diagnostics", systemImage: "wrench.and.screwdriver")
                    .font(.headline)
            }
            .padding(12)
        }
    }

    // MARK: - Actions
    private func applyPortChange() {
        guard let port = UInt16(portInputString), ConnectProtocol.validPortRange.contains(port) else {
            portErrorMessage = "Invalid port number. Please enter a port between \(ConnectProtocol.validPortRange.lowerBound) and \(ConnectProtocol.validPortRange.upperBound)."
            showPortErrorAlert = true
            return
        }

        Task {
            do {
                try await connectServer.applyPort(port)
                portErrorMessage = ""
            } catch {
                portErrorMessage = "SwiftCode could not listen on port \(port). The port may already be in use."
                showPortErrorAlert = true
                portInputString = "\(connectServer.configuredPort)"
            }
        }
    }

    private func connectToDiscovered(_ device: DiscoveredIOSDevice) {
        Task {
            do {
                _ = try await connectServer.connectToDevice(host: device.host, port: device.port)
            } catch {
                manualErrorMessage = "Failed to connect to \(device.name): \(error.localizedDescription)"
            }
        }
    }

    private func connectManual() {
        guard let port = UInt16(manualPortInput), ConnectProtocol.validPortRange.contains(port) else {
            manualErrorMessage = "Invalid port number"
            return
        }

        isConnectingManual = true
        manualErrorMessage = nil

        Task {
            defer { isConnectingManual = false }
            do {
                _ = try await connectServer.connectToDevice(host: manualHostInput, port: port)
            } catch {
                manualErrorMessage = error.localizedDescription
            }
        }
    }
}
