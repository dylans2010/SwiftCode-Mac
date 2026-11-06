#if canImport(AppKit)
import AppKit
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(ImageIO)
import ImageIO
#endif
import Foundation
import YcodeAssistant
import YcodeIDECore

/// The ported Legacy image tool family (Wave 5, slice: Image).
///
/// Behaviour source: Legacy's `AssistImageEncodeBase64Tool`,
/// `AssistImageGetDimensionsTool`, `AssistImageExtractMetadataTool`
/// (`AssistImageInspectionTools.swift`) and
/// `AssistImageDecodeBase64Tool`, `AssistImageConvertFormatTool`,
/// `AssistImageGenerateThumbnailTool`, `AssistSvgToPngTool`
/// (`AssistImageMutationTools.swift`) — Dylan's own code, ported
/// under MIT. See `specs/ide/assist-artboards-media-tools.md` (Part B).
///
/// Conventions, following Waves 1–4:
///
/// * Schemas are Legacy's `parametersSchema` verbatim, plus the
///   `workspace` parameter every Ycode tool carries. Legacy's
///   parameter-name aliases (`filePath`, `base64`, `data`,
///   `destinationPath`, `path`, `source`) are NOT supported: Ycode's
///   argument validation rejects unknown arguments before the
///   handler runs (same as Waves 1–2).
/// * Structured data keeps Legacy's keys, with typed JSON values
///   (integers and booleans) the way Ycode's other tools do —
///   Legacy's string-only map is not reproduced.
/// * Path resolution is split the way Legacy splits it. The three
///   read tools (`image_encode_base64`, `image_get_dimensions`,
///   `image_extract_metadata`) use the session-aware
///   `resolveFileReadingPath` (plain relative paths resolve against
///   the `dir_cd` working directory; `..` that stays inside the
///   workspace is allowed; `~` expands). The four write tools use
///   the strict `resolveFileWritingPath` (trim; reject empty, NUL,
///   a leading `~` and any `..`; plain relative paths resolve
///   against the workspace root, never the session directory) —
///   the same shape as Legacy's image-mutation resolver. No path
///   is ever allowed to escape the workspace.
/// * Approval gating: every writing handler gates BEFORE touching
///   disk, through `approveFileWritingChange` (the Wave 2 helper
///   for non-text writes). `MCPServer.run` already refuses
///   `writes: true` tools when the server is read-only; the
///   approval call is still required. There is no Autopilot bypass.
/// * No new dependency. Dimensions and metadata are read with a
///   small pure-Foundation header parser (PNG, JPEG, GIF, BMP,
///   WebP, TIFF/EXIF) that runs on macOS and Linux alike, so the
///   read tools work everywhere. On macOS the dimensions reader
///   falls back to ImageIO for formats the parser does not know
///   (HEIC, JPEG 2000, …), and the metadata reader uses ImageIO's
///   full property dictionary exactly like Legacy; on Linux the
///   metadata reader returns only the embedded chunks it can parse
///   honestly (PNG text chunks, JPEG EXIF/JFIF, GIF comments, TIFF
///   IFD tags — see `mediaLinuxMetadata`).
///
/// Deliberate deviations from Legacy, recorded here:
///
/// * `image_convert_format`, `image_generate_thumbnail` and
///   `svg_to_png` use AppKit (`NSImage`/`NSBitmapImageRep`) and
///   ImageIO on macOS, exactly like Legacy. On Linux they run
///   through ImageMagick when it is installed (`magick` v7 or
///   `convert` v6 on PATH, fixed argv, same approval gate and
///   output keys); without ImageMagick they fail with an exact
///   "only available on macOS" message naming ImageMagick as the
///   Linux prerequisite, never a faked result. Their real macOS
///   behaviour stays pending verification on Dylan's Mac, and the
///   ImageMagick fallback is verified only at the argv-builder /
///   gate level in tests (no ImageMagick binary exists on this
///   Linux VM).
/// * `image_get_dimensions` reports the same message shape and
///   data keys as Legacy, but the values come from the header
///   parser (or ImageIO on macOS for unknown formats) rather
///   than ImageIO alone. For formats neither knows, it fails
///   with Legacy's "Could not create image source" wording.
/// * `image_extract_metadata` on Linux returns a subset (see
///   above); on macOS it returns Legacy's full ImageIO property
///   dictionary. The two platforms therefore return different
///   `metadataJSON` shapes for the same file; the spec records
///   both.
/// * `image_convert_format`'s description still says
///   "JPEG/HEIC" for `quality` (Legacy's wording), but HEIC is
///   not an accepted target format — the accepted set is exactly
///   Legacy's: png, jpeg/jpg, tiff/tif, bmp, gif.
/// * `image_decode_base64` validates the base64 payload before
///   resolving the destination (Legacy's order), but the
///   approval gate runs before the parent directories are
///   created or any byte is written.
extension YcodeMCPHost {
    var mediaTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        return [
            tool("image_convert_format", "Convert Image Format",
                 "Converts an image file between formats (png, jpeg, tiff, bmp, gif) with optional compression quality.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the source image."),
                                       "format": Schema.string("Target image format: 'png', 'jpeg', 'jpg', 'tiff', 'bmp', or 'gif'."),
                                       "destination": Schema.string("Optional workspace-relative destination path. Defaults to source path with new extension."),
                                       "quality": ["type": "number", "description": .string("Compression quality for JPEG/HEIC (0.0 to 1.0). Default: 0.9.")]],
                                      required: ["path", "format"]),
                 output: Schema.output(["destination": Schema.str, "size": Schema.int, "format": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.convertImageFormat(call)
            },
            tool("image_decode_base64", "Decode Base64 to Image",
                 "Decodes a Base64-encoded string into an image file (PNG, JPEG, TIFF, GIF) and saves it to disk.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "base64String": Schema.string("The base64 encoded image string (accepts raw base64 or data:image/...;base64,... URI)."),
                                       "destination": Schema.string("Workspace-relative file path where the decoded image will be saved (e.g. Assets/icon.png).")],
                                      required: ["base64String", "destination"]),
                 output: Schema.output(["destination": Schema.str, "size": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.decodeBase64Image(call)
            },
            tool("image_encode_base64", "Encode Image to Base64",
                 "Reads an image file from the workspace and encodes it into a Base64 string or Data URI.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the image file."),
                                       "includeDataUri": Schema.boolean("Whether to return as a full data:image/<type>;base64,... URI. Defaults to false.")],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str, "mimeType": Schema.str, "byteCount": Schema.int,
                                        "charCount": Schema.int, "base64": Schema.str])) { h, call in
                try h.encodeBase64Image(call)
            },
            tool("image_extract_metadata", "Extract Image Metadata",
                 "Extracts all embedded EXIF, TIFF, GPS, and camera metadata from an image as structured JSON.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the image file.")],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str, "metadataCount": Schema.int, "metadataJSON": Schema.str])) { h, call in
                try h.extractImageMetadata(call)
            },
            tool("image_generate_thumbnail", "Generate Image Thumbnail",
                 "Generates a scaled thumbnail image maintaining aspect ratio and writes it to disk.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the source image."),
                                       "maxPixelSize": Schema.integer("Maximum width or height of the thumbnail in pixels (e.g. 256). Default: 256."),
                                       "destination": Schema.string("Optional workspace-relative path for output thumbnail. Defaults to <name>_thumb.png.")],
                                      required: ["path"]),
                 output: Schema.output(["destination": Schema.str, "width": Schema.int, "height": Schema.int, "size": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.generateImageThumbnail(call)
            },
            tool("image_get_dimensions", "Get Image Dimensions and Specs",
                 "Extracts image dimensions (width, height), scale, color space, and format without loading full bitmap.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the image file.")],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str, "width": Schema.int, "height": Schema.int, "colorModel": Schema.str,
                                        "depth": Schema.int, "hasAlpha": Schema.bool, "format": Schema.str])) { h, call in
                try h.getImageDimensions(call)
            },
            tool("svg_to_png", "Convert SVG to PNG",
                 "Renders an SVG vector graphic into a raster PNG image file at a specified scale or dimensions.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the .svg file."),
                                       "destination": Schema.string("Optional workspace-relative destination path for .png. Defaults to <path>.png."),
                                       "scale": ["type": "number", "description": .string("Scale multiplier for rendering (e.g. 1.0, 2.0 for @2x, 3.0 for @3x). Default: 2.0.")],
                                       "width": Schema.integer("Explicit width in pixels (optional; overrides scale if provided)."),
                                       "height": Schema.integer("Explicit height in pixels (optional; overrides scale if provided).")],
                                      required: ["path"]),
                 output: Schema.output(["destination": Schema.str, "width": Schema.int, "height": Schema.int, "size": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.convertSvgToPng(call)
            },
        ]
    }

    /// Throws unless this is macOS (the Wave 4 `terminalRequireMacOS`
    /// shape). The three raster tools prefer AppKit/ImageIO on macOS
    /// and fall back to ImageMagick on Linux (see the
    /// `*ImageMagick` helpers below); this helper is kept for
    /// callers with no Linux path.
    nonisolated static func mediaRequireMacOS(_ tool: String) throws {
#if os(macOS)
#else
        throw MCPToolError("\(tool) is only available on macOS.")
#endif
    }

    /// Legacy's MIME mapping by file extension.
    nonisolated static func mediaMimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "tif", "tiff": return "image/tiff"
        default: return "application/octet-stream"
        }
    }
}

