import SwiftUI

struct PasswordStrengthMeterView: View {
    @State private var password = ""
    @State private var strength: Double = 0
    @State private var feedback = "Enter a password"

    var body: some View {
        VStack(spacing: 20) {
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .padding()
                .onChange(of: password) { checkStrength() }

            ProgressView(value: strength)
                .accentColor(strengthColor)
                .padding(.horizontal)

            Text(feedback)
                .font(.headline)
                .foregroundColor(strengthColor)

            List {
                StrengthCriteriaRow(label: "At least 8 characters", met: password.count >= 8)
                StrengthCriteriaRow(label: "Contains uppercase", met: password.rangeOfCharacter(from: .uppercaseLetters) != nil)
                StrengthCriteriaRow(label: "Contains lowercase", met: password.rangeOfCharacter(from: .lowercaseLetters) != nil)
                StrengthCriteriaRow(label: "Contains number", met: password.rangeOfCharacter(from: .decimalDigits) != nil)
                StrengthCriteriaRow(label: "Contains symbol", met: password.rangeOfCharacter(from: .punctuationCharacters) != nil || password.rangeOfCharacter(from: .symbols) != nil)
            }

            Spacer()
        }
        .navigationTitle("Password Strength Meter")
    }

    var strengthColor: Color {
        if strength < 0.3 { return .red }
        if strength < 0.7 { return .orange }
        return .green
    }

    func checkStrength() {
        var score: Double = 0
        if password.count >= 8 { score += 0.2 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { score += 0.2 }
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil { score += 0.2 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { score += 0.2 }
        if password.rangeOfCharacter(from: .punctuationCharacters) != nil || password.rangeOfCharacter(from: .symbols) != nil { score += 0.2 }
        strength = score

        if strength == 0 { feedback = "Enter a password" }
        else if strength < 0.4 { feedback = "Weak" }
        else if strength < 0.8 { feedback = "Fair" }
        else { feedback = "Strong" }
    }
}

struct StrengthCriteriaRow: View {
    let label: String
    let met: Bool
    var body: some View {
        HStack {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundColor(met ? .green : .secondary)
            Text(label)
                .foregroundColor(met ? .primary : .secondary)
        }
    }
}
