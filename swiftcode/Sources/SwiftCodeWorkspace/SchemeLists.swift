import Foundation

extension Scheme {
    static let buildForOrder: [Action] = [.testing, .running, .profiling, .archiving, .analyzing]

    public mutating func addBuildEntry(_ ref: BuildableReference, actions: Set<Action>) {
        guard !buildEntries.contains(where: { $0.reference.blueprintIdentifier == ref.blueprintIdentifier }) else { return }
        editAction("BuildAction") { b in
            if b["parallelizeBuildables"] == nil, b.children.isEmpty { b["parallelizeBuildables"] = "YES"; b["buildImplicitDependencies"] = "YES" }
            let entry = XMLNode("BuildActionEntry", attributes: Self.buildForOrder.map { ("buildFor\($0.rawValue)", actions.contains($0) ? "YES" : "NO") },
                                children: [ref.node])
            if let i = b.children.firstIndex(where: { $0.name == "BuildActionEntries" }) {
                b.children[i].children.append(entry)
            } else {
                b.children.insert(XMLNode("BuildActionEntries", children: [entry]), at: 0)
            }
        }
    }

    public mutating func removeBuildEntry(blueprintIdentifier: String) {
        editAction("BuildAction") { b in
            guard let i = b.children.firstIndex(where: { $0.name == "BuildActionEntries" }) else { return }
            b.children[i].children.removeAll { $0.name == "BuildActionEntry" && $0.child("BuildableReference")?["BlueprintIdentifier"] == blueprintIdentifier }
            if b.children[i].children.isEmpty { b.children.remove(at: i) }
        }
    }

    public mutating func addTestPlan(reference: String) {
        guard !testPlans.contains(where: { $0.reference == reference }) else { return }
        let first = testPlans.isEmpty
        editAction("TestAction") { t in
            var attrs = [("reference", reference)]
            if first { attrs.append(("default", "YES")) }
            let node = XMLNode("TestPlanReference", attributes: attrs)
            if let i = t.children.firstIndex(where: { $0.name == "TestPlans" }) {
                t.children[i].children.append(node)
            } else {
                let at = t.children.firstIndex { $0.name == "Testables" }.map { $0 + 1 } ?? 0
                t.children.insert(XMLNode("TestPlans", children: [node]), at: at)
            }
        }
    }

    public mutating func removeTestPlan(reference: String) {
        editAction("TestAction") { t in
            guard let i = t.children.firstIndex(where: { $0.name == "TestPlans" }) else { return }
            let wasDefault = t.children[i].children.contains { $0["reference"] == reference && $0["default"] == "YES" }
            t.children[i].children.removeAll { $0.name == "TestPlanReference" && $0["reference"] == reference }
            if t.children[i].children.isEmpty { t.children.remove(at: i); return }
            if wasDefault, let j = t.children[i].children.firstIndex(where: { $0.name == "TestPlanReference" }) {
                t.children[i].children[j]["default"] = "YES"
            }
        }
    }

    public mutating func setDefaultTestPlan(reference: String) {
        editAction("TestAction") { t in
            guard let i = t.children.firstIndex(where: { $0.name == "TestPlans" }) else { return }
            for j in t.children[i].children.indices where t.children[i].children[j].name == "TestPlanReference" {
                t.children[i].children[j]["default"] = t.children[i].children[j]["reference"] == reference ? "YES" : nil
            }
        }
    }
}