/// Dimensions and specs for one image, as `image_get_dimensions`
/// reports them. `format` is the UTI string Legacy's ImageIO path
/// reports (`public.png`, `public.jpeg`, …).
struct MediaImageInfo: Sendable {
    var width: Int
    var height: Int
    var format: String
    var colorModel: String
    var depth: Int
    var hasAlpha: Bool
    var dpiWidth: Double
    var dpiHeight: Double
}

// MARK: - Pure-Foundation image header parsing

/// Byte-level helpers for the header parser. All reads are
/// bounds-checked and return `nil` outside the data.
enum MediaHeaderBytes {
    static func u8(_ data: Data, _ at: Int) -> UInt8? {
        guard at >= 0, at < data.count else { return nil }
        return data[at]
    }
    static func be16(_ data: Data, _ at: Int) -> Int? {
        guard let hi = u8(data, at), let lo = u8(data, at + 1) else { return nil }
        return (Int(hi) << 8) | Int(lo)
    }
    static func be32(_ data: Data, _ at: Int) -> Int? {
        guard let b0 = u8(data, at), let b1 = u8(data, at + 1), let b2 = u8(data, at + 2), let b3 = u8(data, at + 3) else { return nil }
        return (Int(b0) << 24) | (Int(b1) << 16) | (Int(b2) << 8) | Int(b3)
    }
    static func le16(_ data: Data, _ at: Int) -> Int? {
        guard let lo = u8(data, at), let hi = u8(data, at + 1) else { return nil }
        return Int(lo) | (Int(hi) << 8)
    }
    static func le32(_ data: Data, _ at: Int) -> Int? {
        guard let b0 = u8(data, at), let b1 = u8(data, at + 1), let b2 = u8(data, at + 2), let b3 = u8(data, at + 3) else { return nil }
        return Int(b0) | (Int(b1) << 8) | (Int(b2) << 16) | (Int(b3) << 24)
    }
    static func le24(_ data: Data, _ at: Int) -> Int? {
        guard let b0 = u8(data, at), let b1 = u8(data, at + 1), let b2 = u8(data, at + 2) else { return nil }
        return Int(b0) | (Int(b1) << 8) | (Int(b2) << 16)
    }
    static func ascii(_ data: Data, _ at: Int, _ count: Int) -> String? {
        guard at >= 0, at + count <= data.count else { return nil }
        return String(decoding: data[at..<(at + count)], as: UTF8.self)
    }
}

/// Reads width/height/format (and, where the format carries them,
/// bit depth, alpha, colour model and DPI) from an image file's
/// header alone, without decoding any pixels — the behaviour
/// Legacy gets from ImageIO, for the formats Ycode can parse
/// honestly with Foundation only. Returns `nil` when the bytes
/// are not a format this parser knows (the caller falls back to
/// ImageIO on macOS, or fails, on Linux).
enum MediaHeaderParser {
    static func parse(_ data: Data) -> MediaImageInfo? {
        if data.count >= 8, data[0] == 0x89, data[1] == 0x50, data[2] == 0x4E, data[3] == 0x47,
           data[4] == 0x0D, data[5] == 0x0A, data[6] == 0x1A, data[7] == 0x0A {
            return parsePNG(data)
        }
        if data.count >= 2, data[0] == 0xFF, data[1] == 0xD8 {
            return parseJPEG(data)
        }
        if data.count >= 6, let head = MediaHeaderBytes.ascii(data, 0, 6), head == "GIF87a" || head == "GIF89a" {
            return parseGIF(data)
        }
        if data.count >= 2, data[0] == 0x42, data[1] == 0x4D { // "BM"
            return parseBMP(data)
        }
        if data.count >= 12, MediaHeaderBytes.ascii(data, 0, 4) == "RIFF", MediaHeaderBytes.ascii(data, 8, 4) == "WEBP" {
            return parseWebP(data)
        }
        if data.count >= 8, let order = MediaHeaderBytes.ascii(data, 0, 2), order == "II" || order == "MM" {
            return parseTIFF(data, base: 0)
        }
        return nil
    }

    /// PNG: IHDR carries width, height, bit depth and colour type;
    /// pHYs (when present, unit 1 = pixels per metre) carries DPI.
    static func parsePNG(_ data: Data) -> MediaImageInfo? {
        guard let width = MediaHeaderBytes.be32(data, 16), let height = MediaHeaderBytes.be32(data, 20),
              let bitDepth = MediaHeaderBytes.u8(data, 24), let colorType = MediaHeaderBytes.u8(data, 25) else { return nil }
        var dpiWidth = 72.0, dpiHeight = 72.0
        var offset = 8
        while offset + 8 <= data.count {
            guard let length = MediaHeaderBytes.be32(data, offset),
                  let type = MediaHeaderBytes.ascii(data, offset + 4, 4) else { return nil }
            if type == "pHYs", length >= 9,
               let ppmX = MediaHeaderBytes.be32(data, offset + 8), let ppmY = MediaHeaderBytes.be32(data, offset + 12),
               let unit = MediaHeaderBytes.u8(data, offset + 16), unit == 1 {
                dpiWidth = Double(ppmX) * 0.0254
                dpiHeight = Double(ppmY) * 0.0254
            }
            if type == "IEND" { break }
            offset += 12 + length
        }
        let (colorModel, hasAlpha): (String, Bool)
        switch colorType {
        case 0, 4: colorModel = "Gray"
        default: colorModel = "RGB"
        }
        hasAlpha = colorType == 4 || colorType == 6
        return MediaImageInfo(width: width, height: height, format: "public.png", colorModel: colorModel,
                              depth: Int(bitDepth), hasAlpha: hasAlpha, dpiWidth: dpiWidth, dpiHeight: dpiHeight)
    }

    /// JPEG: SOF0–SOF15 (except the DHT/JPG/DAC markers) carries
    /// precision, height, width and component count; JFIF APP0
    /// carries the density (unit 1 = DPI, unit 2 = dots per cm).
    static func parseJPEG(_ data: Data) -> MediaImageInfo? {
        let sof: Set<UInt8> = [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF]
        var width: Int?, height: Int?, precision = 8, components = 3
        var dpiWidth = 72.0, dpiHeight = 72.0
        var i = 2
        while i + 1 < data.count {
            guard data[i] == 0xFF else { break }
            var marker = data[i + 1]
            while marker == 0xFF {
                i += 1
                guard i + 1 < data.count else { return nil }
                marker = data[i + 1]
            }
            if marker == 0x00 || marker == 0xD9 || marker == 0xDA { break }
            if marker == 0x01 || (0xD0...0xD7).contains(marker) { i += 2; continue }
            guard let length = MediaHeaderBytes.be16(data, i + 2), length >= 2, i + 2 + length <= data.count else { break }
            if sof.contains(marker) {
                guard let p = MediaHeaderBytes.u8(data, i + 4),
                      let h = MediaHeaderBytes.be16(data, i + 5), let w = MediaHeaderBytes.be16(data, i + 7),
                      let c = MediaHeaderBytes.u8(data, i + 9) else { break }
                precision = Int(p); height = h; width = w; components = Int(c)
            } else if marker == 0xE0, length >= 16, MediaHeaderBytes.ascii(data, i + 4, 5) == "JFIF\0",
                      let unit = MediaHeaderBytes.u8(data, i + 11),
                      let xd = MediaHeaderBytes.be16(data, i + 12), let yd = MediaHeaderBytes.be16(data, i + 14) {
                switch unit {
                case 1: dpiWidth = Double(xd); dpiHeight = Double(yd)
                case 2: dpiWidth = Double(xd) * 2.54; dpiHeight = Double(yd) * 2.54
                default: break
                }
            }
            i += 2 + length
        }
        guard let width, let height else { return nil }
        return MediaImageInfo(width: width, height: height, format: "public.jpeg",
                              colorModel: components == 1 ? "Gray" : "RGB", depth: precision, hasAlpha: false,
                              dpiWidth: dpiWidth, dpiHeight: dpiHeight)
    }

