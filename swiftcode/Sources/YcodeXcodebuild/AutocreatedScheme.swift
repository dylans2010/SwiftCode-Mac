import Foundation
import YcodeProject
import YcodeWorkspace

enum AutocreatedScheme {
    static func reference(_ t: PBXObject, _ p: LoadedProject, _ container: String) -> SwiftCodeWorkspace.XMLNode {
        let name = t.string("name") ?? ""
        let product = t.string("productReference").flatMap { p.proj[$0]?.string("path") } ?? name
        return SwiftCodeWorkspace.XMLNode("BuildableReference", attributes: [
            ("BuildableIdentifier", "primary"), ("BlueprintIdentifier", t.id), ("BuildableName", product),
            ("BlueprintName", name), ("ReferencedContainer", "container:\(container)"),
        ])
    }

    static func buildable(_ t: PBXObject, _ p: LoadedProject, _ container: String) -> Scheme.BuildableReference {
        let name = t.string("name") ?? ""
        let product = t.string("productReference").flatMap { p.proj[$0]?.string("path") } ?? name
        return Scheme.BuildableReference(blueprintIdentifier: t.id, buildableName: product, blueprintName: name,
                                         referencedContainer: "container:\(container)")
    }

    static func make(for t: PBXObject, in p: LoadedProject, containerName: String) -> Scheme? {
        let type = t.string("productType") ?? ""
        let isTest = Container.isTestBundle(t)
        let runnable = type.hasSuffix(".application") || type.hasSuffix(".tool")
        let hosted = p.targets.filter { other in
            Container.isTestBundle(other)
                && p.proj.project?["attributes"]?.dictionary?["TargetAttributes"]?.dictionary?[other.id]?.dictionary?["TestTargetID"]?.string == t.id
        }
        var s = Scheme.autocreated(for: buildable(t, p, containerName), isTestBundle: isTest, isRunnable: runnable,
                                   hostedTests: hosted.map { buildable($0, p, containerName) }, autocreateTestPlan: true)
        s.name = t.string("name") ?? ""
        return s
    }

    static func collectsCoverage(_ s: Scheme) -> Bool {
        guard let test = s.document.child("TestAction") else { return false }
        if test["codeCoverageEnabled"] == "YES" { return true }
        return test["shouldAutocreateTestPlan"] == "YES" && !s.testables.isEmpty
    }
}
