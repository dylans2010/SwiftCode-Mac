import Foundation
import Testing
import YcodeAssistant
@testable import YcodeMCP

/// The ported Legacy asset-catalog / localization tools (Wave 7,
/// slice E), each driven black-box through the server's real
/// write-policy path against a copy of `Samples/AgentSamples/Greeter`.
///
/// Behaviour source: Legacy `AssistAssetCatalogListTool`,
/// `AssistAssetCatalogTool`, `AssistAssetImageAddTool`,
/// `AssistLocalizationAuditTool`, `AssistLocalizationTool`,
/// `AssistLocalizeAppTool`, `AssistStringCatalogMigratorTool`,
/// `AssistStringsFileValidateTool` and `AssistStringsLocalizationTool`
/// (Dylan's own code, ported under MIT).
///
/// Assertions are on the tool RESULT (message + on-disk state), never
/// on internals. Messages quoted verbatim are Legacy's. Message
/// assertions use `firstText`, never an exact `resultText ==`
/// (structured results emit two text blocks).
///
/// Note: the Greeter sample ships its own
/// `Strings/Localizable.xcstrings` (keys "Hello" with a `de`
/// translation, and "world" with no localizations). Tests that need
/// a clean localization state delete it from the temp copy first;
/// tests that exercise the catalog use it as-is.
@MainActor
@Suite(.serialized) struct YcodeAssetsLocalizationTests {
    /// The 9 Wave 7 slice E tool IDs, verified live from each
    /// Legacy tool file's `id`.
    static let sliceEIDs = ["asset_catalog_list", "asset_catalog_manager", "asset_image_add",
                            "localization_audit", "localization_manager", "localize_app",
                            "string_catalog_migrator", "strings_file_validate", "strings_localization"]

    /// Opens a copy of Greeter and installs the ported slice E tools
    /// on the server (same shape as Wave 6's `opened`).
    func opened(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> YcodeMCPHost {
        let host = YcodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.assetsLocalizationTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.assetsLocalizationTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    /// Writes a fixture file directly (not through a tool under test).
    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func removeFixture(_ sample: TempSample, _ rel: String) {
        try? FileManager.default.removeItem(atPath: sample.path(rel))
    }

    func exists(_ sample: TempSample, _ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: sample.path(rel))
    }

    @Test func toolIDsAreRegisteredOnce() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        #expect(host.assetsLocalizationTools.map(\.name) == Self.sliceEIDs)
        for id in Self.sliceEIDs {
            #expect(host.server.tools.filter { $0.name == id }.count == 1, "\(id) must be registered exactly once")
        }
        // The slice's three Legacy aliases (`asset_catalog` →
        // `asset_catalog_manager`, `localization` →
        // `localization_manager`, `string_catalog` →
        // `string_catalog_migrator`) live in
        // `MCPServer.toolAliases`, which the coordinator owns — they
        // are reported as a wiring fragment instead of asserted here.
    }

    // MARK: - Write policy

