import SwiftUI

public struct XcodeProjViewer: View {
    public let model: XcodeProjModel
    @Environment(\.dismiss) private var dismiss

    // Modern Tab Selection
    @State private var selectedCategory = "overview"
    @State private var selectedTarget: PBXTarget? = nil
    @State private var selectedSubTab = "general"
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
            VStack(spacing: 0) {
                switch selectedCategory {
                case "overview":
                    ScrollView {
                        ProjectOverviewTabView(model: model)
                            .padding()
                    }

                case "targets":
                    HStack(alignment: .top, spacing: 0) {
                        // Left Panel: Targets List
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TARGETS")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .padding([.top, .horizontal], 16)

                            List(model.targets, id: \.uuid, selection: $selectedTarget) { target in
                                HStack {
                                    Image(systemName: "target")
                                        .font(.title3)
                                        .foregroundStyle(selectedTarget?.uuid == target.uuid ? Color.orange : Color.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(target.name)
                                            .font(.headline)
                                            .foregroundStyle(selectedTarget?.uuid == target.uuid ? .primary : .primary.opacity(0.8))
                                        if let pType = target.productType {
                                            Text(pType.replacingOccurrences(of: "com.apple.product-type.", with: ""))
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                                .tag(target)
                            }
                            .listStyle(.sidebar)
                        }
                        .frame(width: 240)

                        Divider()

                        // Right Panel: Inline Target Details & Interactive Settings Editor
                        if let target = selectedTarget {
                            VStack(alignment: .leading, spacing: 0) {
                                // Sub-tabs for Config editing (General, Identity, Deployment, Signing, Info.plist, Entitlements)
                                Picker("", selection: $selectedSubTab) {
                                    Text("General").tag("general")
                                    Text("Identity").tag("identity")
                                    Text("Deployment").tag("deployment")
                                    Text("Signing").tag("signing")
                                    Text("Info.plist").tag("infoplist")
                                    Text("Entitlements").tag("entitlements")
                                }
                                .pickerStyle(.segmented)
                                .padding()
                                .background(Color.secondary.opacity(0.04))

                                Divider()

                                switch selectedSubTab {
                                case "general":
                                    ScrollView {
                                        GeneralTabView(model: model, selectedTargetID: target.uuid)
                                            .padding()
                                    }
                                case "identity":
                                    ScrollView {
                                        IdentityTabView(model: model, selectedTargetID: target.uuid)
                                            .padding()
                                    }
                                case "deployment":
                                    ScrollView {
                                        DeploymentTabView(model: model, selectedTargetID: target.uuid)
                                            .padding()
                                    }
                                case "signing":
                                    ScrollView {
                                        SigningCapabilitiesTabView(model: model)
                                            .padding()
                                    }
                                case "infoplist":
                                    InfoPlistTabView(model: model)
                                case "entitlements":
                                    EntitlementsTabView(model: model)
                                default:
                                    ScrollView {
                                        GeneralTabView(model: model, selectedTargetID: target.uuid)
                                            .padding()
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ContentUnavailableView("No Target Selected", systemImage: "target", description: Text("Select a target from the list to view and edit its properties inline."))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }

                case "settings":
                    ScrollView {
                        BuildSettingsTabView(model: model, searchQuery: searchState)
                            .padding()
                    }

                case "packages":
                    ScrollView {
                        PackagesTabView(model: model)
                            .padding()
                    }

                case "configs":
                    ScrollView {
                        BuildConfigurationsTabView(model: model)
                            .padding()
                    }

                case "metadata":
                    ScrollView {
                        MetadataTabView(model: model)
                            .padding()
                    }

                default:
                    ScrollView {
                        ProjectOverviewTabView(model: model)
                            .padding()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 950, minHeight: 650)
        .onAppear {
            if selectedTarget == nil {
                selectedTarget = model.targets.first
            }
        }
    }
}
