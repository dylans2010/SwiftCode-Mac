import Foundation

public struct AssistAssetImageAddTool: AssistTool {
    public let id = "asset_image_add"
    public let name = "Add Asset Image"
    public let description = "Adds an image to an asset catalog by creating an .imageset with Contents.json and copying the source image."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Adds an image to an asset catalog.",
            properties: [
                "catalog": JSONSchema(type: "string", description: "Workspace-relative path to the .xcassets catalog (e.g. Assets.xcassets). Created if missing."),
                "imageName": JSONSchema(type: "string", description: "Name for the new image set (no slashes or '..')."),
                "sourcePath": JSONSchema(type: "string", description: "Workspace-relative path to the source image file inside the workspace.")
            ],
            required: ["catalog", "imageName", "sourcePath"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let catalogRaw = input["catalog"] as? String, !catalogRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: catalog")
        }
        guard let imageNameRaw = input["imageName"] as? String, !imageNameRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: imageName")
        }
        guard let sourceRaw = input["sourcePath"] as? String, !sourceRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: sourcePath")
        }
        let catalog = catalogRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageName = imageNameRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !catalog.hasSuffix(".xcassets") {
            return .failure("Invalid catalog '\(catalog)': must end with .xcassets.")
        }
        if imageName.contains("/") || imageName.contains("\\") || imageName.contains("..") || imageName == "." || imageName == ".." {
            return .failure("Invalid imageName: must be a bare name without slashes or '..'.")
        }
        let allowedChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_- "))
        if imageName.unicodeScalars.contains(where: { !allowedChars.contains($0) }) {
            return .failure("Invalid imageName: use letters, digits, spaces, '_' or '-'.")
        }
        guard let catalogURL = resolvePath(catalog, workspaceRoot: context.workspaceRoot) else {
            return .failure("Invalid catalog path '\(catalog)': must be inside the workspace and must not contain '..'.")
        }
        guard let sourceURL = resolvePath(sourceRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Invalid sourcePath '\(sourceRaw)': must be inside the workspace and must not contain '..'.")
        }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return .failure("Source image not found at '\(sourceRaw)'.")
        }
        let sourceFileName = sourceURL.lastPathComponent
        let fileName: String
        if sourceURL.pathExtension.isEmpty {
            fileName = "image.png"
        } else {
            fileName = sourceFileName
        }
        let imageSetURL = catalogURL.appendingPathComponent("\(imageName).imageset")
        if FileManager.default.fileExists(atPath: imageSetURL.path) {
            return .failure("Image set '\(imageName).imageset' already exists in '\(catalog)'.")
        }
        do {
            try FileManager.default.createDirectory(at: imageSetURL, withIntermediateDirectories: true)
        } catch {
            return .failure("Failed to create image set directory: \(error.localizedDescription)")
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
        do {
            try contentsJSON.write(to: contentsURL, atomically: true, encoding: .utf8)
            if FileManager.default.fileExists(atPath: destImageURL.path) {
                try FileManager.default.removeItem(at: destImageURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destImageURL)
        } catch {
            return .failure("Failed to add asset image: \(error.localizedDescription)")
        }
        guard FileManager.default.fileExists(atPath: contentsURL.path), FileManager.default.fileExists(atPath: destImageURL.path) else {
            return .failure("Verification failed: image set files not present after write.")
        }
        let relativeSet = relativePath(imageSetURL, root: context.workspaceRoot.standardizedFileURL)
        return .success("Added image '\(imageName)' to '\(catalog)' as \(relativeSet) with file \(fileName).", data: ["catalog": catalog, "imageName": imageName, "imageSet": relativeSet, "fileName": fileName])
    }

    private func relativePath(_ url: URL, root: URL) -> String {
        let path = url.standardizedFileURL.path
        let rootPath = root.path
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
    }

    private func resolvePath(_ rawPath: String, workspaceRoot: URL) -> URL? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.contains("..") { return nil }
        let root = workspaceRoot.standardizedFileURL
        if trimmed.hasPrefix("/") {
            let candidate = URL(fileURLWithPath: trimmed).standardizedFileURL
            guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { return nil }
            return candidate
        }
        let candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { return nil }
        return candidate
    }
}
