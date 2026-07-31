import SwiftUI

struct DatabasePermissionsView: View {
    @State private var useRowLevelSecurity = true
    @State private var restrictAnonymousAccess = true

    var body: some View {
        Form {
            Section("Access Controls & Policies") {
                Toggle("Enforce PostgreSQL Row Level Security (RLS)", isOn: $useRowLevelSecurity)
                Toggle("Restrict anonymous reading/writing", isOn: $restrictAnonymousAccess)
            }

            Section("Authenticated Roles") {
                List {
                    HStack {
                        Text("authenticated")
                        Spacer()
                        Text("READ / WRITE")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    HStack {
                        Text("anon")
                        Spacer()
                        Text("READ ONLY")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    HStack {
                        Text("service_role")
                        Spacer()
                        Text("BYPASS ALL")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .frame(height: 120)
            }
        }
        .formStyle(.grouped)
    }
}
