import SwiftUI

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
        .navigationTitle("Env Switcher")
    }
}