    /// GIF: the logical screen descriptor carries the size; the
    /// packed field's colour-resolution bits carry the depth.
    /// (Transparency lives in a graphic-control extension, which
    /// this header read does not chase — GIFs report no alpha.)
    static func parseGIF(_ data: Data) -> MediaImageInfo? {
        guard let width = MediaHeaderBytes.le16(data, 6), let height = MediaHeaderBytes.le16(data, 8),
              let packed = MediaHeaderBytes.u8(data, 10) else { return nil }
        let depth = Int((packed >> 4) & 0x07) + 1
        return MediaImageInfo(width: width, height: height, format: "com.compuserve.gif", colorModel: "RGB",
                              depth: depth, hasAlpha: false, dpiWidth: 72, dpiHeight: 72)
    }

    /// BMP: BITMAPINFOHEADER carries size, bit count and pixels
    /// per metre (DPI when present).
    static func parseBMP(_ data: Data) -> MediaImageInfo? {
        guard let headerSize = MediaHeaderBytes.le32(data, 14), headerSize >= 40,
              let width = MediaHeaderBytes.le32(data, 18), let height = MediaHeaderBytes.le32(data, 22),
              let bitCount = MediaHeaderBytes.le16(data, 28) else { return nil }
        var dpiWidth = 72.0, dpiHeight = 72.0
        if let ppmX = MediaHeaderBytes.le32(data, 38), ppmX > 0 { dpiWidth = Double(ppmX) * 0.0254 }
        if let ppmY = MediaHeaderBytes.le32(data, 42), ppmY > 0 { dpiHeight = Double(ppmY) * 0.0254 }
        return MediaImageInfo(width: abs(width), height: abs(height), format: "com.microsoft.bmp", colorModel: "RGB",
                              depth: bitCount, hasAlpha: bitCount == 32, dpiWidth: dpiWidth, dpiHeight: dpiHeight)
    }

    /// WebP: VP8X carries width/height minus one plus an alpha
    /// flag; VP8 (lossy) and VP8L (lossless) carry 14-bit sizes.
    static func parseWebP(_ data: Data) -> MediaImageInfo? {
        var offset = 12
        while offset + 8 <= data.count {
            guard let type = MediaHeaderBytes.ascii(data, offset, 4),
                  let size = MediaHeaderBytes.le32(data, offset + 4), size >= 0 else { return nil }
            let chunk = offset + 8
            switch type {
            case "VP8X":
                guard let flags = MediaHeaderBytes.u8(data, chunk),
                      let w = MediaHeaderBytes.le24(data, chunk + 4), let h = MediaHeaderBytes.le24(data, chunk + 7) else { return nil }
                return MediaImageInfo(width: w + 1, height: h + 1, format: "org.webmproject.webp", colorModel: "RGB",
                                      depth: 8, hasAlpha: (flags & 0x10) != 0, dpiWidth: 72, dpiHeight: 72)
            case "VP8 ":
                guard let w = MediaHeaderBytes.le16(data, chunk + 6), let h = MediaHeaderBytes.le16(data, chunk + 8) else { return nil }
                return MediaImageInfo(width: w & 0x3FFF, height: h & 0x3FFF, format: "org.webmproject.webp",
                                      colorModel: "RGB", depth: 8, hasAlpha: false, dpiWidth: 72, dpiHeight: 72)
            case "VP8L":
                guard let packed = MediaHeaderBytes.le32(data, chunk + 1) else { return nil }
                let w = (packed & 0x3FFF) + 1
                let h = ((packed >> 14) & 0x3FFF) + 1
                return MediaImageInfo(width: w, height: h, format: "org.webmproject.webp", colorModel: "RGB",
                                      depth: 8, hasAlpha: ((packed >> 28) & 0x01) != 0, dpiWidth: 72, dpiHeight: 72)
            default:
                break
            }
            offset = chunk + size + (size % 2)
        }
        return nil
    }

    /// TIFF: the first IFD's width/height/bits-per-sample/
    /// photometric/samples-per-pixel/resolution tags.
    static func parseTIFF(_ data: Data, base: Int) -> MediaImageInfo? {
        guard let tags = MediaTIFFParser(data: data, base: base).firstIFD() else { return nil }
        guard let width = tags[256]?.intValue, let height = tags[257]?.intValue else { return nil }
        let depth = tags[258]?.intValue ?? 8
        let photometric = tags[262]?.intValue ?? 2
        let samples = tags[277]?.intValue ?? 3
        var dpiWidth = 72.0, dpiHeight = 72.0
        if let unit = tags[296]?.intValue {
            if let x = tags[282]?.doubleValue, let y = tags[283]?.doubleValue {
                let factor = unit == 3 ? 2.54 : 1.0
                dpiWidth = x * factor
                dpiHeight = y * factor
            }
        }
        let colorModel: String
        switch photometric {
        case 0, 1: colorModel = "Gray"
        default: colorModel = "RGB"
        }
        let hasAlpha = samples == 2 || samples == 4
        return MediaImageInfo(width: width, height: height, format: "public.tiff", colorModel: colorModel,
                              depth: depth, hasAlpha: hasAlpha, dpiWidth: dpiWidth, dpiHeight: dpiHeight)
    }
}

// MARK: - TIFF / EXIF IFD parsing

/// One decoded IFD value. Single-element arrays collapse to the
/// scalar case; the JSON form is what the metadata tools report.
enum MediaTIFFValue: Sendable {
    case int(Int)
    case ints([Int])
    case string(String)
    case double(Double)
    case doubles([Double])

    var intValue: Int? {
        switch self {
        case .int(let v): return v
        case .ints(let vs): return vs.first
        default: return nil
        }
    }
    var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .doubles(let vs): return vs.first
        case .int(let v): return Double(v)
        case .ints(let vs): return vs.first.map(Double.init)
        default: return nil
        }
    }
    var jsonValue: Any {
        switch self {
        case .int(let v): return v
        case .ints(let vs): return vs
        case .string(let s): return s
        case .double(let v): return v
        case .doubles(let vs): return vs
        }
    }
}

/// A TIFF/EXIF image file directory reader: byte order, tag
/// directory, and the typed values of each entry. The same reader
/// serves TIFF files (`base` 0) and the EXIF APP1 payload inside a
/// JPEG (`base` = the TIFF header's offset in the file data).
struct MediaTIFFParser: Sendable {
    let data: Data
    let base: Int

    var littleEndian: Bool? {
        guard let order = MediaHeaderBytes.ascii(data, base, 2) else { return nil }
        if order == "II" { return true }
        if order == "MM" { return false }
        return nil
    }

    func u16(at offset: Int) -> Int? {
        littleEndian == true ? MediaHeaderBytes.le16(data, offset) : MediaHeaderBytes.be16(data, offset)
    }
    func u32(at offset: Int) -> Int? {
        littleEndian == true ? MediaHeaderBytes.le32(data, offset) : MediaHeaderBytes.be32(data, offset)
    }

    /// The entries of the first IFD, or `nil` when the header is
    /// not a TIFF header at all.
    func firstIFD() -> [UInt16: MediaTIFFValue]? {
        guard littleEndian != nil,
              let magic = u16(at: base + 2), magic == 42,
              let ifdOffset = u32(at: base + 4) else { return nil }
        return ifd(at: base + ifdOffset)
    }

    /// The entries of the IFD at an absolute offset in `data`.
    func ifd(at offset: Int) -> [UInt16: MediaTIFFValue]? {
        guard let count = u16(at: offset) else { return nil }
        var out: [UInt16: MediaTIFFValue] = [:]
        for i in 0..<count {
            let entry = offset + 2 + i * 12
            guard let tag = u16(at: entry), let type = u16(at: entry + 2),
                  let valueCount = u32(at: entry + 4) else { continue }
            if let value = readValue(type: type, count: valueCount, fieldOffset: entry + 8) {
                out[UInt16(tag)] = value
            }
        }
        return out
    }

