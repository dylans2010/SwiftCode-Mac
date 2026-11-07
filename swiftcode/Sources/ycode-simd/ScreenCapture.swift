import Foundation
import YcodeHostServices

struct ScreenCapture {
    let statePath: String
    let service: IOSurfaceHostService
    var slot = 0
    var rotation = 0
    var displayName = "LCD"

    func record() -> FrameRecord? {
        guard let data = FileManager.default.contents(atPath: statePath) else { return nil }
        let start = slot * FrameRecord.size
        guard data.count > start else { return nil }
        let bytes = data[(data.startIndex + start)..<min(data.endIndex, data.startIndex + start + FrameRecord.size)]
        return FrameRecord.parse(Substring(String(decoding: bytes, as: UTF8.self)))
    }

    func presentedSurface() -> UInt32? { record().flatMap { $0.surface == 0 ? nil : $0.surface } }

    func capture(to path: String) -> String {
        var id = presentedSurface()
        var how = "presented surface"
        if id == nil {
            guard slot == 0 else { return "\(displayName): no frame presented on this display yet" }
            id = service.surfaceSummary.filter { $0.name.hasPrefix("LCD") }.max { $0.width * $0.height < $1.width * $1.height }?.id
            how = "no frame presented yet; the display buffer"
        }
        guard let id, let s = service.snapshot(surfaceID: id) else {
            return "no surface to capture (\(service.surfaceSummary.count) surfaces exist)"
        }
        guard s.bytesPerElement == 4, s.width > 0, s.height > 0 else {
            return "surface \(id) (\(s.name)) is \(s.width)x\(s.height) with \(s.bytesPerElement) bytes per element: not captured"
        }
        let flat = PNG.rgba(fromBGRA: s.bytes, width: s.width, height: s.height, bytesPerRow: s.bytesPerRow)
        let (rgba, width, height) = PanelPicture.rotate(rgba: flat, width: s.width, height: s.height, degrees: rotation)
        let nonzero = rgba.lazy.enumerated().contains { $0.offset % 4 != 3 && $0.element != 0 }
        let png = PNG.encode(width: width, height: height, rgba: rgba)
        do {
            try Data(png).write(to: URL(fileURLWithPath: path))
        } catch {
            return "cannot write \(path): \(error)"
        }
        return "\(path): \(displayName) \(how) \(id) (\(s.name)), \(width)x\(height)" + (rotation == 0 ? "" : " (turned \(rotation)°)")
            + ", \(png.count) bytes" + (nonzero ? "" : ", all black")
    }
}

extension IOSurfaceHostService {
    func presentedFrameIsBlack(_ record: FrameRecord?) -> Bool? {
        guard let record, record.surface != 0, let s = surface(id: record.surface), s.bytesPerElement == 4,
              s.width > 0, s.height > 0, UInt64(s.bytesPerRow * (s.height - 1) + s.width * 4) <= s.memory.size else { return nil }
        return PanelPicture.isBlack(UnsafeRawPointer(s.memory.host), width: s.width, height: s.height, bytesPerRow: s.bytesPerRow)
    }
}
