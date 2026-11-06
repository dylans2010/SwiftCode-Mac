// Ported from Legacy `SwiftCode/Views/Onboarding/OnboardingFeaturesView.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged only — not yet merged into swiftcode/Sources. See staging-wire/missing/DISPOSITIONS.md.
// Verbatim except `.liquidGlass(...)` -> thinMaterial (see Adaptive notes).
// Self-contained feature list (Modern IDE / AI Powered / Cloud Deployment cards).
// Wiring: WelcomeView (swiftcode-ide) onboarding flow — present as a page/section;
// no feature list exists there yet.

import SwiftUI

struct OnboardingFeaturesView: View {
    let features = [
        FeatureItem(title: "Modern IDE", description: "Full-featured editor with syntax highlighting and auto-completion.", icon: "doc.text.fill", color: .blue),
        FeatureItem(title: "AI Powered", description: "Get smart suggestions and code reviews powered by advanced ML models.", icon: "sparkles", color: .purple),
        FeatureItem(title: "Cloud Deployment", description: "One-click deployment to Netlify, Vercel, and GitHub Pages.", icon: "cloud.fill", color: .orange)
    ]

    var body: some View {
        VStack(spacing: 40) {
            Text("Powerful Features")
                .font(.system(size: 32, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 30) {
                ForEach(features) { feature in
                    HStack(spacing: 20) {
                        Image(systemName: feature.icon)
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(width: 60, height: 60)
                            .background(feature.color.gradient, in: RoundedRectangle(cornerRadius: 15))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(feature.title)
                                .font(.headline)
                            Text(feature.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 40)
    }
}

struct FeatureItem: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let color: Color
}