    @Test func writesAreRefusedWhenReadOnly() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .readOnly)
        let catalog = try await host.server.callTool("asset_catalog_manager",
                                                     ["action": .string("create_catalog"), "catalogPath": .string("Assets.xcassets")])
        #expect(catalog.isToolError && catalog.firstText.contains("read-only"))
        #expect(!exists(sample, "Assets.xcassets"))
        // A read-only action of a writes:true tool is refused too:
        // the flag is static per tool.
        let inspect = try await host.server.callTool("asset_catalog_manager",
                                                     ["action": .string("list"), "catalogPath": .string("Assets.xcassets")])
        #expect(inspect.isToolError && inspect.firstText.contains("read-only"))
        let status = try await host.server.callTool("localize_app", ["action": .string("status")])
        #expect(status.isToolError && status.firstText.contains("read-only"))
        let set = try await host.server.callTool("strings_localization",
                                                 ["action": .string("set"), "key": .string("k"), "value": .string("v")])
        #expect(set.isToolError && set.firstText.contains("read-only"))
    }

    @Test func reviewRefusalWritesNothing() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .review { _ in false })
        let r = try await host.server.callTool("asset_catalog_manager",
                                               ["action": .string("create_catalog"), "catalogPath": .string("Assets.xcassets")])
        #expect(r.isToolError && r.firstText == MCPServer.rejectedMessage)
        #expect(!exists(sample, "Assets.xcassets"))
    }

    // MARK: - asset_catalog_list

    @Test func assetCatalogListFindsCatalogs() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        // The bare Greeter sample has no .xcassets catalog.
        let none = try await host.server.callTool("asset_catalog_list")
        #expect(!none.isToolError, "\(none.resultText)")
        #expect(none.structured?["catalogCount"] == 0 && none.structured?["totalSets"] == 0)
        #expect(none.firstText.contains("No .xcassets catalogs found."))
        try writeFixture(sample, "Assets.xcassets/Contents.json", "{\"info\" : {\"author\" : \"xcode\", \"version\" : 1}}")
        try writeFixture(sample, "Assets.xcassets/AppIcon.appiconset/Contents.json", "{}")
        try writeFixture(sample, "Assets.xcassets/Accent.colorset/Contents.json", "{}")
        try writeFixture(sample, "Assets.xcassets/Logo.imageset/Contents.json", "{}")
        try writeFixture(sample, "Assets.xcassets/Data.dataset/Contents.json", "{}")
        try writeFixture(sample, "Assets.xcassets/Symbol.symbolset/Contents.json", "{}")
        try writeFixture(sample, "Assets.xcassets/README.txt", "not a set")
        try writeFixture(sample, "Nested/Extra.xcassets/Icon.imageset/Contents.json", "{}")
        let all = try await host.server.callTool("asset_catalog_list")
        #expect(!all.isToolError, "\(all.resultText)")
        #expect(all.structured?["catalogCount"] == 2 && all.structured?["totalSets"] == 6)
        #expect(all.firstText.contains("Found 2 catalog(s) with 6 set(s) total."))
        #expect(all.firstText.contains("Assets.xcassets: 5 set(s)"))
        #expect(all.firstText.contains("  - Logo.imageset"))
        #expect(all.firstText.contains("Nested/Extra.xcassets: 1 set(s)"))
        let one = try await host.server.callTool("asset_catalog_list", ["path": .string("Assets.xcassets")])
        #expect(!one.isToolError, "\(one.resultText)")
        #expect(one.structured?["catalogCount"] == 1 && one.structured?["totalSets"] == 5)
        let missing = try await host.server.callTool("asset_catalog_list", ["path": .string("Nope")])
        #expect(missing.isToolError && missing.firstText.contains("Path 'Nope' does not exist or is not a directory."))
        let outside = try await host.server.callTool("asset_catalog_list", ["path": .string("../outside")])
        #expect(outside.isToolError && outside.firstText.contains("Invalid path '../outside': must be inside the workspace and must not contain '..'."))
    }

    // MARK: - asset_catalog_manager

    @Test func assetCatalogManagerCreatesAndInspects() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let created = try await host.server.callTool("asset_catalog_manager",
                                                     ["action": .string("create_catalog"), "catalogPath": .string("Assets.xcassets")])
        #expect(!created.isToolError, "\(created.resultText)")
        #expect(created.firstText.contains("Successfully initialized asset catalog at Assets.xcassets"))
        #expect(exists(sample, "Assets.xcassets/Contents.json"))
        #expect(sample.read("Assets.xcassets/Contents.json").contains("\"author\" : \"xcode\""))
        let empty = try await host.server.callTool("asset_catalog_manager",
                                                   ["action": .string("inspect"), "catalogPath": .string("Assets.xcassets")])
        #expect(!empty.isToolError, "\(empty.resultText)")
        #expect(empty.firstText.contains("Asset Catalog 'Assets.xcassets' contains 0 asset sets:"))
        let color = try await host.server.callTool("asset_catalog_manager",
                                                   ["action": .string("create_colorset"), "catalogPath": .string("Assets.xcassets"),
                                                    "assetName": .string("Accent"), "lightColorHex": .string("#336699"), "darkColorHex": .string("#1E1E1E")])
        #expect(!color.isToolError, "\(color.resultText)")
        #expect(color.firstText.contains("Created Color Set 'Accent' in Assets.xcassets with light: #336699, dark: #1E1E1E"))
        #expect(exists(sample, "Assets.xcassets/Accent.colorset/Contents.json"))
        #expect(sample.read("Assets.xcassets/Accent.colorset/Contents.json").contains("\"colors\""))
        let image = try await host.server.callTool("asset_catalog_manager",
                                                   ["action": .string("create_imageset"), "catalogPath": .string("Assets.xcassets"),
                                                    "assetName": .string("Logo")])
        #expect(!image.isToolError, "\(image.resultText)")
        #expect(image.firstText.contains("Created Image Set 'Logo' in Assets.xcassets with universal 1x/2x/3x slots."))
        #expect(sample.read("Assets.xcassets/Logo.imageset/Contents.json").contains("\"scale\" : \"3x\""))
        let listed = try await host.server.callTool("asset_catalog_manager",
                                                    ["action": .string("list"), "catalogPath": .string("Assets.xcassets")])
        #expect(!listed.isToolError, "\(listed.resultText)")
        #expect(listed.firstText.contains("contains 2 asset sets:"))
        #expect(listed.firstText.contains("Accent.colorset") && listed.firstText.contains("Logo.imageset"))
        let noName = try await host.server.callTool("asset_catalog_manager",
                                                    ["action": .string("create_colorset"), "catalogPath": .string("Assets.xcassets")])
        #expect(noName.isToolError && noName.firstText.contains("assetName is required for create_colorset"))
        let badAction = try await host.server.callTool("asset_catalog_manager",
                                                       ["action": .string("explode"), "catalogPath": .string("Assets.xcassets")])
        #expect(badAction.isToolError && badAction.firstText.contains("Unsupported action 'explode'"))
        let missing = try await host.server.callTool("asset_catalog_manager",
                                                     ["action": .string("inspect"), "catalogPath": .string("Nope.xcassets")])
        #expect(missing.isToolError && missing.firstText.contains("Asset catalog does not exist at path: Nope.xcassets"))
        let traversal = try await host.server.callTool("asset_catalog_manager",
                                                       ["action": .string("create_catalog"), "catalogPath": .string("../Escape.xcassets")])
        #expect(traversal.isToolError && traversal.firstText.contains("Invalid catalog path '../Escape.xcassets'"))
        let badName = try await host.server.callTool("asset_catalog_manager",
                                                     ["action": .string("create_colorset"), "catalogPath": .string("Assets.xcassets"),
                                                      "assetName": .string("../Escape")])
        #expect(badName.isToolError && badName.firstText.contains("Invalid assetName"))
        let noArgs = try await host.server.callTool("asset_catalog_manager")
        #expect(noArgs.isToolError)
    }

    // MARK: - asset_image_add

    @Test func assetImageAddCopiesImage() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        try writeFixture(sample, "logo.png", "PNGDATA")
        let r = try await host.server.callTool("asset_image_add",
                                               ["catalog": .string("Assets.xcassets"), "imageName": .string("Logo"),
                                                "sourcePath": .string("logo.png")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["catalog"] == "Assets.xcassets" && r.structured?["imageName"] == "Logo")
        #expect(r.structured?["imageSet"] == "Assets.xcassets/Logo.imageset" && r.structured?["fileName"] == "logo.png")
        #expect(r.firstText.contains("Added image 'Logo' to 'Assets.xcassets' as Assets.xcassets/Logo.imageset with file logo.png."))
        #expect(sample.read("Assets.xcassets/Logo.imageset/Contents.json").contains("\"filename\" : \"logo.png\""))
        #expect(sample.read("Assets.xcassets/Logo.imageset/logo.png") == "PNGDATA")
        let dup = try await host.server.callTool("asset_image_add",
                                                 ["catalog": .string("Assets.xcassets"), "imageName": .string("Logo"),
                                                  "sourcePath": .string("logo.png")])
        #expect(dup.isToolError && dup.firstText.contains("Image set 'Logo.imageset' already exists in 'Assets.xcassets'."))
        let slash = try await host.server.callTool("asset_image_add",
                                                   ["catalog": .string("Assets.xcassets"), "imageName": .string("a/b"),
                                                    "sourcePath": .string("logo.png")])
        #expect(slash.isToolError && slash.firstText.contains("Invalid imageName: must be a bare name without slashes or '..'."))
        let chars = try await host.server.callTool("asset_image_add",
                                                   ["catalog": .string("Assets.xcassets"), "imageName": .string("a$b"),
                                                    "sourcePath": .string("logo.png")])
        #expect(chars.isToolError && chars.firstText.contains("Invalid imageName: use letters, digits, spaces, '_' or '-'."))
        let missingSource = try await host.server.callTool("asset_image_add",
                                                           ["catalog": .string("Assets.xcassets"), "imageName": .string("Other"),
                                                            "sourcePath": .string("nope.png")])
        #expect(missingSource.isToolError && missingSource.firstText.contains("Source image not found at 'nope.png'."))
        let badCatalog = try await host.server.callTool("asset_image_add",
                                                        ["catalog": .string("Assets"), "imageName": .string("Other"),
                                                         "sourcePath": .string("logo.png")])
        #expect(badCatalog.isToolError && badCatalog.firstText.contains("Invalid catalog 'Assets': must end with .xcassets."))
        // A source without an extension is copied as image.png.
        try writeFixture(sample, "icon", "ICONDATA")
        let noExt = try await host.server.callTool("asset_image_add",
                                                   ["catalog": .string("Assets.xcassets"), "imageName": .string("Icon"),
                                                    "sourcePath": .string("icon")])
        #expect(!noExt.isToolError, "\(noExt.resultText)")
        #expect(noExt.structured?["fileName"] == "image.png")
        #expect(sample.read("Assets.xcassets/Icon.imageset/image.png") == "ICONDATA")
        let noArgs = try await host.server.callTool("asset_image_add", ["catalog": .string("Assets.xcassets")])
        #expect(noArgs.isToolError)
    }

    // MARK: - localization_audit

    @Test func localizationAuditReportsMissingAndUnused() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        // Remove the sample's own catalog so the counts are the
        // fixtures' alone.
        removeFixture(sample, "Strings/Localizable.xcstrings")
        let host = try await opened(sample)
        try writeFixture(sample, "en.lproj/Localizable.strings", "\"hello\" = \"Hello\";\n\"goodbye\" = \"Goodbye\";\n")
        try writeFixture(sample, "es.lproj/Localizable.strings", "\"hello\" = \"Hola\";\n")
        try writeFixture(sample, "Sources/Greeter/UseStrings.swift",
                         "import Foundation\npublic enum UseStrings {\n    public static let hello = NSLocalizedString(\"hello\", comment: \"\")\n}\n")
        let r = try await host.server.callTool("localization_audit")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["localeCount"] == 2 && r.structured?["totalKeys"] == 2)
        #expect(r.structured?["unusedCount"] == 1 && r.structured?["unused"] == "goodbye")
        #expect(r.firstText.contains("Locales: en, es"))
        #expect(r.firstText.contains("Total distinct keys: 2"))
        #expect(r.firstText.contains("en: complete (2 keys)"))
        #expect(r.firstText.contains("es: missing 1 key(s)"))
        #expect(r.firstText.contains("es missing: goodbye"))
        #expect(r.firstText.contains("Unused keys (1)"))
        #expect(r.firstText.contains("- goodbye"))
    }

    @Test func localizationAuditReadsSampleCatalog() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        // The Greeter sample's own catalog: keys "Hello" (de: Hallo)
        // and "world" (no localizations). Both quoted forms appear in
        // the sample's Swift sources ("Hello" in Greeter.swift,
        // "world" in main.swift), so nothing is unused.
        let r = try await host.server.callTool("localization_audit")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["localeCount"] == 1 && r.structured?["totalKeys"] == 2)
        #expect(r.structured?["unusedCount"] == 0)
        #expect(r.firstText.contains("Locales: de"))
        #expect(r.firstText.contains("de: complete (2 keys)"))
        #expect(r.firstText.contains("Unused keys: none found (all keys referenced in Swift files)."))
    }

    @Test func localizationAuditFindsNothing() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        removeFixture(sample, "Strings/Localizable.xcstrings")
        let host = try await opened(sample)
        let r = try await host.server.callTool("localization_audit")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["localeCount"] == 0 && r.structured?["totalKeys"] == 0)
        #expect(r.firstText.contains("No Localizable.strings or Localizable.xcstrings files found."))
    }

    // MARK: - localization_manager

    @Test func localizationManagerListsReadsAddsValidates() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        try writeFixture(sample, "en.lproj/Localizable.strings", "\"welcome_message\" = \"Welcome\";\n\"farewell\" = \"Bye\";\n")
        try writeFixture(sample, "es.lproj/Localizable.strings", "\"welcome_message\" = \"Bienvenido\";\n")
        let langs = try await host.server.callTool("localization_manager",
                                                   ["action": .string("list_languages"), "filePath": .string("en.lproj/Localizable.strings")])
        #expect(!langs.isToolError, "\(langs.resultText)")
        #expect(langs.structured?["languages"] == "en, es" && langs.structured?["count"] == 2)
        #expect(langs.firstText.contains("Languages (2): en, es"))
        let read = try await host.server.callTool("localization_manager",
                                                  ["action": .string("read_key"), "filePath": .string("en.lproj/Localizable.strings"),
                                                   "key": .string("welcome_message")])
        #expect(!read.isToolError, "\(read.resultText)")
        #expect(read.firstText.contains("Found localization: \"welcome_message\" = \"Welcome\";"))
        let missingKey = try await host.server.callTool("localization_manager",
                                                        ["action": .string("read_key"), "filePath": .string("en.lproj/Localizable.strings"),
                                                         "key": .string("nope")])
        #expect(missingKey.isToolError && missingKey.firstText.contains("Key 'nope' not found in en.lproj/Localizable.strings"))
        let valid = try await host.server.callTool("localization_manager",
                                                   ["action": .string("validate"), "filePath": .string("en.lproj/Localizable.strings")])
        #expect(!valid.isToolError, "\(valid.resultText)")
        #expect(valid.firstText.contains("Validation passed for Localizable.strings. Contains 2 localized entries with no syntax errors."))
        let added = try await host.server.callTool("localization_manager",
                                                   ["action": .string("add_translation"), "filePath": .string("en.lproj/Localizable.strings"),
                                                    "key": .string("thanks"), "translation": .string("Thanks")])
        #expect(!added.isToolError, "\(added.resultText)")
        #expect(added.firstText.contains("Successfully added translation for 'thanks' in Localizable.strings."))
        #expect(sample.read("en.lproj/Localizable.strings").contains("\"thanks\" = \"Thanks\";"))
        let updated = try await host.server.callTool("localization_manager",
                                                     ["action": .string("add_translation"), "filePath": .string("en.lproj/Localizable.strings"),
                                                      "key": .string("welcome_message"), "translation": .string("Welcome!")])
        #expect(!updated.isToolError, "\(updated.resultText)")
        #expect(updated.firstText.contains("Successfully updated translation for 'welcome_message' in Localizable.strings."))
        #expect(sample.read("en.lproj/Localizable.strings").contains("\"welcome_message\" = \"Welcome!\";"))
        // Bad .strings: a line without its terminating semicolon.
        try writeFixture(sample, "Bad.strings", "\"a\" = \"A\";\n\"b\" = \"B\";\n\"c\" = \"C\"\n")
        let bad = try await host.server.callTool("localization_manager",
                                                 ["action": .string("validate"), "filePath": .string("Bad.strings")])
        #expect(bad.isToolError && bad.firstText.contains("Line 3: missing terminating semicolon ';'"))
        let missingFile = try await host.server.callTool("localization_manager",
                                                         ["action": .string("validate"), "filePath": .string("Nope.strings")])
        #expect(missingFile.isToolError && missingFile.firstText.contains("File does not exist at: Nope.strings"))
        let badAction = try await host.server.callTool("localization_manager",
                                                       ["action": .string("explode"), "filePath": .string("en.lproj/Localizable.strings")])
        #expect(badAction.isToolError && badAction.firstText.contains("Unsupported action 'explode'"))
        let badExt = try await host.server.callTool("localization_manager",
                                                    ["action": .string("validate"), "filePath": .string("Package.swift")])
        #expect(badExt.isToolError && badExt.firstText.contains("Unsupported localization file type 'swift'"))
    }

    @Test func localizationManagerHandlesCatalogsAndStringsDict() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        // The sample's own catalog: "Hello" has a de translation, no en unit.
        let missingEn = try await host.server.callTool("localization_manager",
                                                       ["action": .string("read_key"), "filePath": .string("Strings/Localizable.xcstrings"),
                                                        "key": .string("Hello")])
        #expect(missingEn.isToolError && missingEn.firstText.contains("Key 'Hello' not found for locale 'en' in Localizable.xcstrings."))
        // The locale comes from the catalog's own `.lproj` folder.
        try writeFixture(sample, "de.lproj/Localizable.xcstrings", sample.read("Strings/Localizable.xcstrings"))
        let foundDe = try await host.server.callTool("localization_manager",
                                                     ["action": .string("read_key"), "filePath": .string("de.lproj/Localizable.xcstrings"),
                                                      "key": .string("Hello")])
        #expect(!foundDe.isToolError, "\(foundDe.resultText)")
        #expect(foundDe.structured?["value"] == "Hallo" && foundDe.structured?["locale"] == "de")
        #expect(foundDe.firstText.contains("Key 'Hello' (de) = \"Hallo\" in Localizable.xcstrings."))
        let added = try await host.server.callTool("localization_manager",
                                                   ["action": .string("add_translation"), "filePath": .string("de.lproj/Localizable.xcstrings"),
                                                    "key": .string("world"), "translation": .string("Welt")])
        #expect(!added.isToolError, "\(added.resultText)")
        #expect(added.firstText.contains("Successfully added translation for 'world' (de) in Localizable.xcstrings."))
        #expect(sample.read("de.lproj/Localizable.xcstrings").contains("Welt"))
        let validCatalog = try await host.server.callTool("localization_manager",
                                                          ["action": .string("validate"), "filePath": .string("Strings/Localizable.xcstrings")])
        #expect(!validCatalog.isToolError, "\(validCatalog.resultText)")
        #expect(validCatalog.firstText.contains("Validation passed for Localizable.xcstrings. Valid String Catalog with 2 key(s)."))
        let langs = try await host.server.callTool("localization_manager",
                                                   ["action": .string("list_languages"), "filePath": .string("Strings/Localizable.xcstrings")])
        #expect(!langs.isToolError, "\(langs.resultText)")
        #expect(langs.structured?["languages"] == "de, en" && langs.structured?["count"] == 2)
        // .stringsdict: read works, add_translation is honestly refused.
        try writeFixture(sample, "Dict.stringsdict", """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>items</key>
        \t<dict>
        \t\t<key>NSStringLocalizedFormatKey</key>
        \t\t<string>%#@items@</string>
        \t\t<key>items</key>
        \t\t<dict>
        \t\t\t<key>NSStringFormatSpecTypeKey</key>
        \t\t\t<string>NSStringPluralRuleType</string>
        \t\t\t<key>NSStringFormatValueTypeKey</key>
        \t\t\t<string>d</string>
        \t\t\t<key>one</key>
        \t\t\t<string>%d item</string>
        \t\t\t<key>other</key>
        \t\t\t<string>%d items</string>
        \t\t</dict>
        \t</dict>
        </dict>
        </plist>
        """)
        let dictRead = try await host.server.callTool("localization_manager",
                                                      ["action": .string("read_key"), "filePath": .string("Dict.stringsdict"),
                                                       "key": .string("items")])
        #expect(!dictRead.isToolError, "\(dictRead.resultText)")
        #expect(dictRead.firstText.contains("Found localization entry for 'items'"))
        let dictValid = try await host.server.callTool("localization_manager",
                                                       ["action": .string("validate"), "filePath": .string("Dict.stringsdict")])
        #expect(!dictValid.isToolError, "\(dictValid.resultText)")
        #expect(dictValid.firstText.contains("Validation passed for Dict.stringsdict. Valid property list."))
        let dictAdd = try await host.server.callTool("localization_manager",
                                                     ["action": .string("add_translation"), "filePath": .string("Dict.stringsdict"),
                                                      "key": .string("items"), "translation": .string("x")])
        #expect(dictAdd.isToolError && dictAdd.firstText.contains("add_translation is not supported for .stringsdict files"))
    }

    // MARK: - strings_localization

    @Test func stringsLocalizationGetSetDelete() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        try writeFixture(sample, "en.lproj/Localizable.strings", "\"greeting\" = \"Hello\";\n")
        // Discovery: en.lproj/Localizable.strings is the first candidate.
        let get = try await host.server.callTool("strings_localization", ["key": .string("greeting")])
        #expect(!get.isToolError, "\(get.resultText)")
        #expect(get.structured?["value"] == "Hello" && get.structured?["file"] == "Localizable.strings")
        #expect(get.firstText.contains("Key 'greeting' = \"Hello\" in Localizable.strings."))
        let set = try await host.server.callTool("strings_localization",
                                                 ["action": .string("set"), "key": .string("farewell"), "value": .string("Goodbye")])
        #expect(!set.isToolError, "\(set.resultText)")
        #expect(set.firstText.contains("Set key 'farewell' in Localizable.strings."))
        #expect(sample.read("en.lproj/Localizable.strings").contains("\"farewell\" = \"Goodbye\";"))
        let replace = try await host.server.callTool("strings_localization",
                                                     ["action": .string("set"), "key": .string("greeting"), "value": .string("Hi")])
        #expect(!replace.isToolError, "\(replace.resultText)")
        #expect(sample.read("en.lproj/Localizable.strings").contains("\"greeting\" = \"Hi\";"))
        #expect(!sample.read("en.lproj/Localizable.strings").contains("\"greeting\" = \"Hello\";"))
        let deleted = try await host.server.callTool("strings_localization",
                                                     ["action": .string("delete"), "key": .string("farewell")])
        #expect(!deleted.isToolError, "\(deleted.resultText)")
        #expect(deleted.firstText.contains("Deleted key 'farewell' from Localizable.strings."))
        #expect(!sample.read("en.lproj/Localizable.strings").contains("farewell"))
        let deleteMissing = try await host.server.callTool("strings_localization",
                                                           ["action": .string("delete"), "key": .string("farewell")])
        #expect(deleteMissing.isToolError && deleteMissing.firstText.contains("Key 'farewell' not found in Localizable.strings."))
        let noValue = try await host.server.callTool("strings_localization",
                                                     ["action": .string("set"), "key": .string("x")])
        #expect(noValue.isToolError && noValue.firstText.contains("Missing required parameter: value for set action."))
        let badLocale = try await host.server.callTool("strings_localization", ["key": .string("greeting"), "locale": .string("a/b")])
        #expect(badLocale.isToolError && badLocale.firstText.contains("Invalid locale."))
        let badAction = try await host.server.callTool("strings_localization",
                                                       ["action": .string("explode"), "key": .string("greeting")])
        #expect(badAction.isToolError && badAction.firstText.contains("Invalid action 'explode'"))
        let noKey = try await host.server.callTool("strings_localization")
        #expect(noKey.isToolError)
    }

    @Test func stringsLocalizationHandlesCatalogs() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        // Discovery falls through to the sample's own catalog.
        let get = try await host.server.callTool("strings_localization",
                                                 ["key": .string("Hello"), "locale": .string("de")])
        #expect(!get.isToolError, "\(get.resultText)")
        #expect(get.structured?["value"] == "Hallo" && get.structured?["locale"] == "de")
        let set = try await host.server.callTool("strings_localization",
                                                 ["action": .string("set"), "key": .string("world"),
                                                  "locale": .string("de"), "value": .string("Welt")])
        #expect(!set.isToolError, "\(set.resultText)")
        #expect(set.firstText.contains("Set key 'world' (de) in Localizable.xcstrings."))
        let again = try await host.server.callTool("strings_localization",
                                                   ["key": .string("world"), "locale": .string("de")])
        #expect(!again.isToolError && again.structured?["value"] == "Welt")
        let deleted = try await host.server.callTool("strings_localization",
                                                     ["action": .string("delete"), "key": .string("world"), "locale": .string("de")])
        #expect(!deleted.isToolError, "\(deleted.resultText)")
        #expect(deleted.firstText.contains("Deleted key 'world' (de) from Localizable.xcstrings."))
        // The key had no other locale, so the delete removed it entirely.
        #expect(!sample.read("Strings/Localizable.xcstrings").contains("\"world\""))
        let gone = try await host.server.callTool("strings_localization",
                                                  ["key": .string("world"), "locale": .string("de")])
        #expect(gone.isToolError && gone.firstText.contains("Key 'world' not found for locale 'de' in Localizable.xcstrings."))
        // No localization file at all: the discovery error.
        removeFixture(sample, "Strings/Localizable.xcstrings")
        let noFile = try await host.server.callTool("strings_localization", ["key": .string("x"), "locale": .string("fr")])
        #expect(noFile.isToolError && noFile.firstText.contains("No Localizable.strings or Localizable.xcstrings found for locale 'fr'."))
    }

    // MARK: - string_catalog_migrator

    @Test func stringCatalogMigratorConverts() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        try writeFixture(sample, "Old.strings", "// comment\n\"hello\" = \"Hello\";\n\"bye\" = \"Goodbye\";\n\"hello\" = \"Hi\";\n")
        let r = try await host.server.callTool("string_catalog_migrator",
                                               ["sourceStringsPath": .string("Old.strings"),
                                                "targetXcstringsPath": .string("Strings/Migrated.xcstrings")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Successfully migrated 2 localization keys from `Old.strings` to String Catalog `Strings/Migrated.xcstrings`."))
        let migrated = sample.read("Strings/Migrated.xcstrings")
        #expect(migrated.contains("\"sourceLanguage\" : \"en\""))
        #expect(migrated.contains("\"manual\""))
        #expect(migrated.contains("Goodbye"))
        // The duplicate key keeps its last value.
        #expect(migrated.contains("Hi"))
        #expect(!migrated.contains("\"value\" : \"Hello\""))
        let missing = try await host.server.callTool("string_catalog_migrator",
                                                     ["sourceStringsPath": .string("Nope.strings"),
                                                      "targetXcstringsPath": .string("Strings/Out.xcstrings")])
        #expect(missing.isToolError && missing.firstText.contains("Source .strings file not found: Nope.strings"))
        let noArgs = try await host.server.callTool("string_catalog_migrator", ["sourceStringsPath": .string("Old.strings")])
        #expect(noArgs.isToolError)
    }

    // MARK: - strings_file_validate

    @Test func stringsFileValidateCounts() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Check.strings",
                         "// comment\n\"ok\" = \"OK\";\n\"empty\" = \"\";\n\"ok\" = \"Again\";\nthis is not an entry\n\"unterminated\" = \"Oops\"\n")
        let r = try await host.server.callTool("strings_file_validate", ["path": .string("Check.strings")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["valid"] == 3 && r.structured?["duplicates"] == 1)
        #expect(r.structured?["malformed"] == 2 && r.structured?["emptyValues"] == 1)
        #expect(r.structured?["passed"] == false)
        #expect(r.firstText.contains("Strings validation for Check.strings:"))
        #expect(r.firstText.contains("- Valid entries: 3"))
        #expect(r.firstText.contains("  DUPLICATE: ok"))
        #expect(r.firstText.contains("  MALFORMED line 5: this is not an entry"))
        #expect(r.firstText.contains("  MALFORMED line 6: \"unterminated\" = \"Oops\""))
        #expect(r.firstText.contains("  EMPTY VALUE: empty"))
        try writeFixture(sample, "Good.strings", "\"a\" = \"A\";\n\"b\" = \"B\";\n")
        let good = try await host.server.callTool("strings_file_validate", ["path": .string("Good.strings")])
        #expect(!good.isToolError && good.structured?["passed"] == true)
        #expect(good.structured?["valid"] == 2 && good.structured?["malformed"] == 0)
        let missing = try await host.server.callTool("strings_file_validate", ["path": .string("Nope.strings")])
        #expect(missing.isToolError && missing.firstText.contains("Cannot read file at: Nope.strings"))
        try writeFixture(sample, "Empty.strings", "")
        let empty = try await host.server.callTool("strings_file_validate", ["path": .string("Empty.strings")])
        #expect(empty.isToolError && empty.firstText.contains("File is empty or undecodable: Empty.strings"))
        let outside = try await host.server.callTool("strings_file_validate", ["path": .string("../outside.strings")])
        #expect(outside.isToolError && outside.firstText.contains("Cannot read file at: ../outside.strings"))
        let noArgs = try await host.server.callTool("strings_file_validate")
        #expect(noArgs.isToolError)
    }

    // MARK: - localize_app

    @Test func localizeAppLocalizesAndReportsStatus() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        try writeFixture(sample, "Sources/Greeter/LocalizableDemo.swift",
                         """
                         import Foundation
                         public enum LocalizableDemo {
                             public static let welcome = NSLocalizedString("welcome_message", comment: "Welcome")
                             public static let bye = String(localized: "goodbye_message")
                             public static let other = NSLocalizedString("other_table", tableName: "Other", comment: "")
                         }
                         """)
        let status = try await host.server.callTool("localize_app", ["action": .string("status")])
        #expect(!status.isToolError, "\(status.resultText)")
        #expect(status.structured?["count"] == 2 && status.structured?["languages"] == "de")
        #expect(status.structured?["sourceLanguage"] == "en" && status.structured?["layoutDirection"] == "ltr")
        #expect(status.firstText.contains("Localization status:"))
        #expect(status.firstText.contains("- Discovered keys in Swift: 2"))
        #expect(status.firstText.contains("- String Catalog: present (2 keys, languages: de)"))
        #expect(status.firstText.contains("- No Info.plist found."))
        let localized = try await host.server.callTool("localize_app",
                                                       ["languages": .array([.string("es"), .string("fr")]),
                                                        "translations": .object(["welcome_message": .object(["es": .string("Bienvenido")])])])
        #expect(!localized.isToolError, "\(localized.resultText)")
        #expect(localized.structured?["count"] == 2 && localized.structured?["languages"] == "es, fr")
        #expect(localized.structured?["layoutDirection"] == "ltr" && localized.structured?["sourceLanguage"] == "en")
        #expect(localized.structured?["keysAdded"] == 6)
        #expect(localized.firstText.contains("Localized app into 2 language(s): es, fr."))
        #expect(localized.firstText.contains("- Discovered 2 localizable key(s) in 5 Swift file(s). (1 key(s) use a non-Localizable table and were skipped.)"))
        #expect(localized.firstText.contains("- String Catalog: Strings/Localizable.xcstrings — 4 key(s), 6 new localization(s) added, 0 updated with supplied translations."))
        #expect(localized.firstText.contains("- No Info.plist found; CFBundleLocalizations was not updated."))
        #expect(localized.firstText.contains("Next: call localization_audit to find keys still missing per locale."))
        let catalog = sample.read("Strings/Localizable.xcstrings")
        #expect(catalog.contains("welcome_message") && catalog.contains("Bienvenido"))
        #expect(catalog.contains("goodbye_message"))
        #expect(catalog.contains("\"state\" : \"new\""))
        // A second localize into an RTL language reports rtl.
        let rtl = try await host.server.callTool("localize_app", ["languages": .array([.string("ar")])])
        #expect(!rtl.isToolError, "\(rtl.resultText)")
        #expect(rtl.structured?["layoutDirection"] == "rtl")
        #expect(rtl.firstText.contains("- Layout direction: rtl (RTL languages: ar)."))
        let tooMany = try await host.server.callTool("localize_app",
                                                     ["languages": .array([.string("es"), .string("fr"), .string("de"), .string("it")])])
        #expect(tooMany.isToolError && tooMany.firstText.contains("Too many languages (4). Maximum 3 languages per Assist session; run again for more."))
        let badCode = try await host.server.callTool("localize_app", ["languages": .array([.string("e")])])
        #expect(badCode.isToolError && badCode.firstText.contains("Invalid language code 'e'."))
        let noLanguages = try await host.server.callTool("localize_app")
        #expect(noLanguages.isToolError && noLanguages.firstText.contains("Missing required parameter: languages"))
        let badAction = try await host.server.callTool("localize_app", ["action": .string("explode")])
        #expect(badAction.isToolError && badAction.firstText.contains("Invalid action 'explode'"))
    }

    @Test func localizeAppFailsWithNoKeys() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        // The bare Greeter sources wrap no user-facing text.
        let r = try await host.server.callTool("localize_app", ["languages": .array([.string("es")])])
        #expect(r.isToolError && r.firstText.contains("No localizable strings found in Swift sources under"))
        #expect(r.firstText.contains("Wrap user-facing text in NSLocalizedString(_:comment:) or String(localized:) first."))
    }

    @Test func localizeAppSetsDevelopmentRegion() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        try writeFixture(sample, "Info.plist", """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>CFBundleDevelopmentRegion</key>
        \t<string>en</string>
        \t<key>CFBundleName</key>
        \t<string>Greeter</string>
        </dict>
        </plist>
        """)
        let r = try await host.server.callTool("localize_app",
                                               ["action": .string("set_development_region"), "development_region": .string("de")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["path"] == "Info.plist" && r.structured?["sourceLanguage"] == "de")
        #expect(r.firstText.contains("Set CFBundleDevelopmentRegion to 'de' (was: 'en')."))
        #expect(r.firstText.contains("Also set the String Catalog source language to de."))
        let plist = sample.read("Info.plist")
        #expect(plist.contains("<key>CFBundleDevelopmentRegion</key>") && plist.contains("<string>de</string>"))
        #expect(sample.read("Strings/Localizable.xcstrings").contains("\"sourceLanguage\" : \"de\""))
        let missingRegion = try await host.server.callTool("localize_app", ["action": .string("set_development_region")])
        #expect(missingRegion.isToolError && missingRegion.firstText.contains("Missing required parameter: development_region for action=set_development_region."))
        let badRegion = try await host.server.callTool("localize_app",
                                                       ["action": .string("set_development_region"), "development_region": .string("e")])
        #expect(badRegion.isToolError && badRegion.firstText.contains("Invalid language code 'e'."))
    }

    @Test func localizeAppSetRegionFailsWithoutPlist() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let r = try await host.server.callTool("localize_app",
                                               ["action": .string("set_development_region"), "development_region": .string("de")])
        #expect(r.isToolError && r.firstText.contains("No Info.plist found in the workspace; cannot set the development region."))
    }
}
