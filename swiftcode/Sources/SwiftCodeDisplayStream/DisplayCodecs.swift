public enum DisplayCodecChoice {
    public static let preference = ["hevc444", "hevc", "h264", "jpeg", "zlib"]

    public static func expectation(_ name: String) -> String {
        switch name {
        case "hevc444", "hevc", "h264": "the guest's full picture rate"
        case "jpeg": "the guest's picture rate at about 20 MB/s, softer colour edges than HEVC 4:4:4"
        case "zlib": "about 4-9 pictures a second and 30-90 MB/s (encode 40-90 ms a picture)"
        default: "an unknown rate"
        }
    }

    public static func wishes(first: String?) -> [String] {
        guard let first, let i = preference.firstIndex(of: first) else { return preference }
        return Array(preference[i...])
    }

    public static func decodable(wishes: [String], problem: (String) -> String?) -> (usable: [String], missing: [(name: String, why: String)]) {
        var usable: [String] = [], missing: [(String, String)] = []
        for w in wishes {
            if let why = problem(w) { missing.append((w, why)) } else { usable.append(w) }
        }
        return (usable, missing)
    }

    public static func serverPick(hello: DisplayClientHello, offered: [String]) -> String {
        if let list = hello.encodings, let e = list.first(where: offered.contains) { return e }
        if offered.contains(hello.encoding) { return hello.encoding }
        return offered.first ?? "zlib"
    }

    public static func warning(viewer: String, wishes: [String], missing: [(name: String, why: String)], offered: [String]?, chosen: String) -> String? {
        guard let best = wishes.first, best != chosen else { return nil }
        var reasons: [String] = []
        for w in wishes {
            if w == chosen { break }
            if let m = missing.first(where: { $0.name == w }) { reasons.append("\(w): \(m.why)") }
            else if let offered, !offered.contains(w) { reasons.append("\(w): the server does not offer it (it offers \(offered.joined(separator: ", ")))") }
        }
        return "\(viewer): WARNING: the stream falls back to \(chosen), expect \(expectation(chosen)). "
            + (reasons.isEmpty ? "" : "Better encodings are missing: " + reasons.joined(separator: "; ") + ". ")
            + "Choose one with --encoding."
    }
}
