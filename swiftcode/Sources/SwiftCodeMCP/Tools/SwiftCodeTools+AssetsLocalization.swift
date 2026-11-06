import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore

/// The ported Legacy asset-catalog / localization tool family (Wave 7,
/// slice E).
///
/// Behaviour source: Legacy's `AssistAssetCatalogListTool`,
/// `AssistAssetCatalogTool`, `AssistAssetImageAddTool`,
/// `AssistLocalizationAuditTool`, `AssistLocalizationTool`,
/// `AssistLocalizeAppTool`, `AssistStringCatalogMigratorTool`,
/// `AssistStringsFileValidateTool` and `AssistStringsLocalizationTool`
/// (Dylan's own code, ported under MIT). The behaviour contract is
/// `~/SwiftCode-Migration-Workspace/scratch/wave7-slice-e-spec.md`.
///
/// Conventions, following Waves 1–6:
///
/// * Schemas are Legacy's `parametersSchema` verbatim, plus the
///   `workspace` parameter every SwiftCode tool carries. Legacy's
///   parameter-name aliases are NOT supported: SwiftCode's argument
///   validation rejects unknown arguments before the handler runs.
///   The three tool-name aliases in this slice (`asset_catalog` →
///   `asset_catalog_manager`, `localization` →
///   `localization_manager`, `string_catalog` →
///   `string_catalog_migrator`, from Legacy's `AssistToolRegistry`
///   alias table) live in `MCPServer.toolAliases`, which the
///   coordinator owns — they are not added here.
/// * Structured data keeps Legacy's keys, with typed JSON values
///   (integers, booleans) the way SwiftCode's other tools do — Legacy's
///   string-only map is not reproduced. Tools whose Legacy result
///   carries no data, or whose data keys vary by action / file type
///   (`asset_catalog_manager`, `localization_manager`,
///   `localize_app`, `string_catalog_migrator`,
///   `strings_localization`), return a plain text result instead.
/// * Paths never escape the workspace. Legacy's tools use three
///   different path rules; the unchecked one (append to the
///   workspace root, so `..` escapes) is NOT ported. Paths go
///   through either the slice's strict resolver
///   (`assetsStrictResolve` — Legacy's `AssistWorkspacePaths.resolve`
///   rule: any `..` as text is refused, absolute paths must be
///   inside the workspace) or the session resolver
///   (`resolveFileReadingPath`). A `..` that stays inside the
///   workspace is refused here, unlike Wave 6's session-resolver
///   tools, because these tools' Legacy messages say `..` is
///   forbidden and the message must stay honest.
/// * `.xcstrings` goes through SwiftCode's own `StringCatalog` seam
///   (`SwiftCodeStrings`, re-exported by `SwiftCodeIDECore`): parsing,
///   `sourceLanguage`, `keys`, `setTranslation`, `addKey`, and
///   `data()` for writing. Where Legacy needs a shape
///   `StringCatalog` has no setter for (a `"new"`-state placeholder
///   unit, deleting one locale of a key), the handler edits the
///   catalog's public `json` (`OrderedJSON`) directly — the seam's
///   own model, not a parallel one. `.strings` files use Legacy's
///   line-based scan/edit: `StringsFile.parse` throws on the first
///   malformed line, which would change Legacy's per-line error
///   behaviour, so the line scan is the faithful port.
/// * Asset catalogs use plain `FileManager` directory work, the way
///   Legacy does: these tools only enumerate `.xcassets` directories
///   and write `Contents.json` text. `SwiftCodeAssetCatalog` is a CAR
///   compiler whose directory loader is not visible to `SwiftCodeMCP`
///   (no target dependency, and `Package.swift` is out of this
///   slice's scope), and nothing here needs a compiled CAR.
/// * Approval gating: the six writing tools
///   (`asset_catalog_manager`, `asset_image_add`,
///   `localization_manager`, `localize_app`,
///   `string_catalog_migrator`, `strings_localization`) are
///   `writes: true` with `safeMutation` annotations. Text writes go
///   through `commit()`; the byte copy in `asset_image_add` is its
///   own `MCPChange` + `approve()` before `copyItem`. The `writes`
///   flag is static per tool, so `asset_catalog_manager`'s
///   `inspect`/`list`, `localization_manager`'s `list_languages` /
///   `read_key` / `validate`, and `localize_app`'s `status` are
///   refused in `readOnly` mode even though they write nothing —
///   exactly as the approval model specifies for dry-run tools.
///   There is no Autopilot bypass.
///
/// Deliberate deviations from Legacy, recorded here:
///
/// * Every path is confined to the workspace (§1 of the spec).
/// * `asset_catalog_manager`'s `create_colorset` keeps Legacy's
///   hardcoded colour components verbatim: the hex arguments are
///   honoured only in the success message, as in Legacy.
/// * `asset_catalog_manager` rejects an `assetName` containing `/`,
///   `\`, or `..`; Legacy did not check it.
/// * `localization_manager`'s `.xcstrings` `add_translation` on a
///   new file writes the seam's canonical empty catalog
///   (`sourceLanguage` + `version`); Legacy's new file had neither.
/// * `string_catalog_migrator` writes through `commit()`, which
///   creates parent directories; Legacy's raw write failed when
///   the parent was missing.
/// * `localize_app` `set_development_region` ignores a catalog-write
///   failure (including a review refusal of the catalog change)
///   after the plist is committed, as Legacy ignores its
///   catalog-write failure.
/// * Structured data uses typed values (ints, bools) where Legacy's
///   map held strings only; keys are unchanged.
/// * Legacy's `suggestedNextActions: ["localization_audit"]` on
///   `localize_app` is dropped (SwiftCode's `MCPToolResult` has no such
///   field); the "Next: call localization_audit …" line in the
///   summary keeps the pointer.
/// * Legacy's `LiveDiffStreamer`, `XcodeProjWriter.addFileReference`
///   and `ProjectSessionStore.recordAssistFileMutation` side channels
///   are not ported: no unreviewed side writes, and new files are
///   not auto-registered in any project file.
///
/// Honest refusals inside the slice are Legacy's own, preserved
/// verbatim: `localization_manager` `add_translation` on a
/// `.stringsdict` file (plural/format-rule dictionaries cannot take
/// a plain string), and `localize_app` `localize` when no
/// localizable keys are discovered.
extension SwiftCodeMCPHost {
    var assetsLocalizationTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        return [
            tool("asset_catalog_list", "List Asset Catalog",
                 "Lists asset catalogs under the workspace and the image, color, and app-icon sets inside each catalog.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Optional workspace-relative path to a single .xcassets catalog or a directory to search. Default: whole workspace.")]),
                 output: Schema.output(["catalogCount": Schema.int, "totalSets": Schema.int, "catalogs": Schema.str])) { h, call in
                try h.assetsListCatalogs(call)
            },
            tool("asset_catalog_manager", "Asset Catalog Manager",
                 "Inspects, manages, and creates asset catalogs (.xcassets), image sets, color sets, and dataset assets.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("Action to perform: 'inspect', 'create_catalog', 'create_colorset', 'create_imageset', 'list'."),
                                       "catalogPath": Schema.string("Workspace-relative path to the .xcassets directory."),
                                       "assetName": Schema.string("Name of the color set or image set to create or inspect."),
                                       "lightColorHex": Schema.string("Hex color for Light mode (e.g. '#FFFFFF' or '#336699')."),
                                       "darkColorHex": Schema.string("Hex color for Dark mode (e.g. '#1E1E1E').")],
                                      required: ["action", "catalogPath"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.assetsManageCatalog(call)
            },
            tool("asset_image_add", "Add Asset Image",
                 "Adds an image to an asset catalog by creating an .imageset with Contents.json and copying the source image.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "catalog": Schema.string("Workspace-relative path to the .xcassets catalog (e.g. Assets.xcassets). Created if missing."),
                                       "imageName": Schema.string("Name for the new image set (no slashes or '..')."),
                                       "sourcePath": Schema.string("Workspace-relative path to the source image file inside the workspace.")],
                                      required: ["catalog", "imageName", "sourcePath"]),
                 output: Schema.output(["catalog": Schema.str, "imageName": Schema.str, "imageSet": Schema.str, "fileName": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.assetsAddImage(call)
            },
            tool("localization_audit", "Localization Audit",
                 "Compares localization keys across locales and reports missing keys and keys never referenced in Swift code.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["localeCount": Schema.int, "totalKeys": Schema.int, "unusedCount": Schema.int, "unused": Schema.str])) { h, call in
                try h.assetsAuditLocalization(call)
            },
            tool("localization_manager", "Localization Manager",
                 "Inspects, extracts, adds translations, and validates .strings, .stringsdict, and .xcstrings localization files.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("Action: 'list_languages', 'read_key', 'add_translation', 'validate'."),
                                       "filePath": Schema.string("Workspace-relative path to .strings or .xcstrings file."),
                                       "key": Schema.string("Localization key (e.g. 'welcome_message')."),
                                       "translation": Schema.string("Translated string value to insert.")],
                                      required: ["action", "filePath"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.assetsManageLocalization(call)
            },
            tool("localize_app", "App Localizer",
                 "Fully localizes an app into up to 3 languages per session: discovers localizable strings in Swift sources, creates/merges a Localizable.xcstrings String Catalog with translations, and sets Info.plist CFBundleLocalizations + CFBundleDevelopmentRegion. Follows the LocalizingApps.md System Asset.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("localize (default), status, or set_development_region."),
                                       "languages": Schema.array(Schema.str, "Language codes to localize into, 1-3 per Assist session (e.g. [\"es\",\"fr\",\"de\"]). Required for action=localize."),
                                       "translations": ["type": "object", "description": .string("Optional map of string-key -> language-code -> translated text. Keys or languages without a supplied translation are written with state \"new\" as untranslated placeholders for the model to translate later.")],
                                       "development_region": Schema.string("Development-region language code (default \"en\"). Sets the String Catalog source language on localize; the value to set for action=set_development_region.")]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.assetsLocalizeApp(call)
            },
            tool("string_catalog_migrator", "String Catalog Migrator",
                 "Converts legacy .strings files into modern Xcode 15+ String Catalogs (.xcstrings).",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "sourceStringsPath": Schema.string("Relative path to the legacy .strings file."),
                                       "targetXcstringsPath": Schema.string("Relative destination path for the .xcstrings file.")],
                                      required: ["sourceStringsPath", "targetXcstringsPath"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.assetsMigrateStringCatalog(call)
            },
            tool("strings_file_validate", "Strings File Validate",
                 "Validates .strings localization files: syntax errors, duplicate keys, and empty values.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the .strings file.")],
                                      required: ["path"]),
                 output: Schema.output(["valid": Schema.int, "duplicates": Schema.int, "malformed": Schema.int,
                                        "emptyValues": Schema.int, "passed": Schema.bool])) { h, call in
                try h.assetsValidateStringsFile(call)
            },
            tool("strings_localization", "Localization Strings",
                 "Gets, sets, or deletes a localization string in Localizable.strings or Localizable.xcstrings.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("get, set, or delete. Default: get."),
                                       "key": Schema.string("Localization key (required)."),
                                       "value": Schema.string("Value for set action."),
                                       "locale": Schema.string("Locale code such as en or fr. Default: en."),
                                       "path": Schema.string("Optional workspace-relative path to a specific .strings or .xcstrings file.")],
                                      required: ["key"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.assetsStringsLocalization(call)
            },
        ]
    }
}

