import SwiftUI

struct LocalBuildView: View {
    @StateObject private var discoveryService = MacDiscoveryService()
    @StateObject private var buildService = LocalBuildService()
    @EnvironmentObject private var projectManager: ProjectManager
    @State private var selectedMac: DiscoveredMac?
    @State private var buildResultURL: URL?
    @State private var showDemo = false

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    headerSection

                    if buildService.isBuilding || !buildService.buildLogs.isEmpty {
                        buildProgressSection
                    } else {
                        macDiscoverySection
                    }

                    if let resultURL = buildResultURL {
                        buildResultSection(url: resultURL)
                    }

                    demoButton
                }
                .padding()
            }
        }
        .navigationTitle("Local Build")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            discoveryService.startScanning()
        }
        .sheet(isPresented: $showDemo) {
            LocalBuildDemoView()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "macmini.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .padding(.bottom, 8)

            Text("Local Mac Build")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text("Build and sign your app using a Mac on your network.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical)
    }

    private var macDiscoverySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Detected Macs")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if discoveryService.isScanning {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button {
                        discoveryService.startScanning()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline)
                    }
                }
            }

            if discoveryService.discoveredMacs.isEmpty {
                if discoveryService.isScanning {
                    Text("Searching for Macs…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    VStack(spacing: 12) {
                        Text("No Macs found on your network.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Make sure the SwiftCode Mac Helper is running on your Mac and both devices are on the same Wi-Fi.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(discoveryService.discoveredMacs) { mac in
                        Button {
                            selectedMac = mac
                        } label: {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading) {
                                    Text(mac.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white)
                                    Text(mac.host)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedMac == mac {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding()
                            .background(selectedMac == mac ? Color.blue.opacity(0.1) : Color.white.opacity(0.05))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(selectedMac == mac ? Color.blue : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                startBuild()
            } label: {
                Text("Start Build")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(selectedMac == nil ? Color.gray : Color.blue, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
            }
            .disabled(selectedMac == nil || buildService.isBuilding)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }

    private var buildProgressSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Build Status")
                .font(.headline)
                .foregroundStyle(.white)

            ProgressView(value: buildService.progress)
                .tint(.blue)

            VStack(alignment: .leading, spacing: 8) {
                Text("Build Logs")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(buildService.buildLogs) { log in
                                Text(log.status)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.green.opacity(0.9))
                                    .id(log.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 150)
                    .padding(8)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(8)
                    .onChange(of: buildService.buildLogs.count) {
                        if let last = buildService.buildLogs.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }

    private func buildResultSection(url: URL) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "app.badge.checkmark.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)

            Text("Build Successful")
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                Button {
                    // Install logic
                } label: {
                    Label("Install", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                }

                ShareLink(item: url) {
                    Label("Download", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }

    private var demoButton: some View {
        Button {
            showDemo = true
        } label: {
            Text("Try Build Demo")
                .font(.caption)
                .foregroundStyle(.blue)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color.blue.opacity(0.1), in: Capsule())
        }
        .padding(.top)
    }

    private func startBuild() {
        guard let mac = selectedMac, let project = projectManager.activeProject else { return }

        Task {
            do {
                buildResultURL = try await buildService.startBuild(on: mac, project: project)
            } catch {
                print("Build failed: \(error)")
            }
        }
    }
}
