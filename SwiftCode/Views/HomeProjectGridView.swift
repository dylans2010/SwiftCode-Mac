import SwiftUI

struct HomeProjectGridView: View {
    let projects: [ProjectRegistryEntry]
    let onSelect: (ProjectRegistryEntry) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 20) {
                ForEach(projects) { project in
                    VStack {
                        Image(systemName: "folder")
                            .font(.system(size: 40))
                        Text(project.name)
                            .lineLimit(1)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .onTapGesture {
                        onSelect(project)
                    }
                }
            }
        }
    }
}