extension SwiftCodeMCPHost {
    // MARK: - asset_catalog_list

    func assetsListCatalogs(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        var searchRoots: [URL] = [root]
        if let raw = call.arguments["path"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            guard let resolved = Self.assetsStrictResolve(raw, root: root) else {
                throw MCPToolError("Invalid path '\(raw)': must be inside the workspace and must not contain '..'.")
            }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir), isDir.boolValue else {
                throw MCPToolError("Path '\(raw)' does not exist or is not a directory.")
            }
            searchRoots = [resolved]
        }
        var catalogs: [URL] = []
        for searchRoot in searchRoots {
            if searchRoot.lastPathComponent.hasSuffix(".xcassets") {
                catalogs.append(searchRoot)
                continue
            }
            guard let enumerator = FileManager.default.enumerator(at: searchRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            while let url = enumerator.nextObject() as? URL {
                if url.lastPathComponent.hasSuffix(".xcassets") {
                    catalogs.append(url)
                    enumerator.skipDescendants()
                }
            }
        }
        catalogs.sort { $0.path < $1.path }
        if catalogs.isEmpty {
            return .structured(["catalogCount": .int(0), "totalSets": .int(0), "catalogs": .string("")],
                               summary: "No .xcassets catalogs found.")
        }
        var lines: [String] = []
        var totalSets = 0
        var catalogNames: [String] = []
        for catalog in catalogs {
            let rel = relative(catalog.path, in: s)
            catalogNames.append(rel)
            let sets = Self.assetsListSets(in: catalog)
            totalSets += sets.count
            lines.append("\(rel): \(sets.count) set(s)")
            for set in sets { lines.append("  - \(set)") }
        }
        lines.insert("Found \(catalogs.count) catalog(s) with \(totalSets) set(s) total.", at: 0)
        return .structured(["catalogCount": .int(catalogs.count), "totalSets": .int(totalSets),
                            "catalogs": .string(catalogNames.joined(separator: ","))],
                           summary: lines.joined(separator: "\n"))
    }

