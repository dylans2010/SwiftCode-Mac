import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct OnboardingView: View {
    @State private var selection = 0

    var body: some View {
        ZStack {
            #if canImport(AppKit)
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()
            #else
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            #endif

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
