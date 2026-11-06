// OnboardingView.swift
//
// Ported from Legacy `SwiftCode/Views/Onboarding/OnboardingView.swift` (SwiftCode-Mac migration, Views/UI worklist).
// Worklist verdict: PARTIAL.
// Missing behaviour ported: the three-step tabbed splash to features to welcome flow
// References legacy types absent from the destination and from this worklist (wiring/integration gaps): OnboardingFeaturesView, OnboardingSplashView.
// Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
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
        }
    }
}