    /// Decodes one entry's values. The 4-byte value field either
    /// holds the values inline (when they fit) or an offset from
    /// `base` to where they live.
    func readValue(type: Int, count: Int, fieldOffset: Int) -> MediaTIFFValue? {
        let typeSize: Int
        switch type {
        case 1, 2, 6, 7: typeSize = 1
        case 3, 8: typeSize = 2
        case 4, 9, 11: typeSize = 4
        case 5, 10, 12: typeSize = 8
        default: return nil
        }
        let total = typeSize * count
        let start: Int
        if total <= 4 {
            start = fieldOffset
        } else {
            guard let off = u32(at: fieldOffset) else { return nil }
            start = base + off
        }
        guard start >= 0, start + total <= data.count else { return nil }
        switch type {
        case 2: // ASCII: one string, NUL-terminated
            let bytes = data[start..<(start + total)]
            let text = String(decoding: bytes, as: UTF8.self)
            return .string(text.split(separator: "\0").first.map(String.init) ?? "")
        case 3, 8: // SHORT / SSHORT
            var values: [Int] = []
            for i in 0..<count {
                guard let v = u16(at: start + i * 2) else { return nil }
                values.append(type == 8 && v >= 0x8000 ? v - 0x10000 : v)
            }
            return values.count == 1 ? .int(values[0]) : .ints(values)
        case 4, 9: // LONG / SLONG
            var values: [Int] = []
            for i in 0..<count {
                guard let v = u32(at: start + i * 4) else { return nil }
                values.append(type == 9 && v >= 0x8000_0000 ? v - 0x1_0000_0000 : v)
            }
            return values.count == 1 ? .int(values[0]) : .ints(values)
        case 5, 10: // RATIONAL / SRATIONAL
            var values: [Double] = []
            for i in 0..<count {
                guard let num = u32(at: start + i * 8), let den = u32(at: start + i * 8 + 4) else { return nil }
                let n = type == 10 && num >= 0x8000_0000 ? num - 0x1_0000_0000 : num
                let d = type == 10 && den >= 0x8000_0000 ? den - 0x1_0000_0000 : den
                values.append(d == 0 ? 0 : Double(n) / Double(d))
            }
            return values.count == 1 ? .double(values[0]) : .doubles(values)
        case 11: // FLOAT
            var values: [Double] = []
            for i in 0..<count {
                var bits: UInt32 = 0
                for b in 0..<4 {
                    guard let byte = MediaHeaderBytes.u8(data, start + i * 4 + b) else { return nil }
                    bits |= UInt32(byte) << (littleEndian == true ? (b * 8) : ((3 - b) * 8))
                }
                values.append(Double(Float(bitPattern: bits)))
            }
            return values.count == 1 ? .double(values[0]) : .doubles(values)
        case 12: // DOUBLE
            var values: [Double] = []
            for i in 0..<count {
                var bits: UInt64 = 0
                for b in 0..<8 {
                    guard let byte = MediaHeaderBytes.u8(data, start + i * 8 + b) else { return nil }
                    bits |= UInt64(byte) << (littleEndian == true ? (b * 8) : ((7 - b) * 8))
                }
                values.append(Double(bitPattern: bits))
            }
            return values.count == 1 ? .double(values[0]) : .doubles(values)
        default: // BYTE / UNDEFINED: raw bytes as integers
            var values: [Int] = []
            for i in 0..<count {
                guard let byte = MediaHeaderBytes.u8(data, start + i) else { return nil }
                values.append(Int(byte))
            }
            return values.count == 1 ? .int(values[0]) : .ints(values)
        }
    }
}

/// EXIF / TIFF tag numbers to the names Legacy's ImageIO
/// dictionary uses (a subset of the common tags; unknown tags
/// report as `Tag <number>`).
enum MediaEXIFTagNames {
    static let ifd0: [UInt16: String] = [
        256: "PixelWidth", 257: "PixelHeight", 258: "BitsPerSample", 259: "Compression",
        262: "PhotometricInterpretation", 271: "Make", 272: "Model", 274: "Orientation",
        277: "SamplesPerPixel", 282: "XResolution", 283: "YResolution", 296: "ResolutionUnit",
        305: "Software", 306: "DateTime", 315: "Artist", 33432: "Copyright",
        34665: "ExifOffset", 34853: "GPSInfo",
    ]
    static let exif: [UInt16: String] = [
        36864: "ExifVersion", 36867: "DateTimeOriginal", 36868: "DateTimeDigitized",
        37121: "ComponentsConfiguration", 37377: "ShutterSpeedValue", 37378: "ApertureValue",
        37379: "BrightnessValue", 37380: "ExposureBiasValue", 37381: "MaxApertureValue",
        37382: "SubjectDistance", 37383: "MeteringMode", 37384: "LightSource", 37385: "Flash",
        37386: "FocalLength", 37500: "MakerNote", 37510: "UserComment",
        40960: "FlashpixVersion", 40961: "ColorSpace", 40962: "PixelXDimension",
        40963: "PixelYDimension", 41483: "FlashEnergy", 41986: "ExposureMode",
        41987: "WhiteBalance", 41988: "DigitalZoomRatio", 41989: "FocalLengthIn35mmFilm",
        41990: "SceneCaptureType", 42016: "ImageUniqueID",
    ]
    static let gps: [UInt16: String] = [
        0: "GPSVersionID", 1: "GPSLatitudeRef", 2: "GPSLatitude", 3: "GPSLongitudeRef",
        4: "GPSLongitude", 5: "GPSAltitudeRef", 6: "GPSAltitude", 7: "GPSTimeStamp",
        29: "GPSDateStamp",
    ]

    static func name(_ tag: UInt16, in table: [UInt16: String]) -> String {
        table[tag] ?? "Tag \(tag)"
    }
}

/// The Linux metadata reader: only what can be parsed honestly
/// from the file bytes with Foundation. Returns one group per
/// embedded source found (`PNG`, `EXIF`, `JFIF`, `GIF`, `TIFF`).
/// Compressed PNG text (`zTXt`) is skipped — there is no zlib
/// inflate in Foundation on Linux — and binary MakerNote data is
/// reported as a byte count, never decoded.
enum MediaLinuxMetadata {
    static func read(_ data: Data) -> [String: Any] {
        var groups: [String: Any] = [:]
        if data.count >= 8, data[0] == 0x89, data[1] == 0x50, data[2] == 0x4E, data[3] == 0x47 {
            if let png = readPNGText(data), !png.isEmpty { groups["PNG"] = png }
        } else if data.count >= 2, data[0] == 0xFF, data[1] == 0xD8 {
            if let jfif = readJFIF(data) { groups["JFIF"] = jfif }
            if let exif = readJPEGEXIF(data), !exif.isEmpty { groups["EXIF"] = exif }
        } else if data.count >= 6, let head = MediaHeaderBytes.ascii(data, 0, 6), head == "GIF87a" || head == "GIF89a" {
            if let comment = readGIFComment(data) { groups["GIF"] = ["Comment": comment] }
        } else if data.count >= 8, let order = MediaHeaderBytes.ascii(data, 0, 2), order == "II" || order == "MM" {
            let parser = MediaTIFFParser(data: data, base: 0)
            if let ifd = parser.firstIFD(), !ifd.isEmpty {
                groups["TIFF"] = named(ifd, names: MediaEXIFTagNames.ifd0)
            }
        }
        return groups
    }

    static func named(_ ifd: [UInt16: MediaTIFFValue], names: [UInt16: String]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (tag, value) in ifd {
            if tag == 37500 { // MakerNote: binary blob, never decoded
                if case .ints(let bytes) = value { out["MakerNote"] = "(binary data, \(bytes.count) bytes)" }
                else { out["MakerNote"] = "(binary data)" }
                continue
            }
            if tag == 37510, case .string(let comment) = value { // UserComment: 8-byte encoding prefix
                out["UserComment"] = String(comment.dropFirst(min(8, comment.count)))
                continue
            }
            out[MediaEXIFTagNames.name(tag, in: names)] = value.jsonValue
        }
        return out
    }