    /// A catalog's sets: immediate children ending in `.imageset`,
    /// `.colorset`, `.appiconset`, `.dataset`, or `.symbolset`,
    /// sorted by name. (Wider than the manager's inspect filter —
    /// Legacy's two tools genuinely differ; see the spec §3/§4.)
    nonisolated static func assetsListSets(in catalog: URL) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: catalog, includingPropertiesForKeys: nil) else { return [] }
        var sets: [String] = []
        for item in contents {
            let name = item.lastPathComponent
            if name.hasSuffix(".imageset") || name.hasSuffix(".colorset") || name.hasSuffix(".appiconset")
                || name.hasSuffix(".dataset") || name.hasSuffix(".symbolset") {
                sets.append(name)
            }
        }
        return sets.sorted()
    }

    // MARK: - asset_catalog_manager

    func assetsManageCatalog(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let action = call.arguments["action"]?.string,
              let catalogPath = call.arguments["catalogPath"]?.string else {
            throw MCPToolError("Missing required parameters: action and catalogPath")
        }
        let lowered = action.lowercased()
        guard ["inspect", "create_catalog", "create_colorset", "create_imageset", "list"].contains(lowered) else {
            throw MCPToolError("Unsupported action '\(action)'. Valid actions: inspect, create_catalog, create_colorset, create_imageset, list")
        }
        let root = Self.folder(of: s.model)
        guard let catalogURL = Self.assetsStrictResolve(catalogPath, root: root) else {
            throw MCPToolError("Invalid catalog path '\(catalogPath)': must be inside the workspace and must not contain '..'.")
        }
        switch lowered {
        case "create_catalog":
            let contentsURL = catalogURL.appendingPathComponent("Contents.json")
            let contentsJSON = """
            {
              "info" : {
                "author" : "xcode",
                "version" : 1
              }
            }
            """
            try await commit(MCPChange(tool: call.name, path: contentsURL.path, relativePath: relative(contentsURL.path, in: s),
                                       original: text(of: contentsURL), proposed: contentsJSON,
                                       summary: "Create asset catalog \(catalogPath)"), call: call, session: s)
            return .text("Successfully initialized asset catalog at \(catalogPath)")
        case "create_colorset":
            guard let assetName = call.arguments["assetName"]?.string, !assetName.isEmpty else {
                throw MCPToolError("assetName is required for create_colorset")
            }
            try Self.assetsCheckAssetName(assetName)
            let lightHex = (call.arguments["lightColorHex"]?.string) ?? "#007AFF"
            let darkHex = (call.arguments["darkColorHex"]?.string) ?? lightHex
            let setURL = catalogURL.appendingPathComponent("\(assetName).colorset")
            let contentsURL = setURL.appendingPathComponent("Contents.json")
            // Legacy's file text verbatim — including its quirk: the
            // components below are hardcoded and the hex arguments
            // appear only in the success message (see the spec §4).
            let contentsJSON = """
            {
              "colors" : [
                {
                  "idiom" : "universal",
                  "color" : {
                    "color-space" : "srgb",
                    "components" : {
                      "alpha" : "1.000",
                      "blue" : "1.000",
                      "green" : "0.500",
                      "red" : "0.000"
                    }
                  }
                },
                {
                  "appearances" : [
                    {
                      "appearance" : "luminosity",
                      "value" : "dark"
                    }
                  ],
                  "idiom" : "universal",
                  "color" : {
                    "color-space" : "srgb",
                    "components" : {
                      "alpha" : "1.000",
                      "blue" : "1.000",
                      "green" : "0.600",
                      "red" : "0.100"
                    }
                  }
                }
              ],
              "info" : {
                "author" : "xcode",
                "version" : 1
              }
            }
            """
            try await commit(MCPChange(tool: call.name, path: contentsURL.path, relativePath: relative(contentsURL.path, in: s),
                                       original: text(of: contentsURL), proposed: contentsJSON,
                                       summary: "Create color set \(assetName).colorset in \(catalogPath)"), call: call, session: s)
            return .text("Created Color Set '\(assetName)' in \(catalogPath) with light: \(lightHex), dark: \(darkHex)")
        case "create_imageset":
            guard let assetName = call.arguments["assetName"]?.string, !assetName.isEmpty else {
                throw MCPToolError("assetName is required for create_imageset")
            }
            try Self.assetsCheckAssetName(assetName)
            let setURL = catalogURL.appendingPathComponent("\(assetName).imageset")
            let contentsURL = setURL.appendingPathComponent("Contents.json")
            let contentsJSON = """
            {
              "images" : [
                { "idiom" : "universal", "scale" : "1x" },
                { "idiom" : "universal", "scale" : "2x" },
                { "idiom" : "universal", "scale" : "3x" }
              ],
              "info" : {
                "author" : "xcode",
                "version" : 1
              }
            }
            """
            try await commit(MCPChange(tool: call.name, path: contentsURL.path, relativePath: relative(contentsURL.path, in: s),
                                       original: text(of: contentsURL), proposed: contentsJSON,
                                       summary: "Create image set \(assetName).imageset in \(catalogPath)"), call: call, session: s)
            return .text("Created Image Set '\(assetName)' in \(catalogPath) with universal 1x/2x/3x slots.")
        default: // inspect, list
            guard FileManager.default.fileExists(atPath: catalogURL.path) else {
                throw MCPToolError("Asset catalog does not exist at path: \(catalogPath)")
            }
            do {
                let items = try FileManager.default.contentsOfDirectory(atPath: catalogURL.path)
                let sets = items.filter { $0.hasSuffix(".colorset") || $0.hasSuffix(".imageset") || $0.hasSuffix(".appiconset") || $0.hasSuffix(".dataset") }
                return .text("Asset Catalog '\(catalogPath)' contains \(sets.count) asset sets:\n" + sets.joined(separator: "\n"))
            } catch {
                throw MCPToolError("Failed to inspect catalog: \(error.localizedDescription)")
            }
        }
    }

    /// Confinement for a set name: Legacy did not check it, and a
    /// `..` name would escape the catalog. The character set is
    /// otherwise Legacy's (no charset check on this tool, unlike
    /// `asset_image_add`).
    nonisolated static func assetsCheckAssetName(_ name: String) throws {
        guard !name.contains("/") && !name.contains("\\") && !name.contains("..") && name != "." && name != ".." else {
            throw MCPToolError("Invalid assetName: must be a bare name without slashes or '..'.")
        }
    }

    // MARK: - asset_image_add

    func assetsAddImage(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let catalogRaw = call.arguments["catalog"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !catalogRaw.isEmpty else {
            throw MCPToolError("Missing required parameter: catalog")
        }
        guard let imageNameRaw = call.arguments["imageName"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !imageNameRaw.isEmpty else {
            throw MCPToolError("Missing required parameter: imageName")
        }
        guard let sourceRaw = call.arguments["sourcePath"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceRaw.isEmpty else {
            throw MCPToolError("Missing required parameter: sourcePath")
        }
        let catalog = catalogRaw
        let imageName = imageNameRaw
        guard catalog.hasSuffix(".xcassets") else {
            throw MCPToolError("Invalid catalog '\(catalog)': must end with .xcassets.")
        }
        guard !imageName.contains("/") && !imageName.contains("\\") && !imageName.contains("..") && imageName != "." && imageName != ".." else {
            throw MCPToolError("Invalid imageName: must be a bare name without slashes or '..'.")
        }
        let allowedChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_- "))
        guard !imageName.unicodeScalars.contains(where: { !allowedChars.contains($0) }) else {
            throw MCPToolError("Invalid imageName: use letters, digits, spaces, '_' or '-'.")
        }
        let root = Self.folder(of: s.model)
        guard let catalogURL = Self.assetsStrictResolve(catalog, root: root) else {
            throw MCPToolError("Invalid catalog path '\(catalog)': must be inside the workspace and must not contain '..'.")
        }
        guard let sourceURL = Self.assetsStrictResolve(sourceRaw, root: root) else {
            throw MCPToolError("Invalid sourcePath '\(sourceRaw)': must be inside the workspace and must not contain '..'.")
        }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw MCPToolError("Source image not found at '\(sourceRaw)'.")
        }
        let fileName = sourceURL.pathExtension.isEmpty ? "image.png" : sourceURL.lastPathComponent
        let imageSetURL = catalogURL.appendingPathComponent("\(imageName).imageset")
        guard !FileManager.default.fileExists(atPath: imageSetURL.path) else {
            throw MCPToolError("Image set '\(imageName).imageset' already exists in '\(catalog)'.")
        }
        let contentsJSON = """
        {
          "images" : [
            {
              "filename" : "\(fileName)",
              "idiom" : "universal"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
        let contentsURL = imageSetURL.appendingPathComponent("Contents.json")
        let destImageURL = imageSetURL.appendingPathComponent(fileName)
        // Contents.json first (commit creates the imageset directory),
        // then the image copy as its own approved change — Legacy's
        // order, and the approval model's non-text shape (§6.2).
        try await commit(MCPChange(tool: call.name, path: contentsURL.path, relativePath: relative(contentsURL.path, in: s),
                                   original: text(of: contentsURL), proposed: contentsJSON,
                                   summary: "Add image set \(imageName).imageset to \(catalog)"), call: call, session: s)
        let copyChange = MCPChange(tool: call.name, path: destImageURL.path, relativePath: relative(destImageURL.path, in: s),
                                   original: nil, proposed: "",
                                   summary: "Copy \(sourceRaw) to \(relative(destImageURL.path, in: s))")
        guard await call.approve(copyChange) else { throw MCPToolError(MCPServer.rejectedMessage) }
        do {
            if FileManager.default.fileExists(atPath: destImageURL.path) {
                try FileManager.default.removeItem(at: destImageURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destImageURL)
        } catch {
            throw MCPToolError("Failed to add asset image: \(error.localizedDescription)")
        }
        s.noteFileEdited(destImageURL.path)
        delegate?.mcpHostDidWrite(destImageURL.path)
        guard FileManager.default.fileExists(atPath: contentsURL.path), FileManager.default.fileExists(atPath: destImageURL.path) else {
            throw MCPToolError("Verification failed: image set files not present after write.")
        }
        let relativeSet = relative(imageSetURL.path, in: s)
        return .structured(["catalog": .string(catalog), "imageName": .string(imageName),
                            "imageSet": .string(relativeSet), "fileName": .string(fileName)],
                           summary: "Added image '\(imageName)' to '\(catalog)' as \(relativeSet) with file \(fileName).")
    }
}

extension SwiftCodeMCPHost {
    // MARK: - localization_audit

    func assetsAuditLocalization(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        var keysByLocale: [String: Set<String>] = [:]
        var sourceFiles: [String] = []
        var swiftFiles: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            throw MCPToolError("Failed to enumerate workspace.")
        }
        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            if name == "Localizable.strings" {
                let locale = Self.assetsLocaleFor(url: url) ?? "unknown"
                keysByLocale[locale, default: []].formUnion(Self.assetsParseStringsKeys(at: url))
                sourceFiles.append(relative(url.path, in: s))
            } else if name == "Localizable.xcstrings" {
                for (locale, keys) in Self.assetsXCStringsKeys(at: url) {
                    keysByLocale[locale, default: []].formUnion(keys)
                }
                sourceFiles.append(relative(url.path, in: s))
            } else if url.pathExtension == "swift" {
                swiftFiles.append(url)
            }
        }
        if keysByLocale.isEmpty {
            return .structured(["localeCount": .int(0), "totalKeys": .int(0), "unusedCount": .int(0), "unused": .string("")],
                               summary: "No Localizable.strings or Localizable.xcstrings files found.")
        }
        let allKeys = keysByLocale.values.reduce(Set<String>()) { $0.union($1) }
        var lines: [String] = []
        lines.append("Locales: \(keysByLocale.keys.sorted().joined(separator: ", "))")
        lines.append("Total distinct keys: \(allKeys.count)")
        lines.append("Localization files: \(sourceFiles.joined(separator: ", "))")
        var missingLines: [String] = []
        for locale in keysByLocale.keys.sorted() {
            let missing = allKeys.subtracting(keysByLocale[locale] ?? [])
            if missing.isEmpty {
                lines.append("\(locale): complete (\(keysByLocale[locale]?.count ?? 0) keys)")
            } else {
                lines.append("\(locale): missing \(missing.count) key(s)")
                for key in missing.sorted().prefix(50) {
                    missingLines.append("\(locale) missing: \(key)")
                }
            }
        }
        if !missingLines.isEmpty {
            lines.append("Missing keys:")
            lines.append(contentsOf: missingLines)
        }
        let unused = Self.assetsFindUnusedKeys(allKeys: allKeys, swiftFiles: swiftFiles)
        if unused.isEmpty {
            lines.append("Unused keys: none found (all keys referenced in Swift files).")
        } else {
            lines.append("Unused keys (\(unused.count)): keys not referenced via NSLocalizedString / String(localized:) / quoted literal in Swift files:")
            for key in unused.sorted().prefix(100) {
                lines.append("- \(key)")
            }
        }
        return .structured(["localeCount": .int(keysByLocale.keys.count), "totalKeys": .int(allKeys.count),
                            "unusedCount": .int(unused.count), "unused": .string(unused.sorted().joined(separator: ","))],
                           summary: lines.joined(separator: "\n"))
    }

    /// Legacy's unused-key scan, verbatim: the first 2000 Swift files,
    /// skipping files over 300,000 characters, stopping once the
    /// concatenated text exceeds 5,000,000 characters; a key is unused
    /// when its quoted form does not appear in that text.
    nonisolated static func assetsFindUnusedKeys(allKeys: Set<String>, swiftFiles: [URL]) -> [String] {
        var swiftText = ""
        for file in swiftFiles.prefix(2000) {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            if content.count > 300_000 { continue }
            swiftText += "\n" + content
            if swiftText.count > 5_000_000 { break }
        }
        var unused: [String] = []
        for key in allKeys {
            if !swiftText.contains("\"\(key)\"") {
                unused.append(key)
            }
        }
        return unused
    }

    // MARK: - localization_manager

    func assetsManageLocalization(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let action = call.arguments["action"]?.string,
              let filePath = call.arguments["filePath"]?.string else {
            throw MCPToolError("Missing required parameters: action and filePath")
        }
        let lowered = action.lowercased()
        guard ["list_languages", "read_key", "add_translation", "validate"].contains(lowered) else {
            throw MCPToolError("Unsupported action '\(action)'. Valid: list_languages, read_key, add_translation, validate")
        }
        let fileURL = try resolveFileReadingPath(filePath, in: s)
        let ext = fileURL.pathExtension.lowercased()
        guard ["strings", "xcstrings", "stringsdict"].contains(ext) else {
            throw MCPToolError("Unsupported localization file type '\(ext)'. Expected .strings, .stringsdict, or .xcstrings.")
        }
        if lowered == "list_languages" {
            return try assetsListLanguages(fileURL: fileURL, ext: ext, root: Self.folder(of: s.model))
        }
        if lowered == "validate" {
            return try assetsValidateLocalizationFile(fileURL: fileURL, ext: ext)
        }
        // read_key / add_translation
        switch ext {
        case "xcstrings":
            return try await assetsManageXCStrings(fileURL: fileURL, action: lowered, call: call, s: s)
        case "stringsdict":
            return try assetsManageStringsDict(fileURL: fileURL, action: lowered, call: call)
        default:
            return try await assetsManageStrings(fileURL: fileURL, filePath: filePath, action: lowered, call: call, s: s)
        }
    }

    func assetsListLanguages(fileURL: URL, ext: String, root: URL) throws -> MCPToolResult {
        var languages = Set<String>()
        if ext == "xcstrings",
           let data = try? Data(contentsOf: fileURL),
           let catalog = try? StringCatalog(data: data) {
            for (_, entry) in catalog.json["strings"]?.objectPairs ?? [] {
                for (lang, _) in entry["localizations"]?.objectPairs ?? [] { languages.insert(lang) }
            }
            languages.insert(catalog.sourceLanguage)
        } else if let own = Self.assetsLocaleFor(url: fileURL) {
            languages.insert(own)
        }
        // Sibling locale files (en.lproj, es.lproj, …) in the workspace.
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                let last = url.lastPathComponent
                if (last == "Localizable.strings" || last == "Localizable.xcstrings" || last == "InfoPlist.strings"),
                   let lang = Self.assetsLocaleFor(url: url) {
                    languages.insert(lang)
                }
            }
        }
        guard !languages.isEmpty else {
            throw MCPToolError("No languages found. The file '\(fileURL.lastPathComponent)' has no detectable locales.")
        }
        let sorted = languages.sorted()
        return .structured(["languages": .string(sorted.joined(separator: ",")), "count": .int(sorted.count)],
                           summary: "Languages (\(sorted.count)): \(sorted.joined(separator: ", "))")
    }

    func assetsValidateLocalizationFile(fileURL: URL, ext: String) throws -> MCPToolResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MCPToolError("File does not exist at: \(fileURL.lastPathComponent)")
        }
        switch ext {
        case "xcstrings":
            guard let data = try? Data(contentsOf: fileURL),
                  let catalog = try? StringCatalog(data: data) else {
                throw MCPToolError("Validation failed: \(fileURL.lastPathComponent) is not valid JSON.")
            }
            guard let stringsJSON = catalog.json["strings"], case .object = stringsJSON else {
                throw MCPToolError("Validation failed: \(fileURL.lastPathComponent) is JSON but has no 'strings' dictionary.")
            }
            return .text("Validation passed for \(fileURL.lastPathComponent). Valid String Catalog with \(catalog.keys.count) key(s).")
        case "stringsdict":
            guard let data = try? Data(contentsOf: fileURL),
                  let _ = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
                throw MCPToolError("Validation failed: \(fileURL.lastPathComponent) is not a valid property list.")
            }
            return .text("Validation passed for \(fileURL.lastPathComponent). Valid property list.")
        default: // strings
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                throw MCPToolError("Cannot read \(fileURL.lastPathComponent)")
            }
            let lines = content.components(separatedBy: .newlines)
            var keyCount = 0
            var syntaxErrors: [String] = []
            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed.hasPrefix("/*") || trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { continue }
                if trimmed.hasPrefix("\"") {
                    if !trimmed.hasSuffix(";") {
                        syntaxErrors.append("Line \(idx + 1): missing terminating semicolon ';'")
                    } else if Self.assetsParseStringsLine(line) == nil {
                        syntaxErrors.append("Line \(idx + 1): malformed key = value entry")
                    } else {
                        keyCount += 1
                    }
                }
            }
            if syntaxErrors.isEmpty {
                return .text("Validation passed for \(fileURL.lastPathComponent). Contains \(keyCount) localized entries with no syntax errors.")
            }
            throw MCPToolError("Validation errors in \(fileURL.lastPathComponent):\n" + syntaxErrors.joined(separator: "\n"))
        }
    }

    func assetsManageStrings(fileURL: URL, filePath: String, action: String, call: MCPToolCall, s: WorkspaceSession) async throws -> MCPToolResult {
        if action == "add_translation" {
            guard let key = call.arguments["key"]?.string, !key.isEmpty,
                  let translation = call.arguments["translation"]?.string else {
                throw MCPToolError("key and translation parameters are required for add_translation")
            }
            var lines: [String] = []
            if FileManager.default.fileExists(atPath: fileURL.path) {
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                    throw MCPToolError("Failed to read localization file: \(fileURL.lastPathComponent)")
                }
                lines = content.components(separatedBy: "\n")
            }
            let newLine = "\"\(Self.assetsEscape(key))\" = \"\(Self.assetsEscape(translation))\";"
            var replaced = false
            for (index, line) in lines.enumerated() {
                if let parsed = Self.assetsParseStringsLine(line), parsed.key == key {
                    lines[index] = newLine
                    replaced = true
                    break
                }
            }
            if !replaced { lines.append(newLine) }
            let proposed = lines.joined(separator: "\n")
            try await commit(MCPChange(tool: call.name, path: fileURL.path, relativePath: relative(fileURL.path, in: s),
                                       original: text(of: fileURL), proposed: proposed,
                                       summary: "\(replaced ? "Update" : "Add") translation for '\(key)' in \(relative(fileURL.path, in: s))"),
                             call: call, session: s)
            guard let verify = try? String(contentsOf: fileURL, encoding: .utf8), verify.contains(newLine) else {
                throw MCPToolError("Verification failed: key not present after write.")
            }
            return .text("Successfully \(replaced ? "updated" : "added") translation for '\(key)' in \(fileURL.lastPathComponent).")
        }
        // read_key
        guard let key = call.arguments["key"]?.string, !key.isEmpty else {
            throw MCPToolError("key parameter is required for read_key")
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MCPToolError("Localization file does not exist at: \(filePath)")
        }
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            throw MCPToolError("Failed to read localization file: \(filePath)")
        }
        for line in content.components(separatedBy: .newlines) {
            if let parsed = Self.assetsParseStringsLine(line), parsed.key == key {
                return .text("Found localization: \"\(parsed.key)\" = \"\(parsed.value)\";")
            }
        }
        throw MCPToolError("Key '\(key)' not found in \(filePath)")
    }

    func assetsManageStringsDict(fileURL: URL, action: String, call: MCPToolCall) throws -> MCPToolResult {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw MCPToolError("Failed to read \(fileURL.lastPathComponent) as a property list.")
        }
        if action == "read_key" {
            guard let key = call.arguments["key"]?.string, !key.isEmpty else {
                throw MCPToolError("key parameter is required for read_key")
            }
            guard let entry = plist[key] else {
                throw MCPToolError("Key '\(key)' not found in \(fileURL.lastPathComponent)")
            }
            return .text("Found localization entry for '\(key)': \(entry)")
        }
        // add_translation on a .stringsdict requires a plural/format-rule
        // dictionary, not a plain string; silently writing a plain string
        // would corrupt the format rules.
        throw MCPToolError("add_translation is not supported for .stringsdict files: entries are plural/format-rule dictionaries, not plain strings. Use the .xcstrings String Catalog (or a .strings file) for plain string translations.")
    }

    func assetsManageXCStrings(fileURL: URL, action: String, call: MCPToolCall, s: WorkspaceSession) async throws -> MCPToolResult {
        let locale = Self.assetsLocaleFor(url: fileURL) ?? "en"
        var catalog: StringCatalog
        if FileManager.default.fileExists(atPath: fileURL.path) {
            guard let data = try? Data(contentsOf: fileURL),
                  let parsed = try? StringCatalog(data: data) else {
                throw MCPToolError("Failed to read \(fileURL.lastPathComponent) as JSON.")
            }
            catalog = parsed
        } else {
            catalog = StringCatalog(sourceLanguage: "en")
        }
        if action == "read_key" {
            guard let key = call.arguments["key"]?.string, !key.isEmpty else {
                throw MCPToolError("key parameter is required for read_key")
            }
            guard let found = Self.assetsCatalogUnit(catalog, key: key, language: locale)?.value else {
                throw MCPToolError("Key '\(key)' not found for locale '\(locale)' in \(fileURL.lastPathComponent).")
            }
            return .structured(["key": .string(key), "value": .string(found), "locale": .string(locale), "file": .string(fileURL.lastPathComponent)],
                               summary: "Key '\(key)' (\(locale)) = \"\(found)\" in \(fileURL.lastPathComponent).")
        }
        // add_translation
        guard let key = call.arguments["key"]?.string, !key.isEmpty,
              let value = call.arguments["translation"]?.string else {
            throw MCPToolError("key and translation parameters are required for add_translation")
        }
        catalog.setTranslation(value, key: key, language: locale)
        let proposed = String(decoding: catalog.data(), as: UTF8.self)
        try await commit(MCPChange(tool: call.name, path: fileURL.path, relativePath: relative(fileURL.path, in: s),
                                   original: text(of: fileURL), proposed: proposed,
                                   summary: "Add translation for '\(key)' (\(locale)) in \(relative(fileURL.path, in: s))"),
                         call: call, session: s)
        return .text("Successfully added translation for '\(key)' (\(locale)) in \(fileURL.lastPathComponent).")
    }
}

extension SwiftCodeMCPHost {
    // MARK: - localize_app

    func assetsLocalizeApp(_ call: MCPToolCall) async throws -> MCPToolResult {
        let action = (call.arguments["action"]?.string ?? "localize").lowercased()
        guard action == "localize" || action == "status" || action == "set_development_region" else {
            throw MCPToolError("Invalid action '\(action)'. Expected localize, status, or set_development_region.")
        }
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw MCPToolError("Workspace root is not accessible.")
        }
        switch action {
        case "status":
            return try assetsLocalizeStatus(root: root, s: s)
        case "set_development_region":
            let region = (call.arguments["development_region"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !region.isEmpty else {
                throw MCPToolError("Missing required parameter: development_region for action=set_development_region.")
            }
            guard Self.assetsIsValidLanguageCode(region) else {
                throw MCPToolError("Invalid language code '\(region)'. Expected 2-3 letters with an optional -Region suffix (e.g. en, es, pt-BR, zh-Hans).")
            }
            return try await assetsLocalizeSetRegion(region, root: root, s: s, call: call)
        default:
            let languages = try Self.assetsValidatedLanguages(call.arguments["languages"]?.array)
            var region = (call.arguments["development_region"]?.string ?? "en").trimmingCharacters(in: .whitespacesAndNewlines)
            if region.isEmpty { region = "en" }
            guard Self.assetsIsValidLanguageCode(region) else {
                throw MCPToolError("Invalid development_region '\(region)'. Expected a language code such as en.")
            }
            let translations = Self.assetsNormalizedTranslations(call.arguments["translations"]?.object)
            return try await assetsLocalize(root: root, s: s, call: call, languages: languages, translations: translations, developmentRegion: region)
        }
    }

    func assetsLocalize(root: URL, s: WorkspaceSession, call: MCPToolCall, languages: [String], translations: [String: [String: String]], developmentRegion: String) async throws -> MCPToolResult {
        let plistURL = Self.assetsFindInfoPlist(in: root)
        let targetDir = plistURL?.deletingLastPathComponent() ?? root
        let discovered = Self.assetsDiscoverLocalizableKeys(in: targetDir)
        guard !discovered.keys.isEmpty else {
            throw MCPToolError("No localizable strings found in Swift sources under '\(relative(targetDir.path, in: s))'. Wrap user-facing text in NSLocalizedString(_:comment:) or String(localized:) first.")
        }
        let catalogURL = Self.assetsFindCatalog(named: "Localizable.xcstrings", in: targetDir) ?? targetDir.appendingPathComponent("Localizable.xcstrings")
        var catalog: StringCatalog
        if let data = try? Data(contentsOf: catalogURL), let parsed = try? StringCatalog(data: data) {
            catalog = parsed
        } else {
            // Missing or invalid existing catalog starts from an empty
            // one (Legacy's `readCatalog ?? [:]`).
            catalog = StringCatalog(sourceLanguage: developmentRegion)
        }
        let merge = Self.assetsMergeCatalog(&catalog, sourceLanguage: developmentRegion, keys: discovered.keys, languages: languages, translations: translations)
        let proposed = String(decoding: catalog.data(), as: UTF8.self)
        try await commit(MCPChange(tool: call.name, path: catalogURL.path, relativePath: relative(catalogURL.path, in: s),
                                   original: text(of: catalogURL), proposed: proposed,
                                   summary: "Localize into \(languages.joined(separator: ", ")) — String Catalog \(relative(catalogURL.path, in: s))"),
                         call: call, session: s)
        guard Self.assetsVerifyCatalog(at: catalogURL, keys: discovered.keys, languages: languages) else {
            throw MCPToolError("Verification failed: the String Catalog was not written correctly.")
        }
        var plistNote = "No Info.plist found; CFBundleLocalizations was not updated."
        if let plistURL {
            guard var dict = Self.assetsReadPlist(at: plistURL) else {
                throw MCPToolError("Wrote the String Catalog but failed to update Info.plist at '\(plistURL.lastPathComponent)'.")
            }
            dict["CFBundleLocalizations"] = languages
            dict["CFBundleDevelopmentRegion"] = developmentRegion
            guard let plistText = Self.assetsPlistText(dict) else {
                throw MCPToolError("Wrote the String Catalog but failed to update Info.plist at '\(plistURL.lastPathComponent)'.")
            }
            try await commit(MCPChange(tool: call.name, path: plistURL.path, relativePath: relative(plistURL.path, in: s),
                                       original: text(of: plistURL), proposed: plistText,
                                       summary: "Set CFBundleLocalizations in \(relative(plistURL.path, in: s))"),
                             call: call, session: s)
            guard let verify = Self.assetsReadPlist(at: plistURL),
                  (verify["CFBundleLocalizations"] as? [String]) == languages,
                  (verify["CFBundleDevelopmentRegion"] as? String) == developmentRegion else {
                throw MCPToolError("Wrote the String Catalog but failed to update Info.plist at '\(plistURL.lastPathComponent)'.")
            }
            plistNote = "Info.plist updated: CFBundleLocalizations=[\(languages.joined(separator: ", "))], CFBundleDevelopmentRegion=\(developmentRegion)."
        }
        let rtlLanguages = languages.filter(Self.assetsIsRightToLeft)
        let direction = rtlLanguages.isEmpty ? "ltr" : "rtl"
        var summary = "Localized app into \(languages.count) language(s): \(languages.joined(separator: ", ")).\n"
        summary += "- Discovered \(discovered.keys.count) localizable key(s) in \(discovered.filesScanned) Swift file(s)."
        if discovered.skippedTableKeys > 0 {
            summary += " (\(discovered.skippedTableKeys) key(s) use a non-Localizable table and were skipped.)"
        }
        summary += "\n- String Catalog: \(relative(catalogURL.path, in: s)) — \(merge.totalKeys) key(s), \(merge.added) new localization(s) added, \(merge.updated) updated with supplied translations."
        summary += "\n- \(plistNote)"
        summary += "\n- Layout direction: \(direction)\(rtlLanguages.isEmpty ? "" : " (RTL languages: \(rtlLanguages.joined(separator: ", ")))")."
        if let plistURL, let note = Self.assetsInfoPlistLocalizationNote(plistURL: plistURL) {
            summary += "\n- Note: \(note)"
        }
        summary += "\nNext: call localization_audit to find keys still missing per locale."
        return .structured(["count": .int(discovered.keys.count), "path": .string(relative(catalogURL.path, in: s)),
                            "languages": .string(languages.joined(separator: ",")), "layoutDirection": .string(direction),
                            "sourceLanguage": .string(developmentRegion), "keysAdded": .int(merge.added)],
                           summary: summary)
    }

    func assetsLocalizeStatus(root: URL, s: WorkspaceSession) throws -> MCPToolResult {
        let targetDir = Self.assetsFindInfoPlist(in: root)?.deletingLastPathComponent() ?? root
        let discovered = Self.assetsDiscoverLocalizableKeys(in: targetDir)
        let catalogURL = Self.assetsFindCatalog(named: "Localizable.xcstrings", in: targetDir)
        var catalogInfo = "absent"
        var catalogLanguages: [String] = []
        var catalogSourceLanguage: String? = nil
        if let catalogURL,
           let data = try? Data(contentsOf: catalogURL),
           let catalog = try? StringCatalog(data: data),
           let stringsJSON = catalog.json["strings"], case .object = stringsJSON {
            var langSet = Set<String>()
            for (_, entry) in catalog.json["strings"]?.objectPairs ?? [] {
                for (lang, _) in entry["localizations"]?.objectPairs ?? [] { langSet.insert(lang) }
            }
            catalogLanguages = langSet.sorted()
            catalogInfo = "present (\(catalog.keys.count) keys, languages: \(catalogLanguages.joined(separator: ", ")))"
            catalogSourceLanguage = catalog.sourceLanguage
        }
        var plistInfo = "No Info.plist found."
        if let plistURL = Self.assetsFindInfoPlist(in: root), let dict = Self.assetsReadPlist(at: plistURL) {
            let localizations = (dict["CFBundleLocalizations"] as? [String])?.joined(separator: ", ") ?? "not set"
            let region = dict["CFBundleDevelopmentRegion"] as? String ?? "not set"
            plistInfo = "\(plistURL.lastPathComponent): CFBundleLocalizations=[\(localizations)], CFBundleDevelopmentRegion=\(region)."
        }
        let summary = "Localization status:\n- Discovered keys in Swift: \(discovered.keys.count)\n- String Catalog: \(catalogInfo)\n- \(plistInfo)"
        return .structured(["count": .int(discovered.keys.count), "languages": .string(catalogLanguages.joined(separator: ",")),
                            "layoutDirection": .string(catalogLanguages.contains(where: Self.assetsIsRightToLeft) ? "rtl" : "ltr"),
                            "sourceLanguage": .string(catalogSourceLanguage ?? "unknown")],
                           summary: summary)
    }

    func assetsLocalizeSetRegion(_ region: String, root: URL, s: WorkspaceSession, call: MCPToolCall) async throws -> MCPToolResult {
        guard let plistURL = Self.assetsFindInfoPlist(in: root) else {
            throw MCPToolError("No Info.plist found in the workspace; cannot set the development region.")
        }
        guard var dict = Self.assetsReadPlist(at: plistURL) else {
            throw MCPToolError("Info.plist at '\(plistURL.lastPathComponent)' is not a valid property list dictionary.")
        }
        let before = dict["CFBundleDevelopmentRegion"] as? String ?? "not set"
        dict["CFBundleDevelopmentRegion"] = region
        guard let plistText = Self.assetsPlistText(dict) else {
            throw MCPToolError("Failed to set CFBundleDevelopmentRegion in Info.plist.")
        }
        try await commit(MCPChange(tool: call.name, path: plistURL.path, relativePath: relative(plistURL.path, in: s),
                                   original: text(of: plistURL), proposed: plistText,
                                   summary: "Set CFBundleDevelopmentRegion to '\(region)' in \(relative(plistURL.path, in: s))"),
                         call: call, session: s)
        guard let verify = Self.assetsReadPlist(at: plistURL),
              (verify["CFBundleDevelopmentRegion"] as? String) == region else {
            throw MCPToolError("Failed to set CFBundleDevelopmentRegion in Info.plist.")
        }
        var note = ""
        let targetDir = plistURL.deletingLastPathComponent()
        if let catalogURL = Self.assetsFindCatalog(named: "Localizable.xcstrings", in: targetDir),
           let data = try? Data(contentsOf: catalogURL),
           var catalog = try? StringCatalog(data: data) {
            catalog.json["sourceLanguage"] = .string(region)
            let catalogText = String(decoding: catalog.data(), as: UTF8.self)
            // Legacy ignores a catalog write failure here; a review
            // refusal of the catalog change is ignored the same way —
            // the plist change stands either way.
            do {
                try await commit(MCPChange(tool: call.name, path: catalogURL.path, relativePath: relative(catalogURL.path, in: s),
                                           original: text(of: catalogURL), proposed: catalogText,
                                           summary: "Set String Catalog source language to \(region)"),
                                 call: call, session: s)
                note = " Also set the String Catalog source language to \(region)."
            } catch {
                // Deliberately ignored, as in Legacy.
            }
        }
        return .structured(["path": .string(relative(plistURL.path, in: s)), "sourceLanguage": .string(region)],
                           summary: "Set CFBundleDevelopmentRegion to '\(region)' (was: \(before)).\(note)")
    }

    // MARK: - localize_app validation / discovery / merge

    nonisolated static func assetsValidatedLanguages(_ value: [AnyJSON]?) throws -> [String] {
        guard let raw = value, !raw.isEmpty else {
            throw MCPToolError("Missing required parameter: languages (1-3 language codes, e.g. [\"es\",\"fr\",\"de\"]).")
        }
        var seen = Set<String>()
        var languages: [String] = []
        for item in raw {
            let code = (item.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty, assetsIsValidLanguageCode(code) else {
                throw MCPToolError("Invalid language code '\(code)'. Expected 2-3 letters with an optional -Region suffix (e.g. en, es, pt-BR, zh-Hans).")
            }
            if seen.insert(code).inserted { languages.append(code) }
        }
        guard !languages.isEmpty else {
            throw MCPToolError("Missing required parameter: languages (1-3 language codes).")
        }
        guard languages.count <= 3 else {
            throw MCPToolError("Too many languages (\(languages.count)). Maximum 3 languages per Assist session; run again for more.")
        }
        return languages
    }

    nonisolated static func assetsIsValidLanguageCode(_ code: String) -> Bool {
        code.range(of: "^[A-Za-z]{2,3}(-[A-Za-z]{2,4})?$", options: .regularExpression) != nil
    }

    nonisolated static func assetsIsRightToLeft(_ code: String) -> Bool {
        let base = code.split(separator: "-").first.map(String.init) ?? code
        return ["ar", "he", "fa", "ur"].contains(base.lowercased())
    }

    nonisolated static func assetsNormalizedTranslations(_ value: [String: AnyJSON]?) -> [String: [String: String]] {
        guard let dict = value else { return [:] }
        var result: [String: [String: String]] = [:]
        for (key, inner) in dict where !key.isEmpty {
            guard let innerDict = inner.object else { continue }
            var converted: [String: String] = [:]
            for (lang, text) in innerDict {
                if let text = text.string { converted[lang] = text }
            }
            if !converted.isEmpty { result[key] = converted }
        }
        return result
    }

    /// Legacy's key discovery, verbatim: `NSLocalizedString("key" …)`
    /// with an optional `tableName:` (a non-`Localizable`, non-empty
    /// table is skipped and counted), and `String(localized: "key" …)`.
    nonisolated static func assetsDiscoverLocalizableKeys(in targetDir: URL) -> (keys: Set<String>, skippedTableKeys: Int, filesScanned: Int) {
        var keys = Set<String>()
        var skippedTableKeys = 0
        var filesScanned = 0
        guard let enumerator = FileManager.default.enumerator(at: targetDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return (keys, skippedTableKeys, filesScanned)
        }
        let nsRegex = try? NSRegularExpression(pattern: #"NSLocalizedString\s*\(\s*"((?:[^"\\]|\\.)*)"\s*(?:,\s*tableName:\s*(?:"((?:[^"\\]|\\.)*)"|nil))?"#)
        let localizedRegex = try? NSRegularExpression(pattern: #"String\s*\(\s*localized:\s*"((?:[^"\\]|\\.)*)""#)
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let path = url.path
            if path.contains("/build/") || path.contains("/DerivedData/") || path.contains("/.build/")
                || path.contains("/Pods/") || path.contains("/.swiftpm/") { continue }
            guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber,
                  size.intValue < 2_000_000,
                  let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else { continue }
            filesScanned += 1
            let range = NSRange(text.startIndex..., in: text)
            if let nsRegex {
                for match in nsRegex.matches(in: text, range: range) {
                    guard let keyRange = Range(match.range(at: 1), in: text) else { continue }
                    let key = assetsUnescapeStringLiteral(String(text[keyRange]))
                    guard !key.isEmpty else { continue }
                    if match.range(at: 2).location != NSNotFound,
                       let tableRange = Range(match.range(at: 2), in: text) {
                        let table = String(text[tableRange])
                        if !table.isEmpty, table != "Localizable" {
                            skippedTableKeys += 1
                            continue
                        }
                    }
                    keys.insert(key)
                }
            }
            if let localizedRegex {
                for match in localizedRegex.matches(in: text, range: range) {
                    guard let keyRange = Range(match.range(at: 1), in: text) else { continue }
                    let key = assetsUnescapeStringLiteral(String(text[keyRange]))
                    if !key.isEmpty { keys.insert(key) }
                }
            }
        }
        return (keys, skippedTableKeys, filesScanned)
    }

    nonisolated static func assetsUnescapeStringLiteral(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
    }

    /// Legacy's catalog merge, through the `StringCatalog` seam: the
    /// source language always carries the key itself as the source
    /// text; target languages get a supplied translation
    /// (`translated`) or a `"new"`-state placeholder unit with an
    /// empty value. Added/updated counts follow Legacy exactly.
    nonisolated static func assetsMergeCatalog(_ catalog: inout StringCatalog, sourceLanguage: String, keys: Set<String>, languages: [String], translations: [String: [String: String]]) -> (added: Int, updated: Int, totalKeys: Int) {
        catalog.json["sourceLanguage"] = .string(sourceLanguage)
        catalog.json["version"] = .string("1.0")
        var added = 0
        var updated = 0
        for key in keys.sorted() {
            if assetsCatalogUnit(catalog, key: key, language: sourceLanguage) == nil {
                catalog.setTranslation(key, key: key, language: sourceLanguage)
                added += 1
            }
            for language in languages where language != sourceLanguage {
                if let translation = translations[key]?[language], !translation.isEmpty {
                    let existing = assetsCatalogUnit(catalog, key: key, language: language)
                    if existing?.value == translation, existing?.state == "translated" { continue }
                    if existing != nil { updated += 1 } else { added += 1 }
                    catalog.setTranslation(translation, key: key, language: language)
                } else if assetsCatalogUnit(catalog, key: key, language: language) == nil {
                    // A "new" placeholder unit has no `StringCatalog`
                    // setter, so it is built on the seam's own JSON
                    // model directly.
                    var strings = catalog.json["strings"] ?? .object([])
                    var entry = strings[key] ?? .object([])
                    var locs = entry["localizations"] ?? .object([])
                    locs[language] = .object([("stringUnit", .object([("state", .string("new")), ("value", .string(""))]))])
                    entry["localizations"] = locs
                    strings[key] = entry
                    catalog.json["strings"] = strings
                    added += 1
                }
            }
        }
        return (added, updated, catalog.keys.count)
    }

    nonisolated static func assetsVerifyCatalog(at url: URL, keys: Set<String>, languages: [String]) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let catalog = try? StringCatalog(data: data) else { return false }
        for key in keys {
            guard catalog.json["strings"]?[key]?["localizations"] != nil else { return false }
            for language in languages {
                guard catalog.json["strings"]?[key]?["localizations"]?[language] != nil else { return false }
            }
        }
        return true
    }

    nonisolated static func assetsInfoPlistLocalizationNote(plistURL: URL) -> String? {
        guard let dict = assetsReadPlist(at: plistURL) else { return nil }
        let candidates = ["CFBundleName", "CFBundleDisplayName"].filter { dict[$0] != nil }
        guard !candidates.isEmpty else { return nil }
        return "Info.plist keys \(candidates.joined(separator: ", ")) are best localized with InfoPlist.strings tables (see LocalizingApps.md), not the Localizable catalog."
    }

    // MARK: - string_catalog_migrator

    func assetsMigrateStringCatalog(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let srcPath = call.arguments["sourceStringsPath"]?.string else {
            throw MCPToolError("Missing required parameter: sourceStringsPath")
        }
        guard let dstPath = call.arguments["targetXcstringsPath"]?.string else {
            throw MCPToolError("Missing required parameter: targetXcstringsPath")
        }
        let srcURL = try resolveFileReadingPath(srcPath, in: s)
        guard FileManager.default.fileExists(atPath: srcURL.path) else {
            throw MCPToolError("Source .strings file not found: \(srcPath)")
        }
        guard let content = try? String(contentsOf: srcURL, encoding: .utf8) else {
            throw MCPToolError("Unable to read .strings content at \(srcPath)")
        }
        // Legacy's regex, verbatim: escaped characters are kept raw.
        let regex = try? NSRegularExpression(pattern: #""([^"\\]*(?:\\.[^"\\]*)*)"\s*=\s*"([^"\\]*(?:\\.[^"\\]*)*)";"#)
        var catalog = StringCatalog(sourceLanguage: "en")
        let nsContent = content as NSString
        if let matches = regex?.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length)) {
            for match in matches {
                let key = nsContent.substring(with: match.range(at: 1))
                let value = nsContent.substring(with: match.range(at: 2))
                catalog.addKey(key)
                catalog.setTranslation(value, key: key, language: "en")
            }
        }
        let dstURL = try resolveFileReadingPath(dstPath, in: s)
        let proposed = String(decoding: catalog.data(), as: UTF8.self)
        try await commit(MCPChange(tool: call.name, path: dstURL.path, relativePath: relative(dstURL.path, in: s),
                                   original: text(of: dstURL), proposed: proposed,
                                   summary: "Migrate \(srcPath) to String Catalog \(dstPath)"),
                         call: call, session: s)
        return .text("Successfully migrated \(catalog.keys.count) localization keys from `\(srcPath)` to String Catalog `\(dstPath)`.")
    }

    // MARK: - strings_file_validate

    func assetsValidateStringsFile(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        guard let raw = call.arguments["path"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            throw MCPToolError("Missing required parameter: path")
        }
        let url: URL
        do {
            url = try resolveFileReadingPath(raw, in: s)
        } catch {
            throw MCPToolError("Cannot read file at: \(raw)")
        }
        guard let data = try? Data(contentsOf: url) else {
            throw MCPToolError("Cannot read file at: \(raw)")
        }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? ""
        guard !text.isEmpty else { throw MCPToolError("File is empty or undecodable: \(raw)") }
        let entryPattern = try? NSRegularExpression(pattern: #"^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$"#)
        var seen: Set<String> = []
        var duplicates: [String] = []
        var malformed: [(Int, String)] = []
        var emptyValues: [String] = []
        var validCount = 0
        for (i, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") || line.hasPrefix("/*") { continue }
            guard let p = entryPattern,
                  let m = p.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let kr = Range(m.range(at: 1), in: line),
                  let vr = Range(m.range(at: 2), in: line) else {
                malformed.append((i + 1, String(line.prefix(100))))
                continue
            }
            validCount += 1
            let key = String(line[kr])
            if seen.contains(key) { duplicates.append(key) } else { seen.insert(key) }
            if String(line[vr]).isEmpty { emptyValues.append(key) }
        }
        var lines = ["Strings validation for \(raw):", "- Valid entries: \(validCount)", "- Duplicate keys: \(duplicates.count)", "- Malformed lines: \(malformed.count)", "- Empty values: \(emptyValues.count)"]
        for d in duplicates.prefix(20) { lines.append("  DUPLICATE: \(d)") }
        for (n, l) in malformed.prefix(20) { lines.append("  MALFORMED line \(n): \(l)") }
        for e in emptyValues.prefix(20) { lines.append("  EMPTY VALUE: \(e)") }
        let ok = duplicates.isEmpty && malformed.isEmpty
        return .structured(["valid": .int(validCount), "duplicates": .int(duplicates.count),
                            "malformed": .int(malformed.count), "emptyValues": .int(emptyValues.count),
                            "passed": .bool(ok)],
                           summary: lines.joined(separator: "\n"))
    }

    // MARK: - strings_localization

    func assetsStringsLocalization(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let key = call.arguments["key"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw MCPToolError("Missing required parameter: key")
        }
        let action = ((call.arguments["action"]?.string) ?? "get").lowercased()
        guard action == "get" || action == "set" || action == "delete" else {
            throw MCPToolError("Invalid action '\(action)': must be get, set, or delete.")
        }
        if action == "set" {
            guard let value = call.arguments["value"]?.string, !value.isEmpty else {
                throw MCPToolError("Missing required parameter: value for set action.")
            }
        }
        let locale = ((call.arguments["locale"]?.string) ?? "en").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !locale.isEmpty, !locale.contains("/"), !locale.contains("..") else {
            throw MCPToolError("Invalid locale.")
        }
        let root = Self.folder(of: s.model)
        let fileURL: URL
        if let rawPath = call.arguments["path"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPath.isEmpty {
            guard let resolved = Self.assetsStrictResolve(rawPath, root: root) else {
                throw MCPToolError("Invalid path '\(rawPath)': must be inside the workspace and must not contain '..'.")
            }
            guard FileManager.default.fileExists(atPath: resolved.path) else {
                throw MCPToolError("Localization file not found at '\(rawPath)'.")
            }
            fileURL = resolved
        } else if let found = Self.assetsFindLocalizationFile(locale: locale, root: root) {
            fileURL = found
        } else {
            throw MCPToolError("No Localizable.strings or Localizable.xcstrings found for locale '\(locale)'. Pass path to a specific file.")
        }
        if fileURL.pathExtension == "xcstrings" {
            return try await assetsStringsLocalizationXCStrings(fileURL: fileURL, action: action, key: key, call: call, s: s, locale: locale)
        }
        if fileURL.pathExtension == "strings" {
            return try await assetsStringsLocalizationStrings(fileURL: fileURL, action: action, key: key, call: call, s: s)
        }
        throw MCPToolError("Unsupported localization file type: \(fileURL.lastPathComponent). Expected .strings or .xcstrings.")
    }

    func assetsStringsLocalizationStrings(fileURL: URL, action: String, key: String, call: MCPToolCall, s: WorkspaceSession) async throws -> MCPToolResult {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            throw MCPToolError("Failed to read \(fileURL.lastPathComponent).")
        }
        var lines = content.components(separatedBy: "\n")
        var foundIndex: Int?
        var foundValue: String?
        for (index, line) in lines.enumerated() {
            if let parsed = Self.assetsParseStringsLine(line), parsed.key == key {
                foundIndex = index
                foundValue = parsed.value
                break
            }
        }
        if action == "get" {
            if let foundValue = foundValue {
                return .structured(["key": .string(key), "value": .string(foundValue), "file": .string(fileURL.lastPathComponent)],
                                   summary: "Key '\(key)' = \"\(foundValue)\" in \(fileURL.lastPathComponent).")
            }
            throw MCPToolError("Key '\(key)' not found in \(fileURL.lastPathComponent).")
        }
        if action == "set" {
            let value = call.arguments["value"]?.string ?? ""
            let newLine = "\"\(Self.assetsEscape(key))\" = \"\(Self.assetsEscape(value))\";"
            if let foundIndex = foundIndex {
                lines[foundIndex] = newLine
            } else {
                lines.append(newLine)
            }
            let updated = lines.joined(separator: "\n")
            try await commit(MCPChange(tool: call.name, path: fileURL.path, relativePath: relative(fileURL.path, in: s),
                                       original: content, proposed: updated,
                                       summary: "Set key '\(key)' in \(relative(fileURL.path, in: s))"),
                             call: call, session: s)
            guard let verify = try? String(contentsOf: fileURL, encoding: .utf8),
                  verify.contains("\"\(Self.assetsEscape(key))\" = \"\(Self.assetsEscape(value))\";") else {
                throw MCPToolError("Verification failed: key not present after write.")
            }
            return .structured(["key": .string(key), "value": .string(value), "file": .string(fileURL.lastPathComponent)],
                               summary: "Set key '\(key)' in \(fileURL.lastPathComponent).")
        }
        // delete
        guard let foundIndex = foundIndex else {
            throw MCPToolError("Key '\(key)' not found in \(fileURL.lastPathComponent).")
        }
        lines.remove(at: foundIndex)
        let updated = lines.joined(separator: "\n")
        try await commit(MCPChange(tool: call.name, path: fileURL.path, relativePath: relative(fileURL.path, in: s),
                                   original: content, proposed: updated,
                                   summary: "Delete key '\(key)' from \(relative(fileURL.path, in: s))"),
                         call: call, session: s)
        return .structured(["key": .string(key), "file": .string(fileURL.lastPathComponent)],
                           summary: "Deleted key '\(key)' from \(fileURL.lastPathComponent).")
    }

    func assetsStringsLocalizationXCStrings(fileURL: URL, action: String, key: String, call: MCPToolCall, s: WorkspaceSession, locale: String) async throws -> MCPToolResult {
        guard let data = try? Data(contentsOf: fileURL),
              var catalog = try? StringCatalog(data: data) else {
            throw MCPToolError("Failed to read \(fileURL.lastPathComponent) as JSON.")
        }
        if action == "get" {
            guard let found = Self.assetsCatalogUnit(catalog, key: key, language: locale)?.value else {
                throw MCPToolError("Key '\(key)' not found for locale '\(locale)' in \(fileURL.lastPathComponent).")
            }
            return .structured(["key": .string(key), "value": .string(found), "locale": .string(locale), "file": .string(fileURL.lastPathComponent)],
                               summary: "Key '\(key)' (\(locale)) = \"\(found)\" in \(fileURL.lastPathComponent).")
        }
        if action == "set" {
            let value = call.arguments["value"]?.string ?? ""
            catalog.setTranslation(value, key: key, language: locale)
            let proposed = String(decoding: catalog.data(), as: UTF8.self)
            try await commit(MCPChange(tool: call.name, path: fileURL.path, relativePath: relative(fileURL.path, in: s),
                                       original: text(of: fileURL), proposed: proposed,
                                       summary: "Set key '\(key)' (\(locale)) in \(relative(fileURL.path, in: s))"),
                             call: call, session: s)
            return .structured(["key": .string(key), "value": .string(value), "locale": .string(locale), "file": .string(fileURL.lastPathComponent)],
                               summary: "Set key '\(key)' (\(locale)) in \(fileURL.lastPathComponent).")
        }
        // delete
        guard var strings = catalog.json["strings"],
              var entry = strings[key],
              var localizations = entry["localizations"],
              localizations[locale] != nil else {
            throw MCPToolError("Key '\(key)' not found for locale '\(locale)' in \(fileURL.lastPathComponent).")
        }
        localizations[locale] = nil
        if localizations.objectPairs.isEmpty {
            strings[key] = nil
        } else {
            entry["localizations"] = localizations
            strings[key] = entry
        }
        catalog.json["strings"] = strings
        let proposed = String(decoding: catalog.data(), as: UTF8.self)
        try await commit(MCPChange(tool: call.name, path: fileURL.path, relativePath: relative(fileURL.path, in: s),
                                   original: text(of: fileURL), proposed: proposed,
                                   summary: "Delete key '\(key)' (\(locale)) from \(relative(fileURL.path, in: s))"),
                         call: call, session: s)
        return .structured(["key": .string(key), "locale": .string(locale), "file": .string(fileURL.lastPathComponent)],
                           summary: "Deleted key '\(key)' (\(locale)) from \(fileURL.lastPathComponent).")
    }

    /// Legacy's file discovery, in order: `<locale>.lproj/Localizable.strings`,
    /// `Localizable.xcstrings` (workspace root),
    /// `en.lproj/Localizable.strings`, `Localizable.strings` (workspace
    /// root), then the first `Localizable.strings` / `Localizable.xcstrings`
    /// found by enumerating the workspace.
    nonisolated static func assetsFindLocalizationFile(locale: String, root: URL) -> URL? {
        let candidates = [
            "\(locale).lproj/Localizable.strings",
            "Localizable.xcstrings",
            "en.lproj/Localizable.strings",
            "Localizable.strings"
        ]
        for candidate in candidates {
            let url = root.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator {
            if url.lastPathComponent == "Localizable.strings" || url.lastPathComponent == "Localizable.xcstrings" {
                return url
            }
        }
        return nil
    }
}

extension SwiftCodeMCPHost {
    // MARK: - Shared helpers

    /// Legacy's `resolvePath` / `AssistWorkspacePaths.resolve` rule:
    /// trim; reject empty and any `..` as text; an absolute path must
    /// equal the workspace root or sit under it; a relative path is
    /// appended to the root and must stay under it.
    nonisolated static func assetsStrictResolve(_ raw: String, root: URL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("..") else { return nil }
        let rootURL = root.standardizedFileURL
        if trimmed.hasPrefix("/") {
            let candidate = URL(fileURLWithPath: trimmed).standardizedFileURL
            guard candidate.path == rootURL.path || candidate.path.hasPrefix(rootURL.path + "/") else { return nil }
            return candidate
        }
        let candidate = rootURL.appendingPathComponent(trimmed).standardizedFileURL
        guard candidate.path == rootURL.path || candidate.path.hasPrefix(rootURL.path + "/") else { return nil }
        return candidate
    }

    /// The `.lproj` parent directory's language code, or nil.
    nonisolated static func assetsLocaleFor(url: URL) -> String? {
        let parent = url.deletingLastPathComponent().lastPathComponent
        if parent.hasSuffix(".lproj") {
            return String(parent.dropLast(".lproj".count))
        }
        return nil
    }

    /// Legacy's `.strings` line parser: skip blank / `//` / `/*` lines,
    /// split on the first `=`, strip a trailing `;`, unquote both sides.
    nonisolated static func assetsParseStringsLine(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") { return nil }
        guard let eqRange = trimmed.range(of: "=") else { return nil }
        let keyPart = trimmed[..<eqRange.lowerBound].trimmingCharacters(in: .whitespaces)
        let valuePart = trimmed[eqRange.upperBound...].trimmingCharacters(in: .whitespaces)
        guard let key = assetsUnquote(keyPart), let rawValue = assetsUnquote(valuePart) else { return nil }
        return (key: key, value: rawValue)
    }

    nonisolated static func assetsUnquote(_ text: String) -> String? {
        var value = String(text)
        if value.hasSuffix(";") {
            value = String(value.dropLast())
        }
        value = value.trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else { return nil }
        let inner = String(value.dropFirst().dropLast())
        return inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Legacy's `.strings` escaper: `\` → `\\`, `"` → `\"`, newline → `\n`.
    nonisolated static func assetsEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Legacy's `localization_audit` key scan of a `.strings` file.
    nonisolated static func assetsParseStringsKeys(at url: URL) -> Set<String> {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var keys: Set<String> = []
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") { continue }
            guard let eqRange = trimmed.range(of: "=") else { continue }
            let keyPart = trimmed[..<eqRange.lowerBound].trimmingCharacters(in: .whitespaces)
            var keyText = String(keyPart)
            if keyText.hasSuffix(";") { keyText = String(keyText.dropLast()) }
            keyText = keyText.trimmingCharacters(in: .whitespaces)
            if keyText.hasPrefix("\"") && keyText.hasSuffix("\"") && keyText.count >= 2 {
                let inner = String(keyText.dropFirst().dropLast())
                keys.insert(inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\"))
            }
        }
        return keys
    }

    /// Legacy's `localization_audit` xcstrings scan, through the
    /// `StringCatalog` seam: a key counts for a locale only when that
    /// key's entry has a `localizations` entry for the locale.
    nonisolated static func assetsXCStringsKeys(at url: URL) -> [String: Set<String>] {
        guard let data = try? Data(contentsOf: url),
              let catalog = try? StringCatalog(data: data) else { return [:] }
        var result: [String: Set<String>] = [:]
        for (key, entry) in catalog.json["strings"]?.objectPairs ?? [] {
            for (locale, _) in entry["localizations"]?.objectPairs ?? [] {
                result[locale, default: []].insert(key)
            }
        }
        return result
    }

    /// The `stringUnit` of one key/locale of a `StringCatalog`, or nil
    /// when there is no such unit. Legacy's read requires only the
    /// `value`; a unit without a `state` still counts.
    nonisolated static func assetsCatalogUnit(_ catalog: StringCatalog, key: String, language: String) -> (state: String?, value: String)? {
        guard let unit = catalog.json["strings"]?[key]?["localizations"]?[language]?["stringUnit"],
              let value = unit["value"]?.stringValue else { return nil }
        return (unit["state"]?.stringValue, value)
    }

    /// Legacy's `findInfoPlist`: the first `Info.plist` in the
    /// workspace (sorted by path), skipping `build`, `DerivedData`
    /// and `.build` paths.
    nonisolated static func assetsFindInfoPlist(in workspaceRoot: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: workspaceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        var candidates: [URL] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "Info.plist" else { continue }
            let path = url.path
            if path.contains("/build/") || path.contains("/DerivedData/") || path.contains("/.build/") { continue }
            candidates.append(url)
        }
        return candidates.sorted { $0.path < $1.path }.first
    }

    /// Legacy's `findCatalog`: the first file of the given name in the
    /// target directory (sorted by path), skipping `build` and
    /// `DerivedData` paths.
    nonisolated static func assetsFindCatalog(named name: String, in targetDir: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: targetDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        var candidates: [URL] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == name else { continue }
            if url.path.contains("/build/") || url.path.contains("/DerivedData/") { continue }
            candidates.append(url)
        }
        return candidates.sorted { $0.path < $1.path }.first
    }

    nonisolated static func assetsReadPlist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format) else { return nil }
        return plist as? [String: Any]
    }

    nonisolated static func assetsPlistText(_ dict: [String: Any]) -> String? {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
