import Foundation
import Testing
import SwiftCodeAssistant
@testable import SwiftCodeMCP

@MainActor
@Suite(.serialized) struct SwiftCodeMediaToolsTests {
    static let mediaIDs = ["image_convert_format", "image_decode_base64", "image_encode_base64",
                           "image_extract_metadata", "image_generate_thumbnail", "image_get_dimensions",
                           "svg_to_png"]

    static let onePixelPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8Xw8AAwMCAO+ip1sAAAAASUVORK5CYII="
    static var onePixelPNG: Data { Data(base64Encoded: onePixelPNGBase64)! }

    func opened(_ sample: TempSample, policy: MCPWritePolicy = .allow) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.mediaTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.mediaTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func writeDataFixture(_ sample: TempSample, _ rel: String, _ data: Data) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static var onePixelJPEG: Data {
        Data([
            0xFF, 0xD8,
            0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
            0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x01, 0x00, 0x01, 0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
            0xFF, 0xD9,
        ])
    }

    static var onePixelGIF: Data {
        Data([
            0x47, 0x49, 0x46, 0x38, 0x39, 0x61,
            0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00,
            0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF,
            0x21, 0xFE, 0x05, 0x68, 0x65, 0x6C, 0x6C, 0x6F, 0x00,
            0x3B,
        ])
    }

    static var onePixelBMP: Data {
        let bytes: [UInt8] = [
            0x42, 0x4D,
            0x36, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x36, 0x00, 0x00, 0x00,
            0x28, 0x00, 0x00, 0x00,
            0x01, 0x00, 0x00, 0x00,
            0x01, 0x00, 0x00, 0x00,
            0x01, 0x00,
            0x18, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x13, 0x0B, 0x00, 0x00,
            0x13, 0x0B, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
        ]
        return Data(bytes)
    }

    static var tinyTIFF: Data {
        Data([
            0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00,
            0x02, 0x00,
            0x00, 0x01, 0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
            0x01, 0x01, 0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
        ])
    }

    static var tinyWebP: Data {
        Data([
            0x52, 0x49, 0x46, 0x46, 0x16, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50,
            0x56, 0x50, 0x38, 0x58, 0x0A, 0x00, 0x00, 0x00,
            0x10, 0x00, 0x00, 0x00,
            0x04, 0x00, 0x00,
            0x02, 0x00, 0x00,
        ])
    }

    static var pngWithTextChunk: Data {
        var bytes = [UInt8](onePixelPNG.prefix(33))
        bytes += [0x00, 0x00, 0x00, 0x0D]
        bytes += [0x74, 0x45, 0x58, 0x74]
        bytes += [UInt8]("Comment\0hello".utf8)
        bytes += [0x00, 0x00, 0x00, 0x00]
        bytes += [0x00, 0x00, 0x00, 0x00]
        bytes += [0x49, 0x45, 0x4E, 0x44]
        bytes += [0x00, 0x00, 0x00, 0x00]
        return Data(bytes)
    }

    static var jpegWithEXIF: Data {
        Data([
            0xFF, 0xD8,
            0xFF, 0xE1, 0x00, 0x22,
            0x45, 0x78, 0x69, 0x66, 0x00, 0x00,
            0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00,
            0x01, 0x00,
            0x0F, 0x01, 0x02, 0x00, 0x04, 0x00, 0x00, 0x00, 0x43, 0x61, 0x6D, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0xFF, 0xD9,
        ])
    }

