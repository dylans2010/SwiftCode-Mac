import Foundation
import YcodeIDECore

extension WorkspaceShellModel {
    public var hidesFileExtensions: Bool { Preferences.shared.fileExtensions == .hide }

    public var projectRows: [OutlineRow] {
        OutlineRows.project(root, expanded: expanded, hideExtensions: hidesFileExtensions, edited: editedPaths, badges: sourceControl.badges)
    }

    public var jumpPath: [(title: String, symbol: String)] {
        guard let d = document else { return [] }
        return WorkspaceChrome.jumpPath(for: URL(fileURLWithPath: d.path), root: session.model.root, workspaceName: workspaceName,
                                        hideExtension: hidesFileExtensions).map { (title: $0.0, symbol: $0.1) }
    }

    public var fileInspector: [InspectorSection] {
        guard let d = document else { return [] }
        let url = URL(fileURLWithPath: d.path)
        let p = Preferences.shared
        return [
            InspectorSection(title: "Identity and Type", rows: [
                InspectorRow(key: "Name", value: .field(url.lastPathComponent)),
                InspectorRow(key: "Type", value: .popUp("Default - " + WorkspaceChrome.fileTypeName(for: url))),
                InspectorRow(key: "Location", value: .popUp(containerKind == .package ? "Relative to Group" : "Relative to Group", button: "folder")),
                InspectorRow(key: "", value: .label(url.lastPathComponent, bold: true)),
                InspectorRow(key: "Full Path", value: .path(url.path, button: "arrow.right.circle.fill")),
            ]),
            InspectorSection(title: "Text Settings", rows: [
                InspectorRow(key: "Text Encoding", value: .popUp(WorkspaceChrome.textEncodingItems[0])),
                InspectorRow(key: "Line Endings", value: .popUp(WorkspaceChrome.lineEndingItems[0])),
                InspectorRow(key: "Indent Using", value: .popUp(p.indentWithTabs ? "Tabs" : "Spaces")),
                InspectorRow(key: "Widths", value: .steppers([("Tab", p.tabWidth), ("Indent", p.indentWidth)])),
            ]),
        ]
    }
}

public struct InspectorSection: Equatable, Sendable {
    public var title: String
    public var rows: [InspectorRow]
}

public struct InspectorRow: Equatable, Sendable {
    public enum Value: Equatable, Sendable {
        case field(String)
        case popUp(String, button: String? = nil)
        case label(String, bold: Bool)
        case path(String, button: String)
        case steppers([Stepper])

        public static func == (a: Value, b: Value) -> Bool { String(describing: a) == String(describing: b) }
    }

    public typealias Stepper = (title: String, value: Int)
    public var key: String
    public var value: Value
}
