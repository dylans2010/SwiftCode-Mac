import Foundation

// MARK: - Offline documentation symbols (Wave 19 slice A)
//
// The documentation browser's model layer: Dylan's own
// `DocumentationBrowserView.swift` models (`DocSymbol`,
// `DocCSectionData` / collection / group / topic), ported verbatim
// under MIT, plus the 57-topic catalogue.
//
// The catalogue is the 57 names on which Legacy's
// `Documentation.sqlite` and `SwiftCode/Resources/DocSymbols.json`
// agree exactly (verified with python3 sqlite3, read-only; the
// 13 framework-level entries take the sqlite's `article` kind —
// the JSON file's `class` for them is Legacy's own sloppiness).
// `docPath` is the real DocC path, derived by the same rule the
// destination's `EnginesDocs.resolveCandidates` uses with a
// framework (symbol → `documentation/<fw>/<name>`; a topic that
// IS the framework → the framework root `documentation/<fw>`);
// the cache overwrites it with the fetched canonical path.
// Legacy's book-slug paths (`/documentation/developerdocumentation/<name>`)
// are NOT used: they are not real Apple URLs and would 404.
//
// Behaviour source: Legacy
// `SwiftCode/Features/AdvancedTools/Views/DocumentationBrowserView.swift`
// (DocSymbol, DocC models, defaultSections, platformDefaults).
// Spec: `specs/ide/wave19-docs.md` §§2, 5.

/// One offline documentation topic: a DocC page, fetched live once
/// and served from the local cache afterwards.
public struct DocSymbol: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    /// "class", "struct", "protocol", "func", "actor", "macro", "article".
    public let kind: String
    public let framework: String
    public let summary: String
    public let syntax: String
    /// Platform -> introduced version, e.g. ["macOS": "10.15"].
    public let platforms: [String: String]
    public let inheritsFrom: String?
    public let conformsTo: [String]
    /// First code listing from the DocC page; empty when the page
    /// has none (the UI hides the sample section instead of showing
    /// a synthetic stub).
    public let codeSample: String
    public let availability: String
    public let seeAlso: [String]
    /// Real DocC path, e.g. "/documentation/swiftui/vstack".
    public let docPath: String

    public init(
        name: String,
        kind: String,
        framework: String,
        summary: String,
        syntax: String,
        platforms: [String: String],
        inheritsFrom: String? = nil,
        conformsTo: [String] = [],
        codeSample: String = "",
        availability: String = "",
        seeAlso: [String] = [],
        docPath: String = ""
    ) {
        self.name = name
        self.kind = kind
        self.framework = framework
        self.summary = summary
        self.syntax = syntax
        self.platforms = platforms
        self.inheritsFrom = inheritsFrom
        self.conformsTo = conformsTo
        self.codeSample = codeSample
        self.availability = availability
        self.seeAlso = seeAlso
        self.docPath = docPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.kind = try container.decode(String.self, forKey: .kind)
        self.framework = try container.decode(String.self, forKey: .framework)
        self.summary = try container.decode(String.self, forKey: .summary)
        self.syntax = try container.decode(String.self, forKey: .syntax)
        self.platforms = try container.decodeIfPresent([String: String].self, forKey: .platforms) ?? [:]
        self.inheritsFrom = try container.decodeIfPresent(String.self, forKey: .inheritsFrom)
        self.conformsTo = try container.decodeIfPresent([String].self, forKey: .conformsTo) ?? []
        self.codeSample = try container.decodeIfPresent(String.self, forKey: .codeSample) ?? ""
        self.availability = try container.decodeIfPresent(String.self, forKey: .availability) ?? ""
        self.seeAlso = try container.decodeIfPresent([String].self, forKey: .seeAlso) ?? []
        self.docPath = try container.decodeIfPresent(String.self, forKey: .docPath) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case name, kind, framework, summary, syntax, platforms, inheritsFrom, conformsTo, codeSample, availability, seeAlso, docPath
    }
}

// MARK: - Documentation hierarchy (sidebar navigation)

public struct DocCSectionData: Identifiable, Hashable, Sendable {
    public var id: String { title }
    public let title: String
    public let icon: String
    public var collections: [DocCCollectionData]

    public init(title: String, icon: String, collections: [DocCCollectionData]) {
        self.title = title
        self.icon = icon
        self.collections = collections
    }
}

public struct DocCCollectionData: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let title: String
    public let path: String
    public let icon: String
    public var groups: [DocCGroupData]

    public init(title: String, path: String, icon: String, groups: [DocCGroupData]) {
        self.title = title
        self.path = path
        self.icon = icon
        self.groups = groups
    }
}

public struct DocCGroupData: Identifiable, Hashable, Sendable {
    public var id: String { title }
    public let title: String
    public var items: [DocCTopicData]

