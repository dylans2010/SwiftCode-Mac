import Foundation
import SwiftParser
import SwiftSyntax

/// Real Swift AST inspection through swift-syntax (the same library
/// `SwiftCodeSyntax` is built on; `SwiftCodeSyntax` itself exposes no parse
/// tree — only `SyntaxDocument` tokens and classification — so the
/// engine parses with `SwiftParser` directly instead of duplicating
/// `SwiftCodeSyntax`'s lexer work).
///
/// This replaces the Wave 6 regex structural fallback in
/// `swift_ast_inspector` (Legacy's own fallback when `xcrun swiftc
/// -dump-ast` was unavailable; the port never shelled out to Apple's
/// toolchain). Declarations now come from the parse tree, with real
/// line numbers, nesting, inheritance clauses and function
/// signatures — not from `(class|struct|…)\s+(\w+)` matches, so a
/// type name inside a string or a comment is no longer reported as
/// a declaration.
///
/// Limits, stated plainly: this is syntactic, not semantic. There
/// is no type checker, so there is no resolved type of an
/// expression, no overload set, and no cross-file symbol index.
/// `hasError` reports only whether the file failed to parse.
enum SwiftASTInspection {
    /// One declaration found in the parse tree.
    struct Declaration: Equatable, Sendable {
        /// `class` / `struct` / `enum` / `protocol` / `actor` /
        /// `extension` / `func` / `var` / `let` / `typealias` /
        /// `case`.
        var kind: String
        var name: String
        /// Dot-joined enclosing type names, e.g. `Outer.Inner`.
        var qualifiedName: String
        /// 1-based line of the declaration.
        var line: Int
        /// Inherited / conformed types, as written.
        var inheritance: [String]
        /// Extra detail: a function's parameter list and return
        /// type, a variable's type annotation, else "".
        var detail: String
        /// Declarations nested inside this one.
        var members: [Declaration]
    }

    /// The inspection of one source file.
    struct Inspection: Sendable {
        /// Top-level declarations (types carry their members).
        var declarations: [Declaration]
        /// Imported module paths, in order (`Foundation`, `SwiftUI`).
        var imports: [String]
        /// Whether the file failed to parse (`tree.hasError`).
        var hasError: Bool

        /// Every declaration, flattened in source order.
        var allDeclarations: [Declaration] {
            var out: [Declaration] = []
            func walk(_ decls: [Declaration]) {
                for d in decls { out.append(d); walk(d.members) }
            }
            walk(declarations)
            return out
        }

        /// The kind of the first declaration named `name`, if any.
        func kind(of name: String) -> String? {
            allDeclarations.first { $0.name == name }?.kind
        }
    }

    /// Parses `source` and collects its declarations. `symbolFilter`
    /// keeps declarations whose name contains it (case-insensitive,
    /// Legacy's filter); a matching member keeps its ancestors,
    /// with only matching descendants.
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

    /// Keeps a declaration when it or any descendant matches the
    /// filter (case-insensitive substring on the name).
    private static func filterDeclaration(_ decl: Declaration, filter: String) -> Declaration? {
        let members = decl.members.compactMap { filterDeclaration($0, filter: filter) }
        if decl.name.localizedCaseInsensitiveContains(filter) || !members.isEmpty {
            var kept = decl
            kept.members = members
            return kept
        }
        return nil
    }

    /// One mutable declaration under construction; the visitor
    /// holds a stack of these so members land on their enclosing
    /// type.
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
            // Bodies may contain local declarations; they are not
            // members of the function, so do not descend.
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
