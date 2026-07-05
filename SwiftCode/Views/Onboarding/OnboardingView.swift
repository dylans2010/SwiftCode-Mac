import SwiftUI

struct OnboardingView: View {
    @State private var selection = 0

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            TabView(selection: $selection) {
                OnboardingSplashView()
                    .tag(0)

                OnboardingFeaturesView()
                    .tag(1)

                OnboardingWelcomeView()
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }
}