    public init(title: String, items: [DocCTopicData]) {
        self.title = title
        self.items = items
    }
}

public struct DocCTopicData: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let title: String
    public let path: String

    public init(title: String, path: String) {
        self.title = title
        self.path = path
    }
}

// MARK: - The 57-topic catalogue

/// One catalogue entry: the fetch key for one offline topic.
public struct DocCatalogueTopic: Sendable, Hashable {
    public let name: String
    public let kind: String
    public let framework: String
    /// Real DocC path without the leading slash, e.g.
    /// "documentation/swiftui/vstack".
    public let docPath: String

    public init(name: String, kind: String, framework: String, docPath: String) {
        self.name = name
        self.kind = kind
        self.framework = framework
        self.docPath = docPath
    }
}

public enum DocumentationCatalogue {
    /// The 57 topics, ordered by framework then name (the sqlite's
    /// order). The live fetch corrects each topic's kind and
    /// canonical path; the catalogue is the fetch list, not the
    /// displayed data.
    public static let topics: [DocCatalogueTopic] = [
        DocCatalogueTopic(name: "AVAudioSession", kind: "class", framework: "AVFoundation", docPath: "documentation/avfoundation/avaudiosession"),
        DocCatalogueTopic(name: "AVFoundation", kind: "article", framework: "AVFoundation", docPath: "documentation/avfoundation"),
        DocCatalogueTopic(name: "AVPlayer", kind: "class", framework: "AVFoundation", docPath: "documentation/avfoundation/avplayer"),
        DocCatalogueTopic(name: "AppIntent", kind: "protocol", framework: "AppIntents", docPath: "documentation/appintents/appintent"),
        DocCatalogueTopic(name: "AppIntents", kind: "article", framework: "AppIntents", docPath: "documentation/appintents"),
        DocCatalogueTopic(name: "AppShortcut", kind: "struct", framework: "AppIntents", docPath: "documentation/appintents/appshortcut"),
        DocCatalogueTopic(name: "AppKit", kind: "article", framework: "AppKit", docPath: "documentation/appkit"),
        DocCatalogueTopic(name: "NSView", kind: "class", framework: "AppKit", docPath: "documentation/appkit/nsview"),
        DocCatalogueTopic(name: "NSViewController", kind: "class", framework: "AppKit", docPath: "documentation/appkit/nsviewcontroller"),
        DocCatalogueTopic(name: "NSWindow", kind: "class", framework: "AppKit", docPath: "documentation/appkit/nswindow"),
        DocCatalogueTopic(name: "AnyPublisher", kind: "struct", framework: "Combine", docPath: "documentation/combine/anypublisher"),
        DocCatalogueTopic(name: "Combine", kind: "article", framework: "Combine", docPath: "documentation/combine"),
        DocCatalogueTopic(name: "PassthroughSubject", kind: "class", framework: "Combine", docPath: "documentation/combine/passthroughsubject"),
        DocCatalogueTopic(name: "Publisher", kind: "protocol", framework: "Combine", docPath: "documentation/combine/publisher"),
        DocCatalogueTopic(name: "CoreData", kind: "article", framework: "CoreData", docPath: "documentation/coredata"),
        DocCatalogueTopic(name: "NSManagedObject", kind: "class", framework: "CoreData", docPath: "documentation/coredata/nsmanagedobject"),
        DocCatalogueTopic(name: "NSPersistentContainer", kind: "class", framework: "CoreData", docPath: "documentation/coredata/nspersistentcontainer"),
        DocCatalogueTopic(name: "CGContext", kind: "class", framework: "CoreGraphics", docPath: "documentation/coregraphics/cgcontext"),
        DocCatalogueTopic(name: "CGRect", kind: "struct", framework: "CoreGraphics", docPath: "documentation/coregraphics/cgrect"),
        DocCatalogueTopic(name: "CoreGraphics", kind: "article", framework: "CoreGraphics", docPath: "documentation/coregraphics"),
        DocCatalogueTopic(name: "Data", kind: "struct", framework: "Foundation", docPath: "documentation/foundation/data"),
        DocCatalogueTopic(name: "Date", kind: "struct", framework: "Foundation", docPath: "documentation/foundation/date"),
        DocCatalogueTopic(name: "FileManager", kind: "class", framework: "Foundation", docPath: "documentation/foundation/filemanager"),
        DocCatalogueTopic(name: "Foundation", kind: "article", framework: "Foundation", docPath: "documentation/foundation"),
        DocCatalogueTopic(name: "JSONDecoder", kind: "class", framework: "Foundation", docPath: "documentation/foundation/jsondecoder"),
        DocCatalogueTopic(name: "URL", kind: "struct", framework: "Foundation", docPath: "documentation/foundation/url"),
        DocCatalogueTopic(name: "URLSession", kind: "class", framework: "Foundation", docPath: "documentation/foundation/urlsession"),
        DocCatalogueTopic(name: "MTLCommandQueue", kind: "protocol", framework: "Metal", docPath: "documentation/metal/mtlcommandqueue"),
        DocCatalogueTopic(name: "MTLDevice", kind: "protocol", framework: "Metal", docPath: "documentation/metal/mtldevice"),
        DocCatalogueTopic(name: "MTLRenderPipelineState", kind: "protocol", framework: "Metal", docPath: "documentation/metal/mtlrenderpipelinestate"),
        DocCatalogueTopic(name: "Metal", kind: "article", framework: "Metal", docPath: "documentation/metal"),
        DocCatalogueTopic(name: "Actor", kind: "protocol", framework: "Swift", docPath: "documentation/swift/actor"),
        DocCatalogueTopic(name: "Array", kind: "struct", framework: "Swift", docPath: "documentation/swift/array"),
        DocCatalogueTopic(name: "Dictionary", kind: "struct", framework: "Swift", docPath: "documentation/swift/dictionary"),
        DocCatalogueTopic(name: "Swift", kind: "article", framework: "Swift", docPath: "documentation/swift"),
        DocCatalogueTopic(name: "Task", kind: "struct", framework: "Swift", docPath: "documentation/swift/task"),
        DocCatalogueTopic(name: "Model", kind: "article", framework: "SwiftData", docPath: "documentation/swiftdata/model"),
        DocCatalogueTopic(name: "ModelContainer", kind: "class", framework: "SwiftData", docPath: "documentation/swiftdata/modelcontainer"),
        DocCatalogueTopic(name: "ModelContext", kind: "class", framework: "SwiftData", docPath: "documentation/swiftdata/modelcontext"),
        DocCatalogueTopic(name: "SwiftData", kind: "article", framework: "SwiftData", docPath: "documentation/swiftdata"),
        DocCatalogueTopic(name: "App", kind: "protocol", framework: "SwiftUI", docPath: "documentation/swiftui/app"),
        DocCatalogueTopic(name: "Binding", kind: "struct", framework: "SwiftUI", docPath: "documentation/swiftui/binding"),
        DocCatalogueTopic(name: "Button", kind: "struct", framework: "SwiftUI", docPath: "documentation/swiftui/button"),
        DocCatalogueTopic(name: "Environment", kind: "struct", framework: "SwiftUI", docPath: "documentation/swiftui/environment"),
        DocCatalogueTopic(name: "List", kind: "struct", framework: "SwiftUI", docPath: "documentation/swiftui/list"),
        DocCatalogueTopic(name: "NavigationStack", kind: "struct", framework: "SwiftUI", docPath: "documentation/swiftui/navigationstack"),
        DocCatalogueTopic(name: "State", kind: "struct", framework: "SwiftUI", docPath: "documentation/swiftui/state"),
        DocCatalogueTopic(name: "SwiftUI", kind: "article", framework: "SwiftUI", docPath: "documentation/swiftui"),
        DocCatalogueTopic(name: "Text", kind: "struct", framework: "SwiftUI", docPath: "documentation/swiftui/text"),
        DocCatalogueTopic(name: "VStack", kind: "struct", framework: "SwiftUI", docPath: "documentation/swiftui/vstack"),
        DocCatalogueTopic(name: "View", kind: "protocol", framework: "SwiftUI", docPath: "documentation/swiftui/view"),
        DocCatalogueTopic(name: "UIButton", kind: "class", framework: "UIKit", docPath: "documentation/uikit/uibutton"),
        DocCatalogueTopic(name: "UIKit", kind: "article", framework: "UIKit", docPath: "documentation/uikit"),
        DocCatalogueTopic(name: "UITableView", kind: "class", framework: "UIKit", docPath: "documentation/uikit/uitableview"),
        DocCatalogueTopic(name: "UIView", kind: "class", framework: "UIKit", docPath: "documentation/uikit/uiview"),
        DocCatalogueTopic(name: "UIViewController", kind: "class", framework: "UIKit", docPath: "documentation/uikit/uiviewcontroller"),
        DocCatalogueTopic(name: "UIWindow", kind: "class", framework: "UIKit", docPath: "documentation/uikit/uiwindow"),
    ]

