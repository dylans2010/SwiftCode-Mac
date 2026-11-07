import AppKit
import SwiftCodeIDECore
import SwiftUI

@MainActor
public final class AppCommands: NSObject {
    public static let shared = AppCommands()

    public enum Links {
        public static let developerDocumentation = URL(string: "https://developer.apple.com/documentation/")!
        public static let humanInterfaceGuidelines = URL(string: "https://developer.apple.com/design/human-interface-guidelines/")!
        public static let swiftBook = URL(string: "https://docs.swift.org/swift-book/")!
        public static let moreDeveloperTools = URL(string: "https://developer.apple.com/download/all/")!
        public static func documentationSearch(_ q: String) -> URL? {
            var c = URLComponents(string: "https://developer.apple.com/search/")!
            c.queryItems = [URLQueryItem(name: "q", value: q)]
            return c.url
        }
    }

    public static var open: (URL) -> Void = { NSWorkspace.shared.open($0) }

    static let actions: Set<String> = [
        "showDeveloperDocumentation:", "showHumanInterfaceGuidelines:", "showSwiftBook:", "openMoreDeveloperTools:",
        "openDeveloperTool:", "showDownloads:", "compareFiles:", "showAboutWindow:", "showSwiftCodeHelp:", "showReleaseNotes:", "reportBug:",
    ]

    public static func handles(_ action: String) -> Bool { actions.contains(action) }

    @objc public func showDeveloperDocumentation(_ sender: Any?) { Self.open(Links.developerDocumentation) }
    @objc public func showHumanInterfaceGuidelines(_ sender: Any?) { Self.open(Links.humanInterfaceGuidelines) }
    @objc public func showSwiftBook(_ sender: Any?) { Self.open(Links.swiftBook) }
    @objc public func showAboutWindow(_ sender: Any?) { AboutWindowController.shared.showWindow(sender) }
    @objc public func showSwiftCodeHelp(_ sender: Any?) { Self.open(ProductIdentity.helpURL) }
    @objc public func showReleaseNotes(_ sender: Any?) { Self.open(ProductIdentity.releasesURL) }
    @objc public func reportBug(_ sender: Any?) { Self.open(ProductIdentity.bugReportURL()) }
    @objc public func openMoreDeveloperTools(_ sender: Any?) { Self.open(Links.moreDeveloperTools) }

    @objc public func openDeveloperTool(_ sender: Any?) {
        guard let url = (sender as? NSMenuItem)?.representedObject as? URL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc public func showDownloads(_ sender: Any?) { SettingsWindowController.shared.show(pane: "Components") }
}

extension AppDelegate {
    @objc public func closeTab(_ sender: Any?) { NSApp.keyWindow?.performClose(sender) }

    @objc public func showBehaviorsSettings(_ sender: Any?) { SettingsWindowController.shared.show(pane: "Behaviors") }
}

private struct EditorViewHelpCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Go to Line...") {
                NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "go_to_line"])
            }
            .keyboardShortcut("l", modifiers: [.command])
        }

        CommandMenu("Editor") {
            Button("Find...") {
                NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "code_search"])
            }
            .keyboardShortcut("f", modifiers: [.command])

            Button("Go to Line...") {
                NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "go_to_line"])
            }
            .keyboardShortcut("l", modifiers: [.command])

            Button("Format Code") {
                NotificationCenter.default.post(name: NSNotification.Name("FormatCode"), object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Divider()

            Button("Next Tab") {
                NotificationCenter.default.post(name: NSNotification.Name("NextTab"), object: nil)
            }
            .keyboardShortcut("}", modifiers: [.command, .shift])

            Button("Previous Tab") {
                NotificationCenter.default.post(name: NSNotification.Name("PreviousTab"), object: nil)
            }
            .keyboardShortcut("{", modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            Divider()

            Button("Customize Toolbar...") {
                SwiftCodeToolbarDelegate.presentCustomizationPalette()
            }

            Divider()

            Button("Coding Tools") {
                NotificationCenter.default.post(
                    name: Notification.Name("TriggerCodingToolsContextAction"),
                    object: nil,
                    userInfo: [
                        "action": CodingToolsUI.CodingAction.refactor,
                        "code": "",
                        "filePath": ""
                    ]
                )
            }
        }

        CommandGroup(replacing: .help) {
            Button("SwiftCode Documentation") {
                NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "documentation_browser"])
            }
            Button("Diagnostics") {
                NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "error_diagnostics"])
            }
        }
    }
}