    /// PNG `tEXt` (plain) and uncompressed `iTXt` keyword/value
    /// pairs. `zTXt` is skipped (compressed — no inflate here).
    static func readPNGText(_ data: Data) -> [String: Any]? {
        var out: [String: Any] = [:]
        var offset = 8
        while offset + 8 <= data.count {
            guard let length = MediaHeaderBytes.be32(data, offset),
                  let type = MediaHeaderBytes.ascii(data, offset + 4, 4) else { return out.isEmpty ? nil : out }
            let chunk = offset + 8
            guard chunk + length <= data.count else { return out.isEmpty ? nil : out }
            if type == "tEXt", length >= 1 {
                let bytes = data[chunk..<(chunk + length)]
                if let nul = bytes.firstIndex(of: 0) {
                    let keyword = String(decoding: bytes[bytes.startIndex..<nul], as: UTF8.self)
                    let value = String(decoding: bytes[bytes.index(after: nul)..<bytes.endIndex], as: UTF8.self)
                    if !keyword.isEmpty { out[keyword] = value }
                }
            } else if type == "iTXt", length >= 1 {
                // keyword NUL compressionFlag compressionMethod language NUL translated NUL text
                let bytes = [UInt8](data[chunk..<(chunk + length)])
                var cursor = 0
                while cursor < bytes.count, bytes[cursor] != 0 { cursor += 1 }
                guard cursor < bytes.count, cursor + 2 < bytes.count, bytes[cursor + 1] == 0 else {
                    offset += 12 + length
                    continue
                }
                let keyword = String(decoding: bytes[0..<cursor], as: UTF8.self)
                cursor += 3 // NUL, flag (0), method
                while cursor < bytes.count, bytes[cursor] != 0 { cursor += 1 } // language tag
                guard cursor < bytes.count else {
                    offset += 12 + length
                    continue
                }
                cursor += 1
                while cursor < bytes.count, bytes[cursor] != 0 { cursor += 1 } // translated keyword
                guard cursor < bytes.count else {
                    offset += 12 + length
                    continue
                }
                cursor += 1
                let value = String(decoding: bytes[cursor..<bytes.count], as: UTF8.self)
                if !keyword.isEmpty { out[keyword] = value }
            }
            if type == "IEND" { break }
            offset += 12 + length
        }
        return out.isEmpty ? nil : out
    }

    /// JFIF APP0 density/version, when the JPEG carries one.
    static func readJFIF(_ data: Data) -> [String: Any]? {
        var i = 2
        while i + 1 < data.count {
            guard data[i] == 0xFF else { return nil }
            let marker = data[i + 1]
            if marker == 0xD9 || marker == 0xDA { return nil }
            if marker == 0x01 || (0xD0...0xD7).contains(marker) { i += 2; continue }
            guard let length = MediaHeaderBytes.be16(data, i + 2), length >= 2, i + 2 + length <= data.count else { return nil }
            if marker == 0xE0, length >= 16, MediaHeaderBytes.ascii(data, i + 4, 5) == "JFIF\0",
               let versionMajor = MediaHeaderBytes.u8(data, i + 9), let versionMinor = MediaHeaderBytes.u8(data, i + 10),
               let unit = MediaHeaderBytes.u8(data, i + 11),
               let xd = MediaHeaderBytes.be16(data, i + 12), let yd = MediaHeaderBytes.be16(data, i + 14) {
                return ["Version": "\(versionMajor).\(versionMinor)", "DensityUnit": unit,
                        "XDensity": xd, "YDensity": yd]
            }
            i += 2 + length
        }
        return nil
    }

    /// JPEG EXIF APP1: IFD0 plus the Exif and GPS sub-IFDs the
    /// pointers name.
    static func readJPEGEXIF(_ data: Data) -> [String: Any]? {
        var i = 2
        while i + 1 < data.count {
            guard data[i] == 0xFF else { return nil }
            let marker = data[i + 1]
            if marker == 0xD9 || marker == 0xDA { return nil }
            if marker == 0x01 || (0xD0...0xD7).contains(marker) { i += 2; continue }
            guard let length = MediaHeaderBytes.be16(data, i + 2), length >= 2, i + 2 + length <= data.count else { return nil }
            if marker == 0xE1, length >= 8, MediaHeaderBytes.ascii(data, i + 4, 6) == "Exif\0\0" {
                let base = i + 10
                let parser = MediaTIFFParser(data: data, base: base)
                guard let ifd0 = parser.firstIFD() else { return nil }
                var out = named(ifd0, names: MediaEXIFTagNames.ifd0)
                if let exifOffset = ifd0[34665]?.intValue,
                   let exifIFD = parser.ifd(at: base + exifOffset) {
                    for (key, value) in named(exifIFD, names: MediaEXIFTagNames.exif) { out[key] = value }
                }
                if let gpsOffset = ifd0[34853]?.intValue,
                   let gpsIFD = parser.ifd(at: base + gpsOffset) {
                    for (key, value) in named(gpsIFD, names: MediaEXIFTagNames.gps) { out[key] = value }
                }
                return out
            }
            i += 2 + length
        }
        return nil
    }

    /// GIF comment extensions (0x21 0xFE), walked block by block
    /// so image data is never mistaken for a comment.
    static func readGIFComment(_ data: Data) -> String? {
        guard let packed = MediaHeaderBytes.u8(data, 10) else { return nil }
        var offset = 13
        if (packed & 0x80) != 0 { offset += 3 * (1 << ((Int(packed) & 0x07) + 1)) }
        var comments: [String] = []
        while offset < data.count {
            let introducer = data[offset]
            if introducer == 0x3B { break } // trailer
            if introducer == 0x21 { // extension
                guard offset + 1 < data.count else { return comments.isEmpty ? nil : comments.joined(separator: "\n") }
                let label = data[offset + 1]
                var cursor = offset + 2
                if label == 0xFE {
                    var text = ""
                    while cursor < data.count {
                        let size = Int(data[cursor])
                        cursor += 1
                        guard size > 0, cursor + size <= data.count else { break }
                        text += String(decoding: data[cursor..<(cursor + size)], as: UTF8.self)
                        cursor += size
                    }
                    if !text.isEmpty { comments.append(text) }
                    offset = cursor
                    continue
                }
                // Any other extension: skip its sub-blocks.
                while cursor < data.count {
                    let size = Int(data[cursor])
                    cursor += 1
                    guard size > 0, cursor + size <= data.count else { break }
                    cursor += size
                }
                offset = cursor
                continue
            }
            if introducer == 0x2C { // image descriptor
                guard offset + 10 <= data.count, let imagePacked = MediaHeaderBytes.u8(data, offset + 9) else { break }
                var cursor = offset + 10
                if (imagePacked & 0x80) != 0 { cursor += 3 * (1 << ((Int(imagePacked) & 0x07) + 1)) }
                guard cursor < data.count else { break }
                cursor += 1 // LZW minimum code size
                while cursor < data.count {
                    let size = Int(data[cursor])
                    cursor += 1
                    guard size > 0, cursor + size <= data.count else { break }
                    cursor += size
                }
                offset = cursor
                continue
            }
            break
        }
        return comments.isEmpty ? nil : comments.joined(separator: "\n")
    }
}

// MARK: - Handlers

