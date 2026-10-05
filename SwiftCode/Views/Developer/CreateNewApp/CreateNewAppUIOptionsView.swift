import SwiftUI

public struct CreateNewAppUIOptionsView: View {
    @Binding public var config: CreateAppConfiguration

    public init(config: Binding<CreateAppConfiguration>) {
        self._config = config
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("3. Visual & UI Preferences")
                .font(.title2.bold())

            Form {
                Section("Visual Style & Navigation") {
                    Picker("Visual Style:", selection: $config.visualStyle) {
                        ForEach(CreateAppStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }

                    Picker("Navigation Pattern:", selection: $config.navigation) {
                        ForEach(CreateAppNavigation.allCases) { nav in
                            Text(nav.rawValue).tag(nav)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Layout Density: \(densityLabel)")
                            .font(.subheadline)
                        Slider(value: $config.density, in: 0.0...1.0, step: 0.25)
                    }
                }

                Section("Data & Capabilities") {
                    Picker("Persistence Engine:", selection: $config.persistence) {
                        ForEach(CreateAppPersistence.allCases) { persistence in
                            Text(persistence.rawValue).tag(persistence)
                        }
                    }

                    Toggle("Enable Interface Animations", isOn: $config.useAnimations)
                    Toggle("Prioritize Accessibility (A11y)", isOn: $config.prioritizeAccessibility)
                }
            }
            .formStyle(.grouped)

            Spacer()
        }
    }

    private var densityLabel: String {
        if config.density <= 0.25 { return "Compact" }
        if config.density <= 0.75 { return "Balanced" }
        return "Spacious"
    }
}
