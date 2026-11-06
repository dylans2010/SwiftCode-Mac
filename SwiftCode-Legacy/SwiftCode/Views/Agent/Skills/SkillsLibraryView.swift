import SwiftUI

public struct SkillsLibraryView: View {
    @State private var skills: [Skill] = []

    public init() {}

    public var body: some View {
        List(skills) { skill in
            VStack(alignment: .leading) {
                Text(skill.name).font(.headline)
                Text(skill.description).font(.subheadline).foregroundColor(.secondary)
            }
            .padding(8)
            .liquidGlass(style: .subtle, cornerRadius: 8)
        }
        .onAppear {
            Task {
                skills = await SkillsRuntime.shared.getAllSkills()
            }
        }
        .navigationTitle("Skills Library")
    }
}
