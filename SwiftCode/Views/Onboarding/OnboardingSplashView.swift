import SwiftUI

struct OnboardingSplashView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 150, height: 150)
                    .scaleEffect(isAnimating ? 1.2 : 0.8)
                    .opacity(isAnimating ? 0.5 : 1)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)

                Image(systemName: "swift")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .foregroundStyle(.blue)
                    .symbolEffect(.bounce, value: isAnimating)
            }

            VStack(spacing: 8) {
                Text("SwiftCode")
                    .font(.system(size: 42, weight: .bold, design: .rounded))

                Text("Next-gen iOS Development")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .offset(y: isAnimating ? 0 : 20)
            .opacity(isAnimating ? 1 : 0)
            .animation(.easeOut(duration: 0.8).delay(0.2), value: isAnimating)

            Spacer()
            Spacer()
        }
        .onAppear {
            isAnimating = true
        }
    }
}
