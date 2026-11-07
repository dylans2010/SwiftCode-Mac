import Foundation
import SwiftParser
import SwiftSyntax

enum SwiftASTInspection {
    struct Declaration: Equatable, Sendable {
        var kind: String
        var name: String
        var qualifiedName: String
        var line: Int
        var inheritance: [String]
        var detail: String
        var members: [Declaration]
    }

    struct Inspection: Sendable {
        var declarations: [Declaration]
        var imports: [String]
        var hasError: Bool

        var allDeclarations: [Declaration] {
            var out: [Declaration] = []
            func walk(_ decls: [Declaration]) {
                for d in decls { out.append(d); walk(d.members) }
            }
            walk(declarations)
            return out
        }

        func kind(of name: String) -> String? {
            allDeclarations.first { $0.name == name }?.kind
        }
    }

    static func inspect(source: String, file: String = "", symbolFilter: String? = nil) -> Inspection {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: file, tree: tree)
        let visitor = Visitor(converter: converter)
        visitor.walk(tree)
        var declarations = visitor.roots.map { $0.declaration }
        if let filter = symbolFilter, !filter.isEmpty {
            declarations = declarations.compactMap { filterDeclaration($0, filter: filter) }
        }
        return Inspection(declarations: declarations, imports: visitor.imports, hasError: tree.hasError)
    }

    private static func filterDeclaration(_ decl: Declaration, filter: String) -> Declaration? {
        let members = decl.members.compactMap { filterDeclaration($0, filter: filter) }
        if decl.name.localizedCaseInsensitiveContains(filter) || !members.isEmpty {
            var kept = decl
            kept.members = members
            return kept
        }
        return nil
    }

    private final class Builder {
        var kind: String
        var name: String
        var qualifiedName: String
        var line: Int
        var inheritance: [String]
        var detail: String
        var children: [Builder] = []

        init(kind: String, name: String, qualifiedName: String, line: Int, inheritance: [String] = [], detail: String = "") {
            self.kind = kind; self.name = name; self.qualifiedName = qualifiedName
            self.line = line; self.inheritance = inheritance; self.detail = detail
        }

        var declaration: Declaration {
            Declaration(kind: kind, name: name, qualifiedName: qualifiedName, line: line,
                        inheritance: inheritance, detail: detail, members: children.map(\.declaration))
        }
    }

    private final class Visitor: SyntaxVisitor {
        let converter: SourceLocationConverter
        var roots: [Builder] = []
        var imports: [String] = []
        private var stack: [Builder] = []

        init(converter: SourceLocationConverter) {
            self.converter = converter
            super.init(viewMode: .sourceAccurate)
        }

        private func line(of node: some SyntaxProtocol) -> Int {
            converter.location(for: node.positionAfterSkippingLeadingTrivia).line
        }

        private func qualified(_ name: String) -> String {
            (stack.map(\.name) + [name]).joined(separator: ".")
        }

        private func push(_ builder: Builder) {
            if let parent = stack.last { parent.children.append(builder) } else { roots.append(builder) }
            stack.append(builder)
        }

        private func addLeaf(_ builder: Builder) {
            if let parent = stack.last { parent.children.append(builder) } else { roots.append(builder) }
        }

        private func inheritance(of clause: InheritanceClauseSyntax?) -> [String] {
            clause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            push(Builder(kind: "class", name: node.name.text, qualifiedName: qualified(node.name.text),
                         line: line(of: node), inheritance: inheritance(of: node.inheritanceClause)))
            return .visitChildren
        }
        override func visitPost(_ node: ClassDeclSyntax) { stack.removeLast() }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            push(Builder(kind: "struct", name: node.name.text, qualifiedName: qualified(node.name.text),
                         line: line(of: node), inheritance: inheritance(of: node.inheritanceClause)))
            return .visitChildren
        }
        override func visitPost(_ node: StructDeclSyntax) { stack.removeLast() }

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            push(Builder(kind: "enum", name: node.name.text, qualifiedName: qualified(node.name.text),
                         line: line(of: node), inheritance: inheritance(of: node.inheritanceClause)))
            return .visitChildren
        }
        override func visitPost(_ node: EnumDeclSyntax) { stack.removeLast() }

        override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
            push(Builder(kind: "protocol", name: node.name.text, qualifiedName: qualified(node.name.text),
                         line: line(of: node), inheritance: inheritance(of: node.inheritanceClause)))
            return .visitChildren
        }
        override func visitPost(_ node: ProtocolDeclSyntax) { stack.removeLast() }

        override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
            push(Builder(kind: "actor", name: node.name.text, qualifiedName: qualified(node.name.text),
                         line: line(of: node), inheritance: inheritance(of: node.inheritanceClause)))
            return .visitChildren
        }
        override func visitPost(_ node: ActorDeclSyntax) { stack.removeLast() }

        override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
            let name = node.extendedType.trimmedDescription
            push(Builder(kind: "extension", name: name, qualifiedName: qualified(name), line: line(of: node)))
            return .visitChildren
        }
        override func visitPost(_ node: ExtensionDeclSyntax) { stack.removeLast() }

        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            let params = node.signature.parameterClause.parameters.map { param -> String in
                let first = param.firstName.text
                let second = param.secondName.map { " \($0.text)" } ?? ""
                return "\(first)\(second): \(param.type.trimmedDescription)"
            }.joined(separator: ", ")
            let returns = node.signature.returnClause.map { " -> \($0.type.trimmedDescription)" } ?? ""
            let isStatic = node.modifiers.contains { $0.name.text == "static" || $0.name.text == "class" }
            addLeaf(Builder(kind: "func", name: node.name.text, qualifiedName: qualified(node.name.text),
                            line: line(of: node), detail: "\(isStatic ? "static " : "")(\(params))\(returns)"))
            return .skipChildren
        }

        override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
            let keyword = node.bindingSpecifier.text
            for binding in node.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                let type = binding.typeAnnotation.map { ": \($0.type.trimmedDescription)" } ?? ""
                addLeaf(Builder(kind: keyword, name: pattern.identifier.text,
                                qualifiedName: qualified(pattern.identifier.text),
                                line: line(of: node), detail: type))
            }
            return .skipChildren
        }

        override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
            for element in node.elements {
                let params = element.parameterClause.map { "(\($0.parameters.map(\.type.trimmedDescription).joined(separator: ", ")))" } ?? ""
                addLeaf(Builder(kind: "case", name: element.name.text, qualifiedName: qualified(element.name.text),
                                line: line(of: node), detail: params))
            }
            return .skipChildren
        }

        override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
            addLeaf(Builder(kind: "typealias", name: node.name.text, qualifiedName: qualified(node.name.text),
                            line: line(of: node), detail: "= \(node.initializer.value.trimmedDescription)"))
            return .skipChildren
        }

        override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
            imports.append(node.path.map(\.name.text).joined(separator: "."))
            return .skipChildren
        }
    }
}
