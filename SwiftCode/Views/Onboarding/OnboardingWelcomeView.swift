import SwiftUI

struct OnboardingWelcomeView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            if #available(iOS 18.0, *) {
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

            Spacer()

            Button {
                withAnimation {
                    settings.hasCompletedOnboarding = true
                }
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 40)
            }
            .buttonStyle(.plain)

            Text("By continuing, you agree to our Terms of Service.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
    }
}
