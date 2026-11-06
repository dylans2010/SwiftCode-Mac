// Ported from SwiftCode-Legacy `SwiftCode/Views/Developer/EnvironmentSwitcherView.swift` (Dylan's own code; direct port authorised under MIT).
// V10 (independent verification): confirmed genuinely missing from production at bc28f653.
import SwiftUI
import SwiftCodeUI

struct EnvironmentSwitcherView: View {
    @State private var selectedEnv = "Development"
    let environments = ["Development", "Staging", "Production", "Testing"]

    var body: some View {
        List {
            Section {
                ForEach(environments, id: \.self) { env in
                    Button {
                        selectedEnv = env
                    } label: {
                        HStack {
                            Text(env)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedEnv == env {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            } header: {
                Text("App Environment")
            } footer: {
                Text("Switching environment will restart the networking session.")
            }
        }
        .liquidGlass(style: .subtle, cornerRadius: 12)
        .navigationTitle("Env Switcher")
    }
}