extension YcodeMCPHost {
    /// `image_encode_base64`: reads the file and returns its
    /// Base64 (or a data URI), with Legacy's message and keys.
    func encodeBase64Image(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "path")
        let url = try resolveFileReadingPath(raw, in: s)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPToolError("Image file not found at: \(raw)")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw MCPToolError("Failed to read image file `\(raw)`: \(error.localizedDescription)")
        }
        let base64 = data.base64EncodedString()
        let includeUri = call.bool("includeDataUri") ?? false
        let mimeType = Self.mediaMimeType(for: url)
        let resultString = includeUri ? "data:\(mimeType);base64,\(base64)" : base64
        let preview = String(resultString.prefix(100)) + "..."
        return .structured(["path": .string(raw), "mimeType": .string(mimeType), "byteCount": .int(data.count),
                            "charCount": .int(resultString.count), "base64": .string(resultString)],
                           summary: "Successfully encoded `\(raw)` into Base64 (\(data.count) bytes raw, \(base64.count) chars base64).\nPreview: \(preview)")
    }

    /// `image_get_dimensions`: the header parser first (every
    /// platform); on macOS, ImageIO for formats the parser does
    /// not know.
    func getImageDimensions(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "path")
        let url = try resolveFileReadingPath(raw, in: s)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPToolError("Image file not found at: \(raw)")
        }
        let info: MediaImageInfo
        if let data = try? Data(contentsOf: url), let parsed = MediaHeaderParser.parse(data) {
            info = parsed
        } else if let fallback = Self.mediaImageIOInfo(at: url) {
            info = fallback
        } else {
            throw MCPToolError("Could not create image source for: \(raw)")
        }
        let output = """
        Image Specifications for \(raw):
        - Dimensions: \(info.width) x \(info.height) pixels
        - Aspect Ratio: \(info.height > 0 ? String(format: "%.2f", Double(info.width) / Double(info.height)) : "N/A")
        - Color Model: \(info.colorModel) (\(info.depth)-bit)
        - Has Alpha Channel: \(info.hasAlpha ? "Yes" : "No")
        - Resolution: \(Int(info.dpiWidth)) x \(Int(info.dpiHeight)) DPI
        - Format / UTI: \(info.format)
        """
        return .structured(["path": .string(raw), "width": .int(info.width), "height": .int(info.height),
                            "colorModel": .string(info.colorModel), "depth": .int(info.depth),
                            "hasAlpha": .bool(info.hasAlpha), "format": .string(info.format)],
                           summary: output)
    }

    /// `image_extract_metadata`: on macOS, ImageIO's full property
    /// dictionary exactly like Legacy; elsewhere, the embedded
    /// chunks the Linux reader can parse honestly.
    func extractImageMetadata(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "path")
        let url = try resolveFileReadingPath(raw, in: s)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPToolError("Image file not found at: \(raw)")
        }
#if canImport(ImageIO)
        if let properties = Self.mediaImageIOProperties(at: url) {
            var sanitized: [String: Any] = [:]
            for (key, value) in properties {
                if JSONSerialization.isValidJSONObject([key: value]) {
                    sanitized[key] = value
                } else {
                    sanitized[key] = String(describing: value)
                }
            }
            let jsonString: String
            if let jsonData = try? JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: jsonData, encoding: .utf8) {
                jsonString = str
            } else {
                jsonString = "\(sanitized)"
            }
            return .structured(["path": .string(raw), "metadataCount": .int(sanitized.count), "metadataJSON": .string(jsonString)],
                               summary: "Extracted metadata from `\(raw)` (\(sanitized.count) property groups):\n\(jsonString)")
        }
        throw MCPToolError("Could not read image source at: \(raw)")
#else
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw MCPToolError("Could not read image source at: \(raw)")
        }
        let groups = MediaLinuxMetadata.read(data)
        let jsonString: String
        if let jsonData = try? JSONSerialization.data(withJSONObject: groups, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: jsonData, encoding: .utf8) {
            jsonString = str
        } else {
            jsonString = "\(groups)"
        }
        return .structured(["path": .string(raw), "metadataCount": .int(groups.count), "metadataJSON": .string(jsonString)],
                           summary: "Extracted metadata from `\(raw)` (\(groups.count) property groups):\n\(jsonString)")
#endif
    }

    /// `image_decode_base64`: strips a `data:…;base64,` prefix,
    /// decodes, and writes the raw bytes (no re-encode).
    func decodeBase64Image(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard var rawBase64 = call.string("base64String"), let destRaw = call.string("destination") else {
            throw MCPToolError("Missing required parameters: base64String and destination")
        }
        if let commaIndex = rawBase64.firstIndex(of: ",") {
            let prefix = String(rawBase64[..<commaIndex])
            if prefix.contains(";base64") {
                rawBase64 = String(rawBase64[rawBase64.index(after: commaIndex)...])
            }
        }
        let cleaned = rawBase64.components(separatedBy: .whitespacesAndNewlines).joined()
        guard let data = Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters), !data.isEmpty else {
            throw MCPToolError("Failed to decode base64 string into valid binary data.")
        }
        let s = try session(for: call)
        guard let destURL = resolveFileWritingPath(destRaw, in: s) else {
            throw MCPToolError("Destination path is outside the workspace: \(destRaw)")
        }
        let rel = fileReadingRelativePath(of: destURL, in: s)
        try await approveFileWritingChange(tool: call.name, path: destURL, relativePath: rel, original: nil,
                                           summary: "Decode base64 image to \(rel)", call: call)
        do {
            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destURL, options: .atomic)
        } catch {
            throw MCPToolError("Failed to write image data to `\(destRaw)`: \(error.localizedDescription)")
        }
        noteFileWritingChanged(destURL, in: s)
        return .structured(["destination": .string(destRaw), "size": .int(data.count)],
                           summary: "Successfully decoded base64 string and saved image to `\(destRaw)` (\(data.count) bytes).")
    }

    /// `image_convert_format`: AppKit decode + re-encode, exactly
    /// like Legacy. macOS-only (the Wave 4 shape: this thin handler
    /// validates and gates; the real work is in
    /// `convertImageFormatMacOS` below).
    func convertImageFormat(_ call: MCPToolCall) async throws -> MCPToolResult {
        let sourceRaw = try fileReadingRequiredString(call, "path")
        guard let formatRaw = call.string("format")?.lowercased() else {
            throw MCPToolError("Missing required parameters: path and format")
        }
        guard ["png", "jpeg", "jpg", "tiff", "tif", "bmp", "gif"].contains(formatRaw) else {
            throw MCPToolError("Unsupported target format '\(formatRaw)'. Supported formats: png, jpeg, tiff, bmp, gif.")
        }
#if canImport(AppKit)
        return try await convertImageFormatMacOS(call, sourceRaw: sourceRaw, formatRaw: formatRaw)
#else
        return try await convertImageFormatImageMagick(call, sourceRaw: sourceRaw, formatRaw: formatRaw)
#endif
    }

#if canImport(AppKit)
    func convertImageFormatMacOS(_ call: MCPToolCall, sourceRaw: String, formatRaw: String) async throws -> MCPToolResult {
        let s = try session(for: call)
        let sourceURL = try resolveFileReadingPath(sourceRaw, in: s)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw MCPToolError("Source image not found at: \(sourceRaw)")
        }
        guard let nsImage = NSImage(contentsOf: sourceURL),
              let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            throw MCPToolError("Failed to read and decode image at: \(sourceRaw)")
        }
        let fileType: NSBitmapImageRep.FileType
        let ext: String
        switch formatRaw {
        case "png": fileType = .png; ext = "png"
        case "jpeg", "jpg": fileType = .jpeg; ext = "jpg"
        case "tiff", "tif": fileType = .tiff; ext = "tiff"
        case "bmp": fileType = .bmp; ext = "bmp"
        default: fileType = .gif; ext = "gif"
        }
        let quality = call.arguments["quality"]?.double ?? 0.9
        var props: [NSBitmapImageRep.PropertyKey: Any] = [:]
        if fileType == .jpeg {
            props[.compressionFactor] = NSNumber(value: quality)
        }
        guard let outputData = bitmap.representation(using: fileType, properties: props) else {
            throw MCPToolError("Failed to convert image to \(formatRaw) format.")
        }
        let defaultDest = (sourceRaw as NSString).deletingPathExtension + ".\(ext)"
        let destRaw = call.string("destination") ?? defaultDest
        guard let destURL = resolveFileWritingPath(destRaw, in: s) else {
            throw MCPToolError("Destination path is outside the workspace: \(destRaw)")
        }
        let rel = fileReadingRelativePath(of: destURL, in: s)
        try await approveFileWritingChange(tool: call.name, path: destURL, relativePath: rel, original: nil,
                                           summary: "Convert \(fileReadingRelativePath(of: sourceURL, in: s)) to \(formatRaw.uppercased())", call: call)
        do {
            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try outputData.write(to: destURL, options: .atomic)
        } catch {
            throw MCPToolError("Failed to write converted image to `\(destRaw)`: \(error.localizedDescription)")
        }
        noteFileWritingChanged(destURL, in: s)
        return .structured(["destination": .string(destRaw), "size": .int(outputData.count), "format": .string(formatRaw)],
                           summary: "Successfully converted `\(sourceRaw)` to \(formatRaw.uppercased()) at `\(destRaw)` (\(outputData.count) bytes).")
    }