    /// The 12 frameworks, in the hub's display order.
    public static let frameworks: [String] = [
        "SwiftUI", "Swift", "Foundation", "AppKit", "UIKit",
        "Combine", "SwiftData", "CoreData", "Metal", "CoreGraphics",
        "AVFoundation", "AppIntents",
    ]

    /// Per-framework platform defaults (Legacy's `platformDefaults`,
    /// ported verbatim) — used only when a fetched page lists no
    /// availability of its own.
    public static let platformDefaults: [String: [String: String]] = [
        "SwiftUI": ["iOS": "13.0", "macOS": "10.15", "watchOS": "6.0", "tvOS": "13.0", "visionOS": "1.0"],
        "SwiftData": ["iOS": "17.0", "macOS": "14.0", "watchOS": "10.0", "tvOS": "17.0", "visionOS": "1.0"],
        "AppIntents": ["iOS": "16.0", "macOS": "13.0", "watchOS": "9.0", "tvOS": "16.0", "visionOS": "1.0"],
        "Combine": ["iOS": "13.0", "macOS": "10.15", "watchOS": "6.0", "tvOS": "13.0", "visionOS": "1.0"],
        "Swift": ["iOS": "15.0", "macOS": "12.0", "watchOS": "8.0", "tvOS": "15.0", "visionOS": "1.0"],
        "Foundation": ["iOS": "7.0", "macOS": "10.9", "watchOS": "2.0", "tvOS": "9.0", "visionOS": "1.0"],
        "UIKit": ["iOS": "2.0", "macOS": "11.0", "watchOS": "2.0", "tvOS": "9.0", "visionOS": "1.0"],
        "AppKit": ["iOS": "13.0", "macOS": "10.0", "watchOS": "6.0", "tvOS": "13.0", "visionOS": "1.0"],
        "CoreData": ["iOS": "3.0", "macOS": "10.4", "watchOS": "2.0", "tvOS": "9.0", "visionOS": "1.0"],
        "CoreGraphics": ["iOS": "2.0", "macOS": "10.0", "watchOS": "2.0", "tvOS": "9.0", "visionOS": "1.0"],
        "Metal": ["iOS": "8.0", "macOS": "10.11", "watchOS": "6.0", "tvOS": "9.0", "visionOS": "1.0"],
        "AVFoundation": ["iOS": "4.0", "macOS": "10.7", "watchOS": "6.0", "tvOS": "9.0", "visionOS": "1.0"],
    ]

