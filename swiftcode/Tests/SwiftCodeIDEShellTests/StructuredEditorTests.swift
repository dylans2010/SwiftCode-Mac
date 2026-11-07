import Foundation
import Testing
@testable import SwiftCodeIDECore
@testable import SwiftCodeIDEShell
import SwiftCodePlist

@MainActor
@Suite struct StructuredEditorTests {
    func temp() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-editors-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func foundationXML(_ obj: Any) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: obj, format: .xml, options: 0)
    }

    @Test func plistOpenedAndLeftIsNeverWritten() throws {
        let d = try temp()
        let u = d.appendingPathComponent("Info.plist")
        let text = "<?xml version=\"1.0\"?>\n<plist version=\"1.0\">\n  <dict>\n    <key>A</key>\n    <string>x</string>\n  </dict>\n</plist>\n"
        try text.write(to: u, atomically: true, encoding: .utf8)
        let m = try PlistEditorModel(path: u.path)
        _ = m.rows
        m.selection = [0]
        m.sort(by: .value)
        m.showsRawKeys = true
        #expect(try String(contentsOf: u, encoding: .utf8) == text)
        #expect(m.saveCount == 0)
    }

    @Test func plistEditsSaveInXMLAndReopen() throws {
        let d = try temp()
        let u = d.appendingPathComponent("Info.plist")
        let original = try foundationXML(["CFBundleName": "Demo", "CFBundleVersion": 1, "Tags": ["a"]] as [String: Any])
        try original.write(to: u)
        let m = try PlistEditorModel(path: u.path)
        let name = try #require(m.rows.first { $0.rawKey == "CFBundleName" })
        #expect(name.key == "Bundle name")
        #expect(m.setValueText("Renamed", at: name.path))
        let version = try #require(m.rows.first { $0.rawKey == "CFBundleVersion" })
        #expect(!m.setValueText("one", at: version.path))
        #expect(m.problem != nil)
        m.selection = version.path
        let added = m.addItem()
        #expect(m.setType("Boolean", at: added))
        #expect(m.setKey("Bundle display name", at: added))
        #expect(!m.setKey("CFBundleName", at: added))
        let reopened = try PlistEditorModel(path: u.path)
        #expect(reopened.document.format == .xml)
        guard case .dictionary(let entries) = reopened.tree.root else { Issue.record("not a dictionary"); return }
        #expect(entries.map(\.key).contains("CFBundleDisplayName"))
        #expect(entries.first { $0.key == "CFBundleName" }?.value == .string("Renamed"))
        #expect(entries.first { $0.key == "CFBundleDisplayName" }?.value == .bool(false))
        let back = try PropertyListSerialization.propertyList(from: Data(contentsOf: u), format: nil) as? [String: Any]
        #expect(back?["CFBundleName"] as? String == "Renamed")
    }

    @Test func plistEditThenUndoByHandIsByteIdentical() throws {
        let d = try temp()
        let u = d.appendingPathComponent("Info.plist")
        let original = try foundationXML(["A": "x", "B": ["c": 2]] as [String: Any])
        try original.write(to: u)
        let m = try PlistEditorModel(path: u.path)
        let a = try #require(m.rows.first { $0.rawKey == "A" })
        m.setValueText("y", at: a.path)
        m.setValueText("x", at: a.path)
        #expect(try Data(contentsOf: u) == original)
    }

    @Test func plistBinaryStaysBinary() throws {
        let d = try temp()
        let u = d.appendingPathComponent("B.plist")
        let original = try PropertyListSerialization.data(fromPropertyList: ["Name": "B", "N": 3] as [String: Any], format: .binary, options: 0)
        try original.write(to: u)
        let m = try PlistEditorModel(path: u.path)
        #expect(m.document.format == .binary)
        m.selection = []
        m.addItem()
        let data = try Data(contentsOf: u)
        #expect(data.starts(with: Array("bplist00".utf8)))
        let back = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        #expect(back?["New item"] as? String == "")
        #expect(back?["N"] as? Int == 3)
    }

    @Test func plistOpenStepStaysOpenStep() throws {
        let d = try temp()
        let u = d.appendingPathComponent("Legacy.plist")
        let text = "{\n\tName = Legacy;\n\tItems = (\n\t\tone,\n\t\ttwo,\n\t);\n}\n"
        try text.write(to: u, atomically: true, encoding: .utf8)
        let m = try PlistEditorModel(path: u.path)
        #expect(m.document.format == .openStep)
        #expect(m.rows.map(\.key) == ["Root", "Name", "Items", "Item 0", "Item 1"])
        let name = try #require(m.rows.first { $0.rawKey == "Name" })
        m.setValueText("Changed", at: name.path)
        let written = try String(contentsOf: u, encoding: .utf8)
        #expect(written == "{\n\tName = Changed;\n\tItems = (\n\t\tone,\n\t\ttwo,\n\t);\n}\n")
        #expect(try PlistEditorModel(path: u.path).document.format == .openStep)
    }

    @Test func plistItemsMoveAndRemove() throws {
        let d = try temp()
        let u = d.appendingPathComponent("L.plist")
        try foundationXML(["Order": ["a", "b", "c"]] as [String: Any]).write(to: u)
        let m = try PlistEditorModel(path: u.path)
        m.selection = [0, 2]
        #expect(m.moveSelected(by: -1))
        #expect(m.selection == [0, 1])
        #expect(m.tree.item(at: [0]) == .array([.string("a"), .string("c"), .string("b")]))
        #expect(m.removeSelected())
        #expect(m.tree.item(at: [0]) == .array([.string("a"), .string("b")]))
        m.selection = []
        #expect(!m.removeSelected())
    }

    @Test func plistSortIsTheViewsNotTheFiles() throws {
        let d = try temp()
        let u = d.appendingPathComponent("S.plist")
        let original = try foundationXML(["b": "2", "a": "1", "c": "0"] as [String: Any])
        try original.write(to: u)
        let m = try PlistEditorModel(path: u.path)
        m.showsRawKeys = true
        let fileOrder = m.rows.dropFirst().map(\.key)
        m.sort(by: .key)
        #expect(m.rows.dropFirst().map(\.key) == ["a", "b", "c"])
        m.sort(by: .key)
        #expect(m.rows.dropFirst().map(\.key) == ["c", "b", "a"])
        m.sort(by: .key)
        #expect(m.rows.dropFirst().map(\.key) == fileOrder)
        #expect(try Data(contentsOf: u) == original)
    }

    func catalog(in d: URL) throws -> URL {
        let cat = d.appendingPathComponent("Assets.xcassets")
        let ac = AssetCatalog(url: cat)
        try FileManager.default.createDirectory(at: cat, withIntermediateDirectories: true)
        try AssetCatalog.json(["info": ["author": "xcode", "version": 1]]).write(to: cat.appendingPathComponent("Contents.json"))
        try ac.addColorSet(named: "AccentColor")
        try ac.addImageSet(named: "Logo")
        return cat
    }

    @Test func assetCatalogAddsEditsAndTrashesSets() throws {
        let d = try temp()
        let cat = try catalog(in: d)
        let trash = d.appendingPathComponent("Trash")
        let m = AssetCatalogEditorModel(path: cat.path, bin: .folder(trash))
        #expect(m.rows.map(\.name) == ["AccentColor", "Logo"])
        #expect(m.selectedSet?.name == "AccentColor")
        let blue = try #require(AssetCatalogEditorModel.color(m.colors[0], hex: "#3478F6"))
        #expect(m.setColor(blue, at: 0))
        #expect(AssetCatalogEditorModel.hex(m.colors[0]) == "#3478F6")
        #expect(m.setAppearances("Any, Dark"))
        #expect(m.colors.count == 2)
        #expect(m.add(tag: AssetCatalog.AddMenuTags.creatable["Image Set"]!))
        #expect(m.selectedSet?.name == "Image")
        let png = d.appendingPathComponent("p.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: png)
        #expect(m.setImage(png, slot: 1))
        #expect(m.slots[1].filename == "p.png")
        let made = try #require(m.selectedSet?.url)
        #expect(m.removeSelected())
        #expect(!FileManager.default.fileExists(atPath: made.path))
        let trashed = try #require(m.lastRemoval?.trashed)
        #expect(FileManager.default.fileExists(atPath: trashed.appendingPathComponent("p.png").path))
        #expect(m.undoRemove())
        #expect(FileManager.default.fileExists(atPath: made.appendingPathComponent("p.png").path))
        #expect(m.selectedSet?.name == "Image")
        let again = AssetCatalogEditorModel(path: cat.path, bin: .folder(trash))
        #expect(again.rows.map(\.name) == ["AccentColor", "Image", "Logo"])
        again.select(again.rows[0].id)
        #expect(again.colors.map(\.appearance) == [nil, "dark"])
    }

    @Test func assetCatalogFoldersRenameAndFilter() throws {
        let d = try temp()
        let cat = try catalog(in: d)
        let m = AssetCatalogEditorModel(path: cat.path, bin: .folder(d.appendingPathComponent("Trash")))
        #expect(m.add(tag: AssetCatalog.AddMenuTags.folder + 1))
        #expect(m.selectedFolder?.lastPathComponent == "Folder")
        #expect(m.providesNamespace)
        #expect(m.add(tag: AssetCatalog.AddMenuTags.creatable["Color Set"]!))
        #expect(m.selectedRow?.id == "Folder/Color.colorset")
        #expect(m.renameSelected("Brand"))
        #expect(m.selectedRow?.id == "Folder/Brand.colorset")
        #expect(!m.renameSelected("a/b"))
        m.setFilter("bra")
        #expect(m.rows.map(\.name) == ["Folder", "Brand"])
        m.setFilter("")
        m.select("Folder")
        #expect(m.removeSelected())
        #expect(m.rows.map(\.name) == ["AccentColor", "Logo"])
    }

    @Test func assetCatalogRemoveNeverDeletesOutright() throws {
        let d = try temp()
        let cat = try catalog(in: d)
        let ac = AssetCatalog(url: cat)
        let logo = try #require(ac.sets().first { $0.name == "Logo" })
        let trash = d.appendingPathComponent("Trash")
        let went = try ac.remove(logo, bin: .folder(trash))
        #expect(went.path.hasPrefix(trash.path))
        #expect(FileManager.default.fileExists(atPath: went.appendingPathComponent("Contents.json").path))
        #expect(throws: (any Error).self) { try ac.removeFolder(cat, bin: .folder(trash)) }
    }

    func strings(in d: URL) throws -> URL {
        let u = d.appendingPathComponent("Localizable.xcstrings")
        let text = """
        {
          "sourceLanguage" : "en",
          "strings" : {
            "Goodbye" : {
              "comment" : "Leaving",
              "localizations" : {
                "de" : {
                  "stringUnit" : {
                    "state" : "translated",
                    "value" : "Tschüss"
                  }
                }
              }
            },
            "Welcome" : {

            }
          },
          "version" : "1.0"
        }

        """
        try text.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    @Test func stringCatalogEditsSaveAndUntouchedStaysByteIdentical() throws {
        let d = try temp()
        let u = try strings(in: d)
        let original = try Data(contentsOf: u)
        let m = try StringCatalogEditorModel(path: u.path)
        #expect(m.languages == ["en", "de"])
        m.select(language: "de")
        m.sort(by: .state)
        m.setFilter("wel")
        #expect(m.rows.map(\.key) == ["Welcome"])
        m.setFilter("")
        #expect(try Data(contentsOf: u) == original)
        #expect(m.setTranslation("Willkommen", key: "Welcome"))
        #expect(m.rows.first { $0.key == "Welcome" }?.state == .translated)
        #expect(m.catalog.progress(language: "de") == 100)
        #expect(m.setTranslation("", key: "Welcome"))
        #expect(try Data(contentsOf: u) == original)
        #expect(m.setNeedsReview(true, key: "Goodbye"))
        #expect(m.setComment("Shown on exit", key: "Goodbye"))
        let k = m.addKey()
        #expect(k == "New Key")
        #expect(m.addKey() == "New Key 2")
        #expect(m.removeSelectedKey())
        let back = try StringCatalogEditorModel(path: u.path)
        back.select(language: "de")
        #expect(back.rows.first { $0.key == "Goodbye" }?.state == .needsReview)
        #expect(back.rows.first { $0.key == "Goodbye" }?.comment == "Shown on exit")
        #expect(back.catalog.keys.contains("New Key"))
        #expect(!back.catalog.keys.contains("New Key 2"))
    }

    @Test func stringCatalogAddsLanguagesAndRefreshesFromSource() throws {
        let d = try temp()
        let u = try strings(in: d)
        try "import Foundation\nlet a = String(localized: \"Welcome\")\nlet b = String(localized: \"Brand New\", comment: \"From code\")\n"
            .write(to: d.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let m = try StringCatalogEditorModel(path: u.path)
        var added: [String] = []
        m.onAddLanguage = { added.append($0) }
        m.addLanguage("fr")
        #expect(added == ["fr"])
        #expect(m.language == "fr")
        #expect(m.languages.contains("fr"))
        let summary = m.refreshFromSource()
        #expect(summary.added.contains("Brand New"))
        let back = try StringCatalogEditorModel(path: u.path)
        #expect(back.catalog.keys.contains("Brand New"))
        #expect(back.rows.first { $0.key == "Brand New" }?.comment == "From code")
        #expect(back.rows.first { $0.key == "Goodbye" }?.state == .stale)
    }

    @Test func workspaceOpensStructuredEditorsByTypeAndSwitchesToSource() throws {
        let pkg = try TempPackage()
        defer { pkg.remove() }
        let plist = pkg.path("Sources/Demo/Info.plist")
        try foundationXML(["A": "x"] as [String: Any]).write(to: URL(fileURLWithPath: plist))
        let cat = try catalog(in: URL(fileURLWithPath: pkg.path("Sources/Demo")))
        let w = try WorkspaceShellModel(url: pkg.url, engine: ScriptedEngine(lines: [], issues: []))
        w.open(plist)
        guard case .propertyList(let m)? = w.structuredEditor else { Issue.record("no plist editor"); return }
        #expect(w.editorKind == .propertyList)
        #expect(w.editor == nil)
        #expect(w.document?.path == plist)
        #expect(w.editorActionState("addPlistItem:")?.enabled == true)
        #expect(w.performEditorAction("addPlistItem:"))
        #expect(w.performEditorAction("toggleRawKeysAndValues:"))
        #expect(m.showsRawKeys)
        w.setShowsSourceView(true)
        #expect(w.structuredEditor == nil)
        #expect(w.isShowingSourceView)
        #expect(w.editor?.buffer.text.contains("<key>New item</key>") == true)
        let b = try #require(w.editor?.buffer)
        b.replace((b.text as NSString).range(of: "<string>x</string>"), with: "<string>typed</string>")
        w.setShowsSourceView(false)
        guard case .propertyList(let m2)? = w.structuredEditor else { Issue.record("no plist editor after source"); return }
        guard case .dictionary(let entries) = m2.tree.root else { Issue.record("not a dictionary"); return }
        #expect(entries.map(\.key) == ["New item", "A"])
        #expect(entries.last?.value == .string("typed"))
        w.open(cat.path)
        #expect(w.editorKind == .assetCatalog)
        #expect(w.editorActionState("deleteSelectedAssets:")?.enabled == true)
        w.closeCurrentDocument()
        #expect(w.structuredEditor == nil)
    }
}