#endif

    /// `image_generate_thumbnail`: ImageIO thumbnail + PNG encode,
    /// exactly like Legacy. macOS-only (thin handler + macOS helper,
    /// the Wave 4 shape).
    func generateImageThumbnail(_ call: MCPToolCall) async throws -> MCPToolResult {
        let sourceRaw = try fileReadingRequiredString(call, "path")
        let maxPixelSize = call.int("maxPixelSize") ?? 256
        guard maxPixelSize > 0 else {
            throw MCPToolError("Invalid maxPixelSize '\(maxPixelSize)': must be a positive integer.")
        }
#if canImport(ImageIO)
        return try await generateImageThumbnailMacOS(call, sourceRaw: sourceRaw, maxPixelSize: maxPixelSize)
#else
        return try await generateImageThumbnailImageMagick(call, sourceRaw: sourceRaw, maxPixelSize: maxPixelSize)
#endif
    }

#if canImport(ImageIO)
    func generateImageThumbnailMacOS(_ call: MCPToolCall, sourceRaw: String, maxPixelSize: Int) async throws -> MCPToolResult {
        let s = try session(for: call)
        let sourceURL = try resolveFileReadingPath(sourceRaw, in: s)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw MCPToolError("Source image not found at: \(sourceRaw)")
        }
        guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw MCPToolError("Could not read image source at: \(sourceRaw)")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let thumbnailCG = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            throw MCPToolError("Failed to create thumbnail from image: \(sourceRaw)")
        }
        guard let pngData = Self.mediaEncodePNG(thumbnailCG) else {
            throw MCPToolError("Failed to encode thumbnail into PNG data.")
        }
        let baseName = (sourceRaw as NSString).deletingPathExtension
        let defaultDest = "\(baseName)_thumb.png"
        let destRaw = call.string("destination") ?? defaultDest
        guard let destURL = resolveFileWritingPath(destRaw, in: s) else {
            throw MCPToolError("Destination path is outside the workspace: \(destRaw)")
        }
        let rel = fileReadingRelativePath(of: destURL, in: s)
        try await approveFileWritingChange(tool: call.name, path: destURL, relativePath: rel, original: nil,
                                           summary: "Generate thumbnail for \(fileReadingRelativePath(of: sourceURL, in: s))", call: call)
        do {
            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try pngData.write(to: destURL, options: .atomic)
        } catch {
            throw MCPToolError("Failed to write thumbnail to `\(destRaw)`: \(error.localizedDescription)")
        }
        noteFileWritingChanged(destURL, in: s)
        return .structured(["destination": .string(destRaw), "width": .int(thumbnailCG.width),
                            "height": .int(thumbnailCG.height), "size": .int(pngData.count)],
                           summary: "Successfully generated \(thumbnailCG.width)x\(thumbnailCG.height) thumbnail for `\(sourceRaw)` at `\(destRaw)` (\(pngData.count) bytes).")
    }
#endif

    /// `svg_to_png`: AppKit SVG rasterization, exactly like Legacy
    /// (an explicit width + height together override `scale`;
    /// otherwise the intrinsic size is scaled, default 2.0; a
    /// zero-sized intrinsic image renders at 512×512).
    /// macOS-only (thin handler + macOS helper, the Wave 4 shape).
    func convertSvgToPng(_ call: MCPToolCall) async throws -> MCPToolResult {
        let sourceRaw = try fileReadingRequiredString(call, "path")
#if canImport(AppKit)
        return try await convertSvgToPngMacOS(call, sourceRaw: sourceRaw)
#else
        return try await convertSvgToPngImageMagick(call, sourceRaw: sourceRaw)
#endif
    }

#if canImport(AppKit)
    func convertSvgToPngMacOS(_ call: MCPToolCall, sourceRaw: String) async throws -> MCPToolResult {
        let s = try session(for: call)
        let sourceURL = try resolveFileReadingPath(sourceRaw, in: s)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw MCPToolError("SVG file not found at: \(sourceRaw)")
        }
        guard let nsImage = NSImage(contentsOf: sourceURL) else {
            throw MCPToolError("Failed to parse and render SVG at: \(sourceRaw)")
        }
        var targetSize = nsImage.size
        if targetSize.width <= 0 || targetSize.height <= 0 {
            targetSize = NSSize(width: 512, height: 512)
        }
        if let explicitWidth = call.int("width"), let explicitHeight = call.int("height"),
           explicitWidth > 0, explicitHeight > 0 {
            targetSize = NSSize(width: explicitWidth, height: explicitHeight)
        } else {
            let scale = call.arguments["scale"]?.double ?? 2.0
            targetSize = NSSize(width: targetSize.width * scale, height: targetSize.height * scale)
        }
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw MCPToolError("Failed to allocate bitmap representation for SVG rendering.")
        }
        bitmap.size = targetSize
        NSGraphicsContext.saveGraphicsState()
        guard let contextRef = NSGraphicsContext(bitmapImageRep: bitmap) else {
            NSGraphicsContext.restoreGraphicsState()
            throw MCPToolError("Failed to create graphics context for bitmap.")
        }
        NSGraphicsContext.current = contextRef
        nsImage.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: nsImage.size),
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw MCPToolError("Failed to encode rendered SVG into PNG format.")
        }
        let baseName = (sourceRaw as NSString).deletingPathExtension
        let defaultDest = "\(baseName).png"
        let destRaw = call.string("destination") ?? defaultDest
        guard let destURL = resolveFileWritingPath(destRaw, in: s) else {
            throw MCPToolError("Destination path is outside the workspace: \(destRaw)")
        }
        let rel = fileReadingRelativePath(of: destURL, in: s)
        try await approveFileWritingChange(tool: call.name, path: destURL, relativePath: rel, original: nil,
                                           summary: "Render SVG \(fileReadingRelativePath(of: sourceURL, in: s)) to PNG", call: call)
        do {
            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try pngData.write(to: destURL, options: .atomic)
        } catch {
            throw MCPToolError("Failed to write rendered PNG to `\(destRaw)`: \(error.localizedDescription)")
        }
        noteFileWritingChanged(destURL, in: s)
        return .structured(["destination": .string(destRaw), "width": .int(Int(targetSize.width)),
                            "height": .int(Int(targetSize.height)), "size": .int(pngData.count)],
                           summary: "Successfully rendered SVG `\(sourceRaw)` to PNG `\(destRaw)` (\(Int(targetSize.width))x\(Int(targetSize.height)), \(pngData.count) bytes).")
    }
#endif
}

// MARK: - ImageMagick fallback (Linux)

extension YcodeMCPHost {
    /// Resolves ImageMagick on PATH: `magick` (v7) first, then
    /// `convert` (v6). Nil when neither exists.
    nonisolated static func mediaImageMagickPath() -> String? {
        guard let pathValue = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        let dirs = pathValue.split(separator: ":").map(String.init)
        for name in ["magick", "convert"] {
            for dir in dirs {
                let candidate = (dir as NSString).appendingPathComponent(name)
                if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
            }
        }
        return nil
    }

