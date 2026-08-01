import SwiftUI

struct PackageExplorerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var platformManager = DependencyPlatformManager.shared
    @State private var selectedCategory: String = "All"
    @State private var searchQuery: String = ""

    let categories = ["All", "Networking", "Database", "UI", "Utility", "Analytics", "Cryptography"]

    var filteredFeatured: [PackageMetadata] {
        if selectedCategory == "All" {
            return platformManager.featuredPackages
        } else {
            return platformManager.featuredPackages.filter { $0.topics.contains(selectedCategory.lowercased()) }
        }
    }

    var filteredTrending: [PackageMetadata] {
        if selectedCategory == "All" {
            return platformManager.trendingPackages
        } else {
            return platformManager.trendingPackages.filter { $0.topics.contains(selectedCategory.lowercased()) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("[", modifiers: .command)

                Text("Package Discovery Explorer")
                    .font(.title2.bold())

                Spacer()

                Picker("", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { cat in
                        Text(cat).tag(cat)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    // Continuing browsing section
                    if !platformManager.continueBrowsing.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Continue Browsing", systemImage: "clock.arrow.circlepath")
                                .font(.headline)
                                .foregroundStyle(.blue)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(platformManager.continueBrowsing, id: \.self) { url in
                                        let name = url.split(separator: "/").last?.replacingOccurrences(of: ".git", with: "") ?? url
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(name)
                                                .font(.headline)
                                                .lineLimit(1)
                                            Text(url)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        .padding()
                                        .frame(width: 200, alignment: .leading)
                                        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }

                    // Featured Grid
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Featured & Editor's Picks", systemImage: "sparkles")
                            .font(.headline)
                            .foregroundStyle(.orange)

                        if filteredFeatured.isEmpty {
                            ContentUnavailableView {
                                Label("No Featured Packages", systemImage: "tray")
                            } description: {
                                Text("No featured packages found in category \(selectedCategory).")
                            }
                            .frame(height: 120)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: .infinity))], spacing: 16) {
                                ForEach(filteredFeatured) { pkg in
                                    NavigationLink(destination: PackageDetailsView(package: pkg)) {
                                        VStack(alignment: .leading, spacing: 10) {
                                            HStack {
                                                Text(pkg.name)
                                                    .font(.headline)
                                                    .foregroundStyle(.primary)
                                                Spacer()
                                                if pkg.isVerified {
                                                    Image(systemName: "checkmark.seal.fill")
                                                        .foregroundStyle(.blue)
                                                }
                                            }

                                            Text(pkg.description ?? "No description available.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                                .frame(height: 36, alignment: .topLeading)

                                            HStack {
                                                Label("\(pkg.stars) stars", systemImage: "star.fill")
                                                    .foregroundStyle(.yellow)
                                                Spacer()
                                                Text(pkg.license ?? "MIT")
                                                    .font(.caption2)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                                            }
                                            .font(.caption)
                                        }
                                        .padding()
                                        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    // Trending / Popular Grid
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Trending & Recently Released", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.headline)
                            .foregroundStyle(.purple)

                        if filteredTrending.isEmpty {
                            ContentUnavailableView {
                                Label("No Trending Packages", systemImage: "star")
                            } description: {
                                Text("No trending packages found in category \(selectedCategory).")
                            }
                            .frame(height: 120)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: .infinity))], spacing: 16) {
                                ForEach(filteredTrending) { pkg in
                                    NavigationLink(destination: PackageDetailsView(package: pkg)) {
                                        VStack(alignment: .leading, spacing: 10) {
                                            HStack {
                                                Text(pkg.name)
                                                    .font(.headline)
                                                    .foregroundStyle(.primary)
                                                Spacer()
                                                Image(systemName: "arrow.up.right.circle.fill")
                                                    .foregroundStyle(.purple)
                                            }

                                            Text(pkg.description ?? "No description available.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                                .frame(height: 36, alignment: .topLeading)

                                            HStack {
                                                Text("v\(pkg.lastReleasedVersion)")
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                                Spacer()
                                                Label("\(pkg.stars) stars", systemImage: "star.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.yellow)
                                            }
                                        }
                                        .padding()
                                        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    // AI Recommendations section
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("AI Copilot Recommendations", systemImage: "sparkles")
                                    .font(.headline)
                                    .foregroundStyle(.blue)
                                Spacer()
                            }
                            Text("Looking for a specialized toolkit? Ask our AI Package Assistant to map architecture profiles dynamically matching deployment targets.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                    .padding(.horizontal, 24)
                }
                .padding(.vertical, 24)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
