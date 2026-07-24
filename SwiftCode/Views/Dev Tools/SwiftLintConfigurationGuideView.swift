import SwiftUI

struct LintRuleItem: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let exampleBad: String
    let exampleGood: String
    var isEnabled: Bool = true
}

public struct SwiftLintConfigurationGuideView: View {
    @State private var rules = [
        LintRuleItem(name: "force_cast", description: "Avoid force casts; they can trigger runtime application crashes.", exampleBad: "let x = y as! String", exampleGood: "guard let x = y as? String else { return }"),
        LintRuleItem(name: "force_unwrapping", description: "Avoid force unwraps; prefer optional binding chains.", exampleBad: "let user = auth.currentUser!", exampleGood: "guard let user = auth.currentUser else { return }"),
        LintRuleItem(name: "line_length", description: "Lines should not span excessively long character boundaries.", exampleBad: "let str = \"very...very...very...long...string...\"", exampleGood: "let str = \"split...\"\n+ \"string\""),
        LintRuleItem(name: "cyclomatic_complexity", description: "Limit nested branches to maintain code readability.", exampleBad: "func process() { if a { if b { if c {} } } }", exampleGood: "func process() { guard a, b, c else { return } }")
    ]

    public init() {}

    private var generatedYML: String {
        let disabled = rules.filter { !$0.isEnabled }.map { $0.name }
        let enabled = rules.filter { $0.isEnabled }.map { $0.name }

        var output = "disabled_rules:\n"
        for r in disabled { output += "  - \(r)\n" }

        output += "\nopt_in_rules:\n"
        for r in enabled { output += "  - \(r)\n" }

        return output
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SwiftLint Configuration Playbook")
                        .font(.title.bold())
                    Text("Design custom SwiftLint rulesets and generate clean validation .swiftlint.yml files.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack(alignment: .top, spacing: 20) {
                    // Controls
                    VStack(spacing: 16) {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Select SwiftLint Rules")
                                    .font(.headline)

                                ForEach(rules.indices, id: \.self) { idx in
                                    Toggle(rules[idx].name, isOn: $rules[idx].isEnabled)
                                        .toggleStyle(.checkbox)
                                }
                            }
                            .padding(8)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Generated SwiftLint YML")
                                        .font(.headline)
                                    Spacer()
                                    Button("Copy") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(generatedYML, forType: .string)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }

                                Text(generatedYML)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.15))
                                    .cornerRadius(6)
                            }
                            .padding(8)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                    .frame(width: 300)

                    // Code examples preview
                    VStack(spacing: 16) {
                        ForEach(rules) { item in
                            GroupBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(item.name)
                                        .font(.headline)
                                        .foregroundColor(.orange)

                                    Text(item.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading) {
                                            Text("🛑 Bad Practice").font(.caption.bold()).foregroundColor(.red)
                                            Text(item.exampleBad)
                                                .font(.system(.caption, design: .monospaced))
                                                .padding(6)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(Color.red.opacity(0.08))
                                                .cornerRadius(4)
                                        }

                                        VStack(alignment: .leading) {
                                            Text("🟢 Recommended").font(.caption.bold()).foregroundColor(.green)
                                            Text(item.exampleGood)
                                                .font(.system(.caption, design: .monospaced))
                                                .padding(6)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(Color.green.opacity(0.08))
                                                .cornerRadius(4)
                                        }
                                    }
                                }
                                .padding(6)
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
