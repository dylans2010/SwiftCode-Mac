import SwiftUI

/// An alert-style UI triggered when the autonomous agent requires manual intervention.
public struct AssistUserTakeover: View {
    let reason: String
    let onResume: () -> Void
    let onAbort: () -> Void

    public init(reason: String, onResume: @escaping () -> Void, onAbort: @escaping () -> Void) {
        self.reason = reason
        self.onResume = onResume
        self.onAbort = onAbort
    }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)

            VStack(spacing: 8) {
                Text("Manual Takeover Required")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 12) {
                Button(action: onResume) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Resume Autonomous Execution")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
                }

                Button(action: onAbort) {
                    Text("Abort and Clear Plan")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .foregroundStyle(.red)
                        .cornerRadius(10)
                }
            }
        }
        .padding(24)
        .background(Color(white: 0.15))
        .cornerRadius(20)
        .shadow(radius: 20)
        .padding(40)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        AssistUserTakeover(
            reason: "The agent has encountered repeated failures on step 3 and requires human assistance to resolve a dependency conflict.",
            onResume: {},
            onAbort: {}
        )
    }
}
