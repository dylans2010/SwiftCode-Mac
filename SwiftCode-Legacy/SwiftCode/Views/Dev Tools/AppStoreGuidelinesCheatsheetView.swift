import SwiftUI

struct GuidelineSection: Identifiable {
    let id = UUID()
    let number: String
    let title: String
    let description: String
    let checklist: [String]
}

public struct AppStoreGuidelinesCheatsheetView: View {
    private let guidelines = [
        GuidelineSection(
            number: "1. Safety",
            title: "User-Generated Content & Moderation",
            description: "Apps must not contain offensive, insensitive, or harmful material.",
            checklist: [
                "Include a mechanism to filter objectionable material.",
                "Provide a mechanism for users to flag/report content.",
                "Provide a mechanism to block abusive users.",
                "Expose clear developer contact details for immediate support requests."
            ]
        ),
        GuidelineSection(
            number: "2. Performance",
            title: "Completeness & Stability",
            description: "Apps should be final versions, fully complete, and free of placeholder metadata.",
            checklist: [
                "Verify no crashes or major execution hangs occur during reviews.",
                "Ensure all URLs, privacy policy endpoints, and support links are valid.",
                "Configure a valid Demo Account credential inside the app review notes.",
                "Erase any test code, empty frameworks, or standard boilerplate placeholders."
            ]
        ),
        GuidelineSection(
            number: "3. Business",
            title: "In-App Purchases & Subscriptions",
            description: "Payments must use Apple's native StoreKit APIs where appropriate.",
            checklist: [
                "Do not include external web checkout links for digital services.",
                "Ensure restoring purchases works correctly and immediately.",
                "Clearly list auto-renewing subscription terms in the description text.",
                "Configure active, valid StoreKit configuration test files locally."
            ]
        )
    ]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("App Store Submission Playbook")
                        .font(.title.bold())
                    Text("Audit and prepare your app targets for successful Apple App Store App Review cycles.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                ForEach(guidelines) { section in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(section.number)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.12))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)

                                Text(section.title)
                                    .font(.headline)
                                Spacer()
                            }

                            Text(section.description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text("COMPLIANCE CHECKLIST")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)

                                ForEach(section.checklist, id: \.self) { item in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "square.dashed")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                            .padding(.top, 2)
                                        Text(item)
                                            .font(.subheadline)
                                    }
                                }
                            }
                        }
                        .padding(10)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