    /// The sidebar sections: Legacy's five section buckets, but
    /// with collections = the 12 frameworks and kind-groups holding
    /// only the 57 catalogue topics (Legacy's hardcoded tree listed
    /// topics outside the 57 — navigation into the bundled archive,
    /// not the offline index — so it is not reproduced).
    public static func defaultSections() -> [DocCSectionData] {
        func icon(for title: String) -> String {
            switch title {
            case "SwiftUI": return "square.stack.3d.down.right.fill"
            case "UIKit": return "apps.iphone"
            case "AppKit": return "macwindow"
            case "Foundation": return "cube.box.fill"
            case "Swift": return "swift"
            case "Combine": return "waveform.path.ecg"
            case "SwiftData": return "cylinder.split.1x2.fill"
            case "CoreData": return "internaldrive.fill"
            case "Metal": return "cpu.fill"
            case "CoreGraphics": return "paintpalette.fill"
            case "AVFoundation": return "play.tv.fill"
            case "AppIntents": return "bolt.badge.automatic.fill"
            default: return "doc.text.fill"
            }
        }
        func kindGroupTitle(_ kind: String) -> String {
            switch kind {
            case "class": return "Classes"
            case "struct": return "Structs"
            case "protocol": return "Protocols"
            default: return "Articles"
            }
        }
        func collection(for framework: String) -> DocCCollectionData {
            let fwTopics = topics.filter { $0.framework == framework }
            var groups: [DocCGroupData] = []
            for kind in ["class", "struct", "protocol", "article"] {
                let items = fwTopics.filter { $0.kind == kind }
                    .map { DocCTopicData(title: $0.name, path: "/" + $0.docPath) }
                if !items.isEmpty {
                    groups.append(DocCGroupData(title: kindGroupTitle(kind), items: items))
                }
            }
            return DocCCollectionData(
                title: framework, path: "/documentation/\(framework.lowercased())",
                icon: icon(for: framework), groups: groups)
        }
        func section(_ title: String, icon: String, frameworks: [String]) -> DocCSectionData {
            DocCSectionData(title: title, icon: icon,
                            collections: frameworks.map(collection(for:)))
        }
        return [
            section("User Interface", icon: "macwindow.on.rectangle",
                    frameworks: ["SwiftUI", "UIKit", "AppKit"]),
            section("Core & System Services", icon: "gearshape.2.fill",
                    frameworks: ["Foundation", "Swift", "Combine"]),
            section("Data & Persistence", icon: "cylinder.split.1x2.fill",
                    frameworks: ["SwiftData", "CoreData"]),
            section("Graphics & Media", icon: "photo.tv.fill",
                    frameworks: ["Metal", "CoreGraphics", "AVFoundation"]),
            section("System Integration", icon: "app.connected.to.app.below.fill",
                    frameworks: ["AppIntents"]),
        ]
    }
}
