import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SkillsLibraryEntry: Identifiable, Equatable, Hashable {
    var id: URL { fileURL }
    var name: String
    var description: String
    var sourceKind: String
    var fileURL: URL
    var directoryURL: URL
}

struct AgentSkillsLibraryView: View {
    var workspaceRoot: URL?

    @Environment(\.colorScheme) private var scheme
    @State private var entries: [SkillsLibraryEntry] = []
    @State private var searchText = ""
    @State private var selected: SkillsLibraryEntry?
    @State private var draftContent = ""
    @State private var showingCreate = false
    @State private var newSkillName = ""
    @State private var newSkillDescription = ""
    @State private var showingImport = false
    @State private var showingDeleteConfirm = false
    @State private var errorMessage: String?

    private var filtered: [SkillsLibraryEntry] {
        guard !searchText.isEmpty else { return entries }
        let needle = searchText.lowercased()
        return entries.filter {
            $0.name.lowercased().contains(needle)
                || $0.description.lowercased().contains(needle)
        }
    }

    var body: some View {
        let c = ShellColors(scheme)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Search skills", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(ShellFonts.row)
                Button("Import") { showingImport = true }
                    .help("Import a SKILL.md file into the workspace skills library")
                Button("Create") { showingCreate = true }
                    .help("Create a new skill")
            }
            .padding(10)
            if let error = errorMessage {
                Text(verbatim: error)
                    .font(ShellFonts.small)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
            Hairline(color: c.separator)
            if entries.isEmpty {
                ContentUnavailableView(
                    "No skills",
                    systemImage: "square.stack.3d.up",
                    description: Text("Skills live as SKILL.md files under .claude/skills/ or .agents/skills/ in the workspace. Create one to get started.")
                )
            } else {
                List(selection: $selected) {
                    ForEach(filtered) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: entry.name).font(ShellFonts.rowBold)
                            Text(verbatim: entry.description)
                                .font(ShellFonts.small)
                                .foregroundStyle(c.secondaryLabel)
                                .lineLimit(2)
                            Text(verbatim: "\(entry.sourceKind) · \(entry.directoryURL.lastPathComponent)")
                                .font(ShellFonts.mini)
                                .foregroundStyle(c.tertiaryLabel)
                        }
                        .tag(entry)
                        .contextMenu {
                            Button("Duplicate Skill") {
                                duplicateSkill(entry)
                            }
                            Button("Delete Skill", role: .destructive) {
                                selected = entry
                                showingDeleteConfirm = true
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            if let entry = selected {
                Hairline(color: c.separator)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(verbatim: entry.name).font(ShellFonts.rowBold)
                        Spacer()
                        Text(verbatim: entry.fileURL.path)
                            .font(ShellFonts.mini)
                            .foregroundStyle(c.tertiaryLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    TextEditor(text: $draftContent)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 180)
                        .border(c.fieldStroke)
                    HStack {
                        Button("Save") { saveSelected() }
                            .buttonStyle(.borderedProminent)
                            .disabled(draftContent.isEmpty)
                        Button("Delete", role: .destructive) { showingDeleteConfirm = true }
                        Spacer()
                        Text(verbatim: "Saved to \(entry.fileURL.lastPathComponent)")
                            .font(ShellFonts.mini)
                            .foregroundStyle(c.tertiaryLabel)
                    }
                }
                .padding(10)
            }
        }
        .onAppear { reload() }
        .onChange(of: selected) { _, entry in
            guard let entry else { return }
            draftContent = (try? String(contentsOf: entry.fileURL, encoding: .utf8)) ?? ""
        }
        .sheet(isPresented: $showingCreate) {
            createSkillSheet(colors: c)
        }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.plainText]) { result in
            importSkill(result)
        }
        .alert("Delete skill?", isPresented: $showingDeleteConfirm, presenting: selected) { entry in
            Button("Delete", role: .destructive) { deleteSkill(entry) }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text("Delete \(entry.name) and its SKILL.md file? This cannot be undone.")
        }
    }

    @ViewBuilder
    private func createSkillSheet(colors c: ShellColors) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Create Skill").font(ShellFonts.rowBold)
            TextField("Skill name (lowercase, hyphens)", text: $newSkillName)
                .textFieldStyle(.roundedBorder)
            TextField("One-line description", text: $newSkillDescription)
                .textFieldStyle(.roundedBorder)
            Text("Creates <name>/SKILL.md under .claude/skills/ in the workspace, or under ~/.config/swiftcode/skills/ when no workspace is open.")
                .font(ShellFonts.small)
                .foregroundStyle(c.secondaryLabel)
            HStack {
                Spacer()
                Button("Cancel") { showingCreate = false }
                Button("Create") {
                    createSkill()
                    showingCreate = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(sanitizedSkillName(newSkillName).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private var skillRoots: [(URL, String)] {
        var roots: [(URL, String)] = []
        if let workspaceRoot {
            roots.append((workspaceRoot.appendingPathComponent(".claude/skills"), "Claude"))
            roots.append((workspaceRoot.appendingPathComponent(".agents/skills"), "Project"))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        roots.append((home.appendingPathComponent(".config/swiftcode/skills"), "SwiftCode"))
        return roots
    }

    private func reload() {
        var found: [SkillsLibraryEntry] = []
        let fm = FileManager.default
        for (root, kind) in skillRoots {
            guard let children = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            else { continue }
            for dir in children where dir.hasDirectoryPath {
                let file = dir.appendingPathComponent("SKILL.md")
                guard fm.fileExists(atPath: file.path),
                      let content = try? String(contentsOf: file, encoding: .utf8)
                else { continue }
                let (name, description) = SkillsLibraryEntry.parse(content, fallbackName: dir.lastPathComponent)
                found.append(SkillsLibraryEntry(
                    name: name, description: description, sourceKind: kind,
                    fileURL: file, directoryURL: dir))
            }
        }
        found.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        entries = found
        if let selected, !found.contains(selected) {
            self.selected = nil
        }
    }

    private func sanitizedSkillName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private func createSkill() {
        let name = sanitizedSkillName(newSkillName)
        guard !name.isEmpty else { return }
        let base: URL
        if let workspaceRoot {
            base = workspaceRoot.appendingPathComponent(".claude/skills")
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/swiftcode/skills")
        }
        let dir = base.appendingPathComponent(name)
        let description = newSkillDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = """
            ---
            name: \(name)
            description: \(description.isEmpty ? "No description provided." : description)
            ---

            # \(name)

            \(description.isEmpty ? "Describe what this skill does, when to use it, and how." : description)

            ## Instructions

            <!-- Write the skill's instructions here. -->
            """
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try content.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            newSkillName = ""
            newSkillDescription = ""
            errorMessage = nil
            reload()
        } catch {
            errorMessage = "Could not create skill: \(error.localizedDescription)"
        }
    }

    private func saveSelected() {
        guard let entry = selected else { return }
        do {
            try draftContent.write(to: entry.fileURL, atomically: true, encoding: .utf8)
            errorMessage = nil
            reload()
        } catch {
            errorMessage = "Could not save skill: \(error.localizedDescription)"
        }
    }

    private func duplicateSkill(_ entry: SkillsLibraryEntry) {
        let fm = FileManager.default
        let baseName = sanitizedSkillName(entry.name)
        guard !baseName.isEmpty else {
            errorMessage = "Could not duplicate skill: bad name."
            return
        }
        let parent = entry.directoryURL.deletingLastPathComponent()
        var candidate = baseName + "-copy"
        var n = 2
        while fm.fileExists(atPath: parent.appendingPathComponent(candidate).path) {
            candidate = baseName + "-copy-\(n)"
            n += 1
        }
        let dir = parent.appendingPathComponent(candidate)
        do {
            let content = try String(contentsOf: entry.fileURL, encoding: .utf8)
            let rewritten = rewriteSkillName(content, from: entry.name, to: candidate)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try rewritten.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            errorMessage = nil
            reload()
            selected = entries.first { $0.directoryURL == dir }
        } catch {
            errorMessage = "Could not duplicate skill: \(error.localizedDescription)"
        }
    }

    private func rewriteSkillName(_ content: String, from oldName: String, to newName: String) -> String {
        var lines = content.components(separatedBy: .newlines)
        var inFrontMatter = false
        var sawFrontMatterEnd = false
        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                if inFrontMatter { sawFrontMatterEnd = true; inFrontMatter = false; continue }
                inFrontMatter = true
                continue
            }
            if inFrontMatter && trimmed.hasPrefix("name:") {
                lines[i] = "name: \(newName)"
            }
        }
        if !sawFrontMatterEnd {
        }
        if let idx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "# \(oldName)" }) {
            lines[idx] = "# \(newName)"
        }
        return lines.joined(separator: "\n")
    }

    private func deleteSkill(_ entry: SkillsLibraryEntry) {
        do {
            try FileManager.default.removeItem(at: entry.directoryURL)
            selected = nil
            errorMessage = nil
            reload()
        } catch {
            errorMessage = "Could not delete skill: \(error.localizedDescription)"
        }
    }

    private func importSkill(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        let base: URL
        if let workspaceRoot {
            base = workspaceRoot.appendingPathComponent(".claude/skills")
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/swiftcode/skills")
        }
        let name = sanitizedSkillName(url.deletingPathExtension().lastPathComponent)
        guard !name.isEmpty else { return }
        let dir = base.appendingPathComponent(name)
        do {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: dir.appendingPathComponent("SKILL.md"))
            errorMessage = nil
            reload()
        } catch {
            errorMessage = "Could not import skill: \(error.localizedDescription)"
        }
    }
}

extension SkillsLibraryEntry {
    static func parse(_ content: String, fallbackName: String) -> (String, String) {
        var name = fallbackName
        var description = "No description provided."
        let lines = content.components(separatedBy: .newlines)
        var inFrontMatter = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                if inFrontMatter { break }
                inFrontMatter = true
                continue
            }
            guard inFrontMatter else { continue }
            if trimmed.hasPrefix("name:") {
                name = trimmed.dropFirst("name:".count).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("description:") {
                description = trimmed.dropFirst("description:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        return (name, description)
    }
}
