import SwiftUI

public struct XcodeProjViewer: View {
    public let model: XcodeProjModel
    @Environment(\.dismiss) private var dismiss

    // Modern Tab Selection
    @State private var selectedCategory = "overview"
    @State private var selectedTarget: PBXTarget? = nil
    @State private var showingTargetDetail = false
    @State private var searchState = ""

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Elegant Header Area
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.orange.opacity(0.15).gradient)
                    Image(systemName: "hammer.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange.gradient)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.projectURL.lastPathComponent)
                        .font(.headline)
                    Text("Xcode Project Workspace Dashboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search build settings...", text: $searchState)
                        .textFieldStyle(.plain)
                        .frame(width: 160)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding()
            .background(.thinMaterial)

            Divider()

            // Segmented Picker for Categories (Replacing Sidebars!)
            Picker("", selection: $selectedCategory) {
                Text("Overview").tag("overview")
                Text("Targets").tag("targets")
                Text("Build Settings").tag("settings")
                Text("Packages").tag("packages")
                Text("Configurations").tag("configs")
                Text("Metadata").tag("metadata")
            }
            .pickerStyle(.segmented)
            .padding()
            .background(.regularMaterial)

            Divider()

            // Main Detail Area
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedCategory {
                    case "overview":
                        ProjectOverviewTabView(model: model)
                            .padding()

                    case "targets":
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Project Targets")
                                .font(.title3.bold())
                                .padding(.horizontal)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                                ForEach(model.targets) { target in
                                    Button {
                                        selectedTarget = target
                                        showingTargetDetail = true
                                    } label: {
                                        VStack(alignment: .leading, spacing: 10) {
                                            HStack {
                                                Image(systemName: "target")
                                                    .font(.title3)
                                                    .foregroundStyle(.orange)
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }

                                            Text(target.name)
                                                .font(.headline)
                                                .foregroundStyle(.primary)

                                            if let pType = target.productType {
                                                Text(pType.replacingOccurrences(of: "com.apple.product-type.", with: ""))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        .padding()
                                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.vertical)

                    case "settings":
                        BuildSettingsTabView(model: model, searchQuery: searchState)
                            .padding()

                    case "packages":
                        PackagesTabView(model: model)
                            .padding()

                    case "configs":
                        BuildConfigurationsTabView(model: model)
                            .padding()

                    case "metadata":
                        MetadataTabView(model: model)
                            .padding()

                    default:
                        ProjectOverviewTabView(model: model)
                            .padding()
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .sheet(isPresented: $showingTargetDetail) {
            if let target = selectedTarget {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(target.name)
                                .font(.headline)
                            Text("Target Configuration Details")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Close") {
                            showingTargetDetail = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    .padding()
                    .background(.thinMaterial)

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            GeneralTabView(model: model, selectedTargetID: target.uuid)
                            IdentityTabView(model: model, selectedTargetID: target.uuid)
                            DeploymentTabView(model: model, selectedTargetID: target.uuid)
                            SigningCapabilitiesTabView(model: model)
                            EntitlementsTabView(model: model)
                            InfoPlistTabView(model: model)
                        }
                        .padding()
                    }
                }
                .frame(width: 650, height: 500)
            }
        }
    }
}
