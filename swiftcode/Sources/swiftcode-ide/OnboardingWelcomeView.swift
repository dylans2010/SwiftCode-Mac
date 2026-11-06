// OnboardingWelcomeView.swift
//
// Ported from Legacy `SwiftCode/Views/Onboarding/OnboardingWelcomeView.swift` (SwiftCode-Mac migration, Views/UI worklist).
// Worklist verdict: PARTIAL.
// Missing behaviour ported: 'Ready to Build? / Get Started' step; Terms of Service line
// References legacy types absent from the destination and from this worklist (wiring/integration gaps): AppSettings.
// Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
import SwiftUI

struct OnboardingWelcomeView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            if #available(iOS 18.0, macOS 15.0, *) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, options: .repeat(2))
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 12) {
                Text("Ready to Build?")
                    .font(.system(size: 32, weight: .bold, design: .rounded))

                Text("SwiftCode is your companion for building and deploying amazing iOS and Web applications directly from your device.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            }
            .padding(16)
            .liquidGlass(style: .standard, cornerRadius: 16)

            Spacer()

            Button {
                withAnimation {
                    settings.hasCompletedOnboarding = true
                }
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)

            Text("By continuing, you agree to our Terms of Service.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
    }
}
