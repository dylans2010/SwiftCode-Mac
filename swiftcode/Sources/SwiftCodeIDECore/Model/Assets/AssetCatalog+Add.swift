import Foundation

extension AssetCatalog {
    public static func newSetName(forTag tag: Int) -> (base: String, ext: String)? {
        let t = AddMenuTags.self
        let otherIndex = tag - t.otherKindBase
        switch tag {
        case 0: return ("Image", "imageset")
        case 1: return ("Color", "colorset")
        case 2, 3, t.watchIcon: return ("AppIcon", "appiconset")
        case t.visionIcon: return ("AppIcon", "solidimagestack")
        case t.tvIcon: return ("App Icon & Top Shelf Image", "brandassets")
        case t.messagesIcon: return ("iMessage App Icon", "stickersiconset")
        default:
            guard otherSetTitles.indices.contains(otherIndex) else { return nil }
            let o = otherSetTitles[otherIndex]
            return (o.defaultName, o.kind.rawValue)
        }
    }

    @discardableResult
    public func addSet(tag: Int, named name: String? = nil, in dir: URL) throws -> AssetSet {
        guard let (base, ext) = Self.newSetName(forTag: tag) else { throw CocoaError(.featureUnsupported) }
        let t = AddMenuTags.self
        let group = relativePath(dir)
        let n = name ?? Self.uniqueName(base, ext: ext, in: dir)
        var set: AssetSet
        switch tag {
        case 0: set = try addImageSet(named: n, in: group)
        case 1: set = try addColorSet(named: n, in: group)
        case 2: set = try addMacAppIconSet(named: n, in: dir)
        case 3: set = try addSingleSizeAppIcon(platform: "ios", named: n, in: dir)
        case t.watchIcon: set = try addSingleSizeAppIcon(platform: "watchos", named: n, in: dir)
        case t.visionIcon: set = try addVisionOSAppIcon(named: n, in: dir)
        case t.tvIcon: set = try addTVBrandAssets(named: n, in: dir)
        case t.messagesIcon: set = try addMessagesIcon(named: n, in: dir)
        default: set = try addSet(Self.otherSetTitles[tag - t.otherKindBase].kind, named: n, in: group)
        }
        set.group = sets().first { Self.same($0.url, set.url) }?.group ?? set.group
        return set
    }

    public func insertionDirectory(folder: URL?, set: AssetSet?) -> URL {
        if let folder { return folder }
        if let set { return set.kind.isContainer ? set.url : set.url.deletingLastPathComponent() }
        return url
    }

    public static func isInsideStickerPack(_ dir: URL) -> Bool {
        let p = dir.standardizedFileURL.path
        return p.hasSuffix(".stickerpack") || p.contains(".stickerpack/")
    }

    @discardableResult
    public func rename(_ item: URL, to name: String) throws -> URL {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !n.contains("/"), !relativePath(item).isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        let ext = Kind(rawValue: item.pathExtension) == nil ? "" : item.pathExtension
        let dest = item.deletingLastPathComponent().appendingPathComponent(ext.isEmpty ? n : "\(n).\(ext)")
        guard !Self.same(dest, item) else { return item }
        guard !FileManager.default.fileExists(atPath: dest.path) else { throw CocoaError(.fileWriteFileExists) }
        try FileManager.default.moveItem(at: item, to: dest)
        return dest
    }
}