    @Test func toolsAreRegisteredWithLegacySchemas() async throws {
        let host = SwiftCodeMCPHost()
        let tools = host.mediaTools
        #expect(tools.map(\.name) == Self.mediaIDs)
        let expectedTitles: [String: String] = [
            "image_convert_format": "Convert Image Format", "image_decode_base64": "Decode Base64 to Image",
            "image_encode_base64": "Encode Image to Base64", "image_extract_metadata": "Extract Image Metadata",
            "image_generate_thumbnail": "Generate Image Thumbnail", "image_get_dimensions": "Get Image Dimensions and Specs",
            "svg_to_png": "Convert SVG to PNG",
        ]
        let expectedRequired: [String: [String]] = [
            "image_convert_format": ["path", "format"], "image_decode_base64": ["base64String", "destination"],
            "image_encode_base64": ["path"], "image_extract_metadata": ["path"],
            "image_generate_thumbnail": ["path"], "image_get_dimensions": ["path"], "svg_to_png": ["path"],
        ]
        let expectedOutputs: [String: [String]] = [
            "image_convert_format": ["destination", "format", "size"],
            "image_decode_base64": ["destination", "size"],
            "image_encode_base64": ["base64", "byteCount", "charCount", "mimeType", "path"],
            "image_extract_metadata": ["metadataCount", "metadataJSON", "path"],
            "image_generate_thumbnail": ["destination", "height", "size", "width"],
            "image_get_dimensions": ["colorModel", "depth", "format", "hasAlpha", "height", "path", "width"],
            "svg_to_png": ["destination", "height", "size", "width"],
        ]
        let readOnlyIDs: Set<String> = ["image_encode_base64", "image_extract_metadata", "image_get_dimensions"]
        for tool in tools {
            #expect(tool.title == expectedTitles[tool.name])
            #expect(tool.inputSchema["properties"]?["workspace"] != nil, "\(tool.name) is missing the workspace parameter")
            let required = tool.inputSchema["required"]?.array?.compactMap(\.string) ?? []
            #expect(required == expectedRequired[tool.name], "\(tool.name) required: \(required)")
            let outputKeys = tool.outputSchema?["properties"]?.object?.keys.sorted() ?? []
            #expect(outputKeys == expectedOutputs[tool.name], "\(tool.name) output keys: \(outputKeys)")
            if readOnlyIDs.contains(tool.name) {
                #expect(tool.annotations.readOnly && tool.annotations.idempotent && !tool.writes,
                        "\(tool.name) must be a read-only tool")
            } else {
                #expect(!tool.annotations.readOnly && tool.annotations.idempotent && tool.writes,
                        "\(tool.name) must be a safeMutation write tool")
            }
        }
    }

    @Test func encodeBase64RoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeDataFixture(sample, "icon.png", Self.onePixelPNG)
        let host = try await opened(sample)
        let r = try await host.server.callTool("image_encode_base64", ["path": .string("icon.png")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["base64"]?.string == Self.onePixelPNGBase64)
        #expect(r.structured?["mimeType"]?.string == "image/png")
        #expect(r.structured?["byteCount"]?.int == Self.onePixelPNG.count)
        #expect(r.structured?["charCount"]?.int == Self.onePixelPNGBase64.count)
        #expect(r.firstText.contains("Successfully encoded `icon.png` into Base64"))
    }

    @Test func encodeBase64DataUri() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeDataFixture(sample, "icon.png", Self.onePixelPNG)
        let host = try await opened(sample)
        let r = try await host.server.callTool("image_encode_base64",
                                               ["path": .string("icon.png"), "includeDataUri": .bool(true)])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["base64"]?.string == "data:image/png;base64,\(Self.onePixelPNGBase64)")
        #expect(r.structured?["mimeType"]?.string == "image/png")
    }

    @Test func encodeBase64MissingFileFails() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("image_encode_base64", ["path": .string("nope.png")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Image file not found at: nope.png"))
    }

    @Test func encodeBase64UnknownExtensionMime() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeDataFixture(sample, "blob.bin", Self.onePixelPNG)
        let host = try await opened(sample)
        let r = try await host.server.callTool("image_encode_base64", ["path": .string("blob.bin")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["mimeType"]?.string == "application/octet-stream")
    }

    @Test func decodeBase64WritesFile() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("image_decode_base64",
                                               ["base64String": .string("data:image/png;base64,\(Self.onePixelPNGBase64)"),
                                                "destination": .string("Assets/icon.png")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Successfully decoded base64 string and saved image to `Assets/icon.png`"))
        #expect(r.structured?["size"]?.int == Self.onePixelPNG.count)
        let onDisk = try Data(contentsOf: URL(fileURLWithPath: sample.path("Assets/icon.png")))
        #expect(onDisk == Self.onePixelPNG)
    }

    @Test func decodeBase64InvalidFails() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("image_decode_base64",
                                               ["base64String": .string("not base64 at all !!!"),
                                                "destination": .string("out.png")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Failed to decode base64 string into valid binary data."))
        #expect(!FileManager.default.fileExists(atPath: sample.path("out.png")))
    }

    @Test func decodeBase64EscapingDestinationFails() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("image_decode_base64",
                                               ["base64String": .string(Self.onePixelPNGBase64),
                                                "destination": .string("../escape.png")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("outside the workspace"))
    }

    @Test func getDimensionsPNG() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeDataFixture(sample, "icon.png", Self.onePixelPNG)
        let host = try await opened(sample)
        let r = try await host.server.callTool("image_get_dimensions", ["path": .string("icon.png")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["width"]?.int == 1)
        #expect(r.structured?["height"]?.int == 1)
        #expect(r.structured?["format"]?.string == "public.png")
        #expect(r.structured?["colorModel"]?.string == "Gray")
        #expect(r.structured?["depth"]?.int == 8)
        #expect(r.structured?["hasAlpha"]?.bool == true)
        #expect(r.firstText.contains("Dimensions: 1 x 1 pixels"))
        #expect(r.firstText.contains("Format / UTI: public.png"))
    }

    @Test func getDimensionsAcrossFormats() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeDataFixture(sample, "a.jpg", Self.onePixelJPEG)
        try writeDataFixture(sample, "a.gif", Self.onePixelGIF)
        try writeDataFixture(sample, "a.bmp", Self.onePixelBMP)
        try writeDataFixture(sample, "a.tiff", Self.tinyTIFF)
        try writeDataFixture(sample, "a.webp", Self.tinyWebP)
        let host = try await opened(sample)
        let expectations: [(String, Int, Int, String, Bool)] = [
            ("a.jpg", 1, 1, "public.jpeg", false),
            ("a.gif", 1, 1, "com.compuserve.gif", false),
            ("a.bmp", 1, 1, "com.microsoft.bmp", false),
            ("a.tiff", 2, 3, "public.tiff", false),
            ("a.webp", 5, 3, "org.webmproject.webp", true),
        ]
        for (path, width, height, format, hasAlpha) in expectations {
            let r = try await host.server.callTool("image_get_dimensions", ["path": .string(path)])
            #expect(!r.isToolError, "\(path): \(r.resultText)")
            #expect(r.structured?["width"]?.int == width, "\(path) width")
            #expect(r.structured?["height"]?.int == height, "\(path) height")
            #expect(r.structured?["format"]?.string == format, "\(path) format")
            #expect(r.structured?["hasAlpha"]?.bool == hasAlpha, "\(path) alpha")
        }
    }

    @Test func getDimensionsUnknownFormatFails() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "notes.txt", "just text, not an image")
        let host = try await opened(sample)
        let r = try await host.server.callTool("image_get_dimensions", ["path": .string("notes.txt")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Could not create image source for: notes.txt"))
    }

    @Test func getDimensionsMissingFileFails() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("image_get_dimensions", ["path": .string("nope.png")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Image file not found at: nope.png"))
    }

    @Test func extractMetadataPNGTextChunk() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeDataFixture(sample, "tagged.png", Self.pngWithTextChunk)
        let host = try await opened(sample)
        let r = try await host.server.callTool("image_extract_metadata", ["path": .string("tagged.png")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["metadataCount"]?.int == 1)
        let json = r.structured?["metadataJSON"]?.string ?? ""
        #expect(json.contains("Comment"))
        #expect(json.contains("hello"))
        #expect(r.firstText.contains("Extracted metadata from `tagged.png` (1 property groups)"))
    }

    @Test func extractMetadataJPEGEXIF() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeDataFixture(sample, "photo.jpg", Self.jpegWithEXIF)
        let host = try await opened(sample)
        let r = try await host.server.callTool("image_extract_metadata", ["path": .string("photo.jpg")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["metadataCount"]?.int == 1)
        let json = r.structured?["metadataJSON"]?.string ?? ""
        #expect(json.contains("Make"))
        #expect(json.contains("Cam"))
    }

    @Test func extractMetadataJPEGJFIF() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeDataFixture(sample, "plain.jpg", Self.onePixelJPEG)
        let host = try await opened(sample)
        let r = try await host.server.callTool("image_extract_metadata", ["path": .string("plain.jpg")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["metadataCount"]?.int == 1)
        let json = r.structured?["metadataJSON"]?.string ?? ""
        #expect(json.contains("JFIF"))
        #expect(json.contains("1.1"))
    }

    @Test func extractMetadataGIFComment() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeDataFixture(sample, "anim.gif", Self.onePixelGIF)
        let host = try await opened(sample)
        let r = try await host.server.callTool("image_extract_metadata", ["path": .string("anim.gif")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["metadataCount"]?.int == 1)
        let json = r.structured?["metadataJSON"]?.string ?? ""
        #expect(json.contains("hello"))
    }

    @Test func extractMetadataNoEmbeddedDataIsEmptyNotError() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeDataFixture(sample, "plain.png", Self.onePixelPNG)
        let host = try await opened(sample)
        let r = try await host.server.callTool("image_extract_metadata", ["path": .string("plain.png")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["metadataCount"]?.int == 0)
    }

    @Test func extractMetadataMissingFileFails() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("image_extract_metadata", ["path": .string("nope.png")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Image file not found at: nope.png"))
    }

#if !os(macOS)
    @Test func convertFormatIsMacOSOnlyOnLinux() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeDataFixture(sample, "icon.png", Self.onePixelPNG)
        let host = try await opened(sample)
        let r = try await host.server.callTool("image_convert_format",
                                               ["path": .string("icon.png"), "format": .string("jpeg")])
        #expect(r.isToolError)
        #expect(r.firstText == "image_convert_format is only available on macOS.")
        #expect(!FileManager.default.fileExists(atPath: sample.path("icon.jpg")))
    }

    @Test func convertFormatUnsupportedFormatFailsBeforePlatformGate() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeDataFixture(sample, "icon.png", Self.onePixelPNG)
        let host = try await opened(sample)
        let r = try await host.server.callTool("image_convert_format",
                                               ["path": .string("icon.png"), "format": .string("heic")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Unsupported target format 'heic'"))
    }

    @Test func generateThumbnailIsMacOSOnlyOnLinux() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeDataFixture(sample, "icon.png", Self.onePixelPNG)
        let host = try await opened(sample)
        let r = try await host.server.callTool("image_generate_thumbnail", ["path": .string("icon.png")])
        #expect(r.isToolError)
        #expect(r.firstText == "image_generate_thumbnail is only available on macOS.")
        #expect(!FileManager.default.fileExists(atPath: sample.path("icon_thumb.png")))
    }

    @Test func generateThumbnailInvalidSizeFailsBeforePlatformGate() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeDataFixture(sample, "icon.png", Self.onePixelPNG)
        let host = try await opened(sample)
        let r = try await host.server.callTool("image_generate_thumbnail",
                                               ["path": .string("icon.png"), "maxPixelSize": .int(0)])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Invalid maxPixelSize '0'"))
    }

    @Test func svgToPngIsMacOSOnlyOnLinux() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "logo.svg", "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><rect width=\"10\" height=\"10\" fill=\"red\"/></svg>")
        let host = try await opened(sample)
        let r = try await host.server.callTool("svg_to_png", ["path": .string("logo.svg")])
        #expect(r.isToolError)
        #expect(r.firstText == "svg_to_png is only available on macOS.")
        #expect(!FileManager.default.fileExists(atPath: sample.path("logo.png")))
    }
#endif

    @Test func writeToolsRefusedWhenReadOnly() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .readOnly)
        let r = try await host.server.callTool("image_decode_base64",
                                               ["base64String": .string(Self.onePixelPNGBase64),
                                                "destination": .string("out.png")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("read-only"))
        #expect(!FileManager.default.fileExists(atPath: sample.path("out.png")))
    }

    @Test func readToolsAllowedWhenReadOnly() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeDataFixture(sample, "icon.png", Self.onePixelPNG)
        let host = try await opened(sample, policy: .readOnly)
        let r = try await host.server.callTool("image_get_dimensions", ["path": .string("icon.png")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["width"]?.int == 1)
    }
}