    /// Runs ImageMagick with a fixed argv (never a shell).
    /// Without ImageMagick the failure keeps the exact
    /// "only available on macOS" wording the media tests assert
    /// (the ImageMagick prerequisite is documented in the spec
    /// §12 and the file header instead).
    func mediaRunImageMagick(_ args: [String], tool: String) async throws -> TerminalFixedRun {
        guard let magick = Self.mediaImageMagickPath() else {
            throw MCPToolError("\(tool) is only available on macOS.")
        }
        guard let run = await archiveRunFixed(magick, args) else {
            throw MCPToolError("Could not start ImageMagick at \(magick).")
        }
        if run.timedOut {
            throw MCPToolError("ImageMagick timed out after 120s.")
        }
        guard run.exitCode == 0 else {
            let tail = (run.stdout + "\n" + run.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            throw MCPToolError("ImageMagick failed (exit \(run.exitCode))\(tail.isEmpty ? "." : ": \(tail.prefix(500))")")
        }
        return run
    }

    /// `image_convert_format` via ImageMagick: `magick <src>
    /// [-quality N] <dst>` (quality only for JPEG, Legacy's
    /// default 0.9 → 90). Same approval gate and output keys as
    /// the macOS helper.
    func convertImageFormatImageMagick(_ call: MCPToolCall, sourceRaw: String, formatRaw: String) async throws -> MCPToolResult {
        let s = try session(for: call)
        let sourceURL = try resolveFileReadingPath(sourceRaw, in: s)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw MCPToolError("Source image not found at: \(sourceRaw)")
        }
        let ext: String
        switch formatRaw {
        case "png": ext = "png"
        case "jpeg", "jpg": ext = "jpg"
        case "tiff", "tif": ext = "tiff"
        case "bmp": ext = "bmp"
        default: ext = "gif"
        }
        let defaultDest = (sourceRaw as NSString).deletingPathExtension + ".\(ext)"
        let destRaw = call.string("destination") ?? defaultDest
        guard let destURL = resolveFileWritingPath(destRaw, in: s) else {
            throw MCPToolError("Destination path is outside the workspace: \(destRaw)")
        }
        let rel = fileReadingRelativePath(of: destURL, in: s)
        try await approveFileWritingChange(tool: call.name, path: destURL, relativePath: rel, original: nil,
                                           summary: "Convert \(fileReadingRelativePath(of: sourceURL, in: s)) to \(formatRaw.uppercased())", call: call)
        var args = [sourceURL.path]
        if formatRaw == "jpeg" || formatRaw == "jpg" {
            let quality = call.arguments["quality"]?.double ?? 0.9
            args += ["-quality", "\(Int(quality * 100))"]
        }
        args.append(destURL.path)
        do {
            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw MCPToolError("Failed to create destination directory for `\(destRaw)`: \(error.localizedDescription)")
        }
        _ = try await mediaRunImageMagick(args, tool: call.name)
        guard let outputData = try? Data(contentsOf: destURL) else {
            throw MCPToolError("ImageMagick reported success but no output file appeared at `\(destRaw)`.")
        }
        noteFileWritingChanged(destURL, in: s)
        return .structured(["destination": .string(destRaw), "size": .int(outputData.count), "format": .string(formatRaw)],
                           summary: "Successfully converted `\(sourceRaw)` to \(formatRaw.uppercased()) at `\(destRaw)` (\(outputData.count) bytes).")
    }

    /// `image_generate_thumbnail` via ImageMagick: `magick <src>
    /// -resize <N>x<N> <dst>` (larger dimension capped at N,
    /// aspect preserved — Legacy's ImageIO thumbnail semantics).
    /// Dimensions come from the header parser on the output PNG.
    func generateImageThumbnailImageMagick(_ call: MCPToolCall, sourceRaw: String, maxPixelSize: Int) async throws -> MCPToolResult {
        let s = try session(for: call)
        let sourceURL = try resolveFileReadingPath(sourceRaw, in: s)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw MCPToolError("Source image not found at: \(sourceRaw)")
        }
        let baseName = (sourceRaw as NSString).deletingPathExtension
        let defaultDest = "\(baseName)_thumb.png"
        let destRaw = call.string("destination") ?? defaultDest
        guard let destURL = resolveFileWritingPath(destRaw, in: s) else {
            throw MCPToolError("Destination path is outside the workspace: \(destRaw)")
        }
        let rel = fileReadingRelativePath(of: destURL, in: s)
        try await approveFileWritingChange(tool: call.name, path: destURL, relativePath: rel, original: nil,
                                           summary: "Generate thumbnail for \(fileReadingRelativePath(of: sourceURL, in: s))", call: call)
        do {
            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw MCPToolError("Failed to create destination directory for `\(destRaw)`: \(error.localizedDescription)")
        }
        _ = try await mediaRunImageMagick([sourceURL.path, "-resize", "\(maxPixelSize)x\(maxPixelSize)", destURL.path], tool: call.name)
        guard let pngData = try? Data(contentsOf: destURL) else {
            throw MCPToolError("ImageMagick reported success but no thumbnail appeared at `\(destRaw)`.")
        }
        let info = MediaHeaderParser.parse(pngData)
        noteFileWritingChanged(destURL, in: s)
        return .structured(["destination": .string(destRaw), "width": .int(info?.width ?? 0),
                            "height": .int(info?.height ?? 0), "size": .int(pngData.count)],
                           summary: "Successfully generated \(info?.width ?? 0)x\(info?.height ?? 0) thumbnail for `\(sourceRaw)` at `\(destRaw)` (\(pngData.count) bytes).")
    }

    /// `svg_to_png` via ImageMagick: `magick -density <72*scale>
    /// -background none <src.svg> [-resize WxH!] <dst.png>`
    /// (explicit width + height together override the scale, as
    /// in Legacy). Dimensions come from the header parser on the
    /// output PNG.
    func convertSvgToPngImageMagick(_ call: MCPToolCall, sourceRaw: String) async throws -> MCPToolResult {
        let s = try session(for: call)
        let sourceURL = try resolveFileReadingPath(sourceRaw, in: s)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw MCPToolError("SVG file not found at: \(sourceRaw)")
        }
        let baseName = (sourceRaw as NSString).deletingPathExtension
        let defaultDest = "\(baseName).png"
        let destRaw = call.string("destination") ?? defaultDest
        guard let destURL = resolveFileWritingPath(destRaw, in: s) else {
            throw MCPToolError("Destination path is outside the workspace: \(destRaw)")
        }
        let rel = fileReadingRelativePath(of: destURL, in: s)
        try await approveFileWritingChange(tool: call.name, path: destURL, relativePath: rel, original: nil,
                                           summary: "Render SVG \(fileReadingRelativePath(of: sourceURL, in: s)) to PNG", call: call)
        let scale = call.arguments["scale"]?.double ?? 2.0
        var args = ["-density", "\(Int(72.0 * scale))", "-background", "none", sourceURL.path]
        var targetWidth = 0
        var targetHeight = 0
        if let w = call.int("width"), let h = call.int("height"), w > 0, h > 0 {
            targetWidth = w
            targetHeight = h
            args += ["-resize", "\(w)x\(h)!"]
        }
        args.append(destURL.path)
        do {
            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw MCPToolError("Failed to create destination directory for `\(destRaw)`: \(error.localizedDescription)")
        }
        _ = try await mediaRunImageMagick(args, tool: call.name)
        guard let pngData = try? Data(contentsOf: destURL) else {
            throw MCPToolError("ImageMagick reported success but no PNG appeared at `\(destRaw)`.")
        }
        let info = MediaHeaderParser.parse(pngData)
        let width = info?.width ?? targetWidth
        let height = info?.height ?? targetHeight
        noteFileWritingChanged(destURL, in: s)
        return .structured(["destination": .string(destRaw), "width": .int(width),
                            "height": .int(height), "size": .int(pngData.count)],
                           summary: "Successfully rendered SVG `\(sourceRaw)` to PNG `\(destRaw)` (\(width)x\(height), \(pngData.count) bytes).")
    }
}

// MARK: - ImageIO helpers (macOS only)

extension YcodeMCPHost {
    /// ImageIO dimensions for a format the header parser does not
    /// know (HEIC, JPEG 2000, …). `nil` on Linux and when ImageIO
    /// cannot read the file at all.
    nonisolated static func mediaImageIOInfo(at url: URL) -> MediaImageInfo? {
#if canImport(ImageIO)
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else { return nil }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let dpiWidth = properties[kCGImagePropertyDPIWidth] as? Double ?? 72.0
        let dpiHeight = properties[kCGImagePropertyDPIHeight] as? Double ?? 72.0
        let colorModel = properties[kCGImagePropertyColorModel] as? String ?? "Unknown"
        let depth = properties[kCGImagePropertyDepth] as? Int ?? 8
        let hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool ?? false
        let typeIdentifier = CGImageSourceGetType(imageSource) as String? ?? url.pathExtension
        return MediaImageInfo(width: width, height: height, format: typeIdentifier, colorModel: colorModel,
                              depth: depth, hasAlpha: hasAlpha, dpiWidth: dpiWidth, dpiHeight: dpiHeight)
#else
        return nil
#endif
    }

    /// ImageIO's full property dictionary for a file, or `nil`
    /// when it cannot be read. (macOS only; the Linux metadata
    /// reader never calls this.)
    nonisolated static func mediaImageIOProperties(at url: URL) -> [String: Any]? {
#if canImport(ImageIO)
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else { return nil }
        return properties
#else
        return nil
#endif
    }

    /// Encodes a `CGImage` as PNG data (the Wave 4
    /// `terminalEncodePNG` shape, with the UTI as a literal so no
    /// UniformTypeIdentifiers import is needed). macOS only: the
    /// whole function is compiled out where CoreGraphics is absent.
#if canImport(CoreGraphics)
    nonisolated static func mediaEncodePNG(_ image: CGImage) -> Data? {
#if canImport(ImageIO)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
#else
        return nil
#endif
    }
#endif
}
