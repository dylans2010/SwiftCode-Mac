// OnboardingWelcomeView.swift
//
// Ported from Legacy `SwiftCode/Views/Onboarding/OnboardingWelcomeView.swift` (SwiftCode-Mac migration, Views/UI worklist).
// Worklist verdict: PARTIAL.
// Missing behaviour ported: 'Ready to Build? / Get Started' step; Terms of Service line
// Wiring (wiring-views): `@EnvironmentObject AppSettings` replaced with
// `@State AppSettings.shared` — `AppSettings` is `@Observable` (Observation),
// not `ObservableObject`, and nothing injects it into the environment — and
// `.liquidGlass` replaced with thinMaterial (no `liquidGlass` modifier exists
// in the destination; cf. A6's Adaptive substitutions). The "Get Started"
// button sets `hasCompletedOnboarding`, which dismisses the first-run sheet
// in `ShellRootView`.
import SwiftUI
import SwiftCodeAssistant

struct OnboardingWelcomeView: View {
    @State private var settings = AppSettings.shared

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
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

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
