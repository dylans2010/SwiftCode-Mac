import Foundation
import SwiftCodePlist
import SwiftCodeProject

public enum XcodeGenSpecError: Error, LocalizedError, Equatable, Sendable {
    case yaml(line: Int, message: String)
    case unsupported(path: String, detail: String)
    case invalid(path: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .yaml(let line, let message):
            "project.yml line \(line): \(message)"
        case .unsupported(let path, let detail):
            "Unsupported XcodeGen key '\(path)': \(detail)"
        case .invalid(let path, let message):
            "Invalid XcodeGen spec at '\(path)': \(message)"
        }
    }
}

public enum XcodeGenYAMLValue: Sendable {
    case string(String)
    case bool(Bool)
    case map([(String, XcodeGenYAMLValue)])
    case list([XcodeGenYAMLValue])

    public var map: [(String, XcodeGenYAMLValue)]? {
        if case .map(let entries) = self { return entries }
        return nil
    }

    public var list: [XcodeGenYAMLValue]? {
        if case .list(let items) = self { return items }
        return nil
    }

    public var scalar: String? {
        switch self {
        case .string(let s): return s
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    public subscript(key: String) -> XcodeGenYAMLValue? {
        map?.first { $0.0 == key }?.1
    }
}

public enum XcodeGenYAMLParser {
    private struct Line {
        var number: Int
        var indent: Int
        var text: String
    }

    public static func parse(_ text: String) throws -> XcodeGenYAMLValue {
        var lines: [Line] = []
        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let stripped = stripComment(raw)
            let trimmed = stripped.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            var indent = 0
            for ch in stripped {
                guard ch == " " else { break }
                indent += 1
            }
            if raw.prefix(while: { $0 == " " || $0 == "\t" }).contains("\t") {
                throw XcodeGenSpecError.yaml(line: index + 1, message: "tabs are not allowed for indentation")
            }
            lines.append(Line(number: index + 1, indent: indent, text: trimmed))
        }
        guard !lines.isEmpty else {
            throw XcodeGenSpecError.yaml(line: 1, message: "the spec is empty")
        }
        var i = 0
        let value = try parseBlock(lines, &i, lines[0].indent)
        if i < lines.count {
            throw XcodeGenSpecError.yaml(line: lines[i].number, message: "unexpected content after the top-level mapping")
        }
        return value
    }

    private static func stripComment(_ line: String) -> String {
        var inSingle = false
        var inDouble = false
        var previous: Character = " "
        for (offset, ch) in line.enumerated() {
            switch ch {
            case "'" where !inDouble: inSingle.toggle()
            case "\"" where !inSingle: inDouble.toggle()
            case "#" where !inSingle && !inDouble && (previous == " " || previous == "\t" || offset == 0):
                return String(line.prefix(offset))
            default: break
            }
            previous = ch
        }
        return line
    }

    private static func parseBlock(_ lines: [Line], _ i: inout Int, _ indent: Int) throws -> XcodeGenYAMLValue {
        guard i < lines.count else { return .map([]) }
        if lines[i].indent < indent { return .map([]) }
        if lines[i].text == "-" || lines[i].text.hasPrefix("- ") {
            return try parseList(lines, &i, indent)
        }
        return try parseMap(lines, &i, indent)
    }

    private static func parseMapPair(_ lines: [Line], _ i: inout Int, _ indent: Int) throws -> (String, XcodeGenYAMLValue) {
        let line = lines[i]
        guard let colon = firstColon(line.text) else {
            throw XcodeGenSpecError.yaml(line: line.number, message: "expected 'key: value'")
        }
        let key = String(line.text[..<colon]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            throw XcodeGenSpecError.yaml(line: line.number, message: "empty key")
        }
        let rest = String(line.text[line.text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        i += 1
        if rest.isEmpty {
            if i < lines.count && lines[i].indent > indent {
                return (key, try parseBlock(lines, &i, lines[i].indent))
            }
            return (key, .map([]))
        }
        return (key, try parseScalar(rest, line: line.number))
    }

    private static func parseMap(_ lines: [Line], _ i: inout Int, _ indent: Int) throws -> XcodeGenYAMLValue {
        var entries: [(String, XcodeGenYAMLValue)] = []
        while i < lines.count {
            let line = lines[i]
            if line.indent < indent { break }
            if line.indent > indent {
                throw XcodeGenSpecError.yaml(line: line.number, message: "unexpected indentation")
            }
            if line.text == "-" || line.text.hasPrefix("- ") { break }
            entries.append(try parseMapPair(lines, &i, indent))
        }
        return .map(entries)
    }

    private static func parseList(_ lines: [Line], _ i: inout Int, _ indent: Int) throws -> XcodeGenYAMLValue {
        var items: [XcodeGenYAMLValue] = []
        while i < lines.count {
            let line = lines[i]
            if line.indent != indent { break }
            guard line.text == "-" || line.text.hasPrefix("- ") else { break }
            let rest = line.text == "-" ? "" : String(line.text.dropFirst(2))
            i += 1
            if rest.isEmpty {
                if i < lines.count && lines[i].indent > indent {
                    items.append(try parseBlock(lines, &i, lines[i].indent))
                } else {
                    items.append(.string(""))
                }
                continue
            }
            if let colon = firstColon(rest), !rest.hasPrefix("\""), !rest.hasPrefix("'"), !rest.hasPrefix("[") {
                var entries: [(String, XcodeGenYAMLValue)] = []
                let key = String(rest[..<colon]).trimmingCharacters(in: .whitespaces)
                let valueText = String(rest[rest.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if valueText.isEmpty {
                    if i < lines.count && lines[i].indent > indent {
                        entries.append((key, try parseBlock(lines, &i, lines[i].indent)))
                    } else {
                        entries.append((key, .map([])))
                    }
                } else {
                    entries.append((key, try parseScalar(valueText, line: line.number)))
                }
                while i < lines.count && lines[i].indent == indent + 2
                        && !(lines[i].text == "-" || lines[i].text.hasPrefix("- ")) {
                    entries.append(try parseMapPair(lines, &i, indent + 2))
                }
                items.append(.map(entries))
                continue
            }
            items.append(try parseScalar(rest, line: line.number))
        }
        return .list(items)
    }

    private static func firstColon(_ text: String) -> String.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == ":" {
                let next = text.index(after: index)
                if next == text.endIndex || text[next] == " " {
                    return index
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func parseScalar(_ text: String, line: Int) throws -> XcodeGenYAMLValue {
        if text.hasPrefix("[") {
            guard text.hasSuffix("]") else {
                throw XcodeGenSpecError.yaml(line: line, message: "unterminated inline list '\(text)'")
            }
            let inner = String(text.dropFirst().dropLast())
            if inner.trimmingCharacters(in: .whitespaces).isEmpty { return .list([]) }
            return .list(try splitTopLevel(inner, line: line).map { try parseScalar($0, line: line) })
        }
        if text.hasPrefix("{") {
            guard text.hasSuffix("}") else {
                throw XcodeGenSpecError.yaml(line: line, message: "unterminated inline map '\(text)'")
            }
            let inner = String(text.dropFirst().dropLast())
            if inner.trimmingCharacters(in: .whitespaces).isEmpty { return .map([]) }
            var entries: [(String, XcodeGenYAMLValue)] = []
            for part in try splitTopLevel(inner, line: line) {
                guard let colon = firstColon(part) else {
                    throw XcodeGenSpecError.yaml(line: line, message: "expected 'key: value' in inline map '\(part)'")
                }
                let key = String(part[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(part[part.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                entries.append((key, try parseScalar(value, line: line)))
            }
            return .map(entries)
        }
        if text.hasPrefix("\"") {
            return .string(try parseDoubleQuoted(text, line: line))
        }
        if text.hasPrefix("'") {
            return .string(try parseSingleQuoted(text, line: line))
        }
        if text.hasPrefix("&") || text.hasPrefix("*") || text == "|" || text == ">" || text.hasPrefix("|") || text.hasPrefix(">") {
            throw XcodeGenSpecError.yaml(line: line, message: "anchors, aliases, and block scalars are outside the supported YAML subset")
        }
        switch text {
        case "true": return .bool(true)
        case "false": return .bool(false)
        default: return .string(text)
        }
    }

    private static func parseDoubleQuoted(_ text: String, line: Int) throws -> String {
        guard text.count >= 2, text.hasSuffix("\"") else {
            throw XcodeGenSpecError.yaml(line: line, message: "unterminated double-quoted string '\(text)'")
        }
        var out = ""
        var chars = text.dropFirst().dropLast().makeIterator()
        while let ch = chars.next() {
            if ch == "\\" {
                guard let esc = chars.next() else { break }
                switch esc {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                default: out.append(esc)
                }
            } else {
                out.append(ch)
            }
        }
        return out
    }

    private static func parseSingleQuoted(_ text: String, line: Int) throws -> String {
        guard text.count >= 2, text.hasSuffix("'") else {
            throw XcodeGenSpecError.yaml(line: line, message: "unterminated single-quoted string '\(text)'")
        }
        return String(text.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
    }

    private static func splitTopLevel(_ text: String, line: Int) throws -> [String] {
        var parts: [String] = []
        var depth = 0
        var inSingle = false
        var inDouble = false
        var current = ""
        for ch in text {
            switch ch {
            case "'" where !inDouble: inSingle.toggle(); current.append(ch)
            case "\"" where !inSingle: inDouble.toggle(); current.append(ch)
            case "[", "{" where !inSingle && !inDouble: depth += 1; current.append(ch)
            case "]", "}" where !inSingle && !inDouble: depth -= 1; current.append(ch)
            case "," where !inSingle && !inDouble && depth == 0:
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            default: current.append(ch)
            }
        }
        if inSingle || inDouble || depth != 0 {
            throw XcodeGenSpecError.yaml(line: line, message: "unbalanced inline collection '\(text)'")
        }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        return parts.filter { !$0.isEmpty }
    }
}

public struct XcodeGenSettings: Sendable {
    public var base: [(String, String)] = []
    public var configs: [String: [(String, String)]] = [:]

    public init() {}

    public var configNames: Set<String> { Set(configs.keys) }

    public func merged(for config: String) -> [(String, String)] {
        var out = base
        for (key, value) in configs[config] ?? [] {
            if let index = out.firstIndex(where: { $0.0 == key }) {
                out[index] = (key, value)
            } else {
                out.append((key, value))
            }
        }
        return out
    }
}

public struct XcodeGenOptions: Equatable, Sendable {
    public var bundleIdPrefix: String?
    public var deploymentTarget: [String: String] = [:]
    public var developmentLanguage: String?
    public var xcodeVersion: String?
    public var createIntermediateGroups = false
}

public enum XcodeGenTargetType: Equatable, Sendable {
    case application
    case framework
    case staticLibrary
    case dynamicLibrary
    case bundle
    case unitTestBundle
    case uiTestBundle
    case appExtension
    case watchApp
    case watchExtension
    case tool

    public init(specValue: String) throws {
        switch specValue {
        case "application": self = .application
        case "framework": self = .framework
        case "static-library": self = .staticLibrary
        case "dynamic-library": self = .dynamicLibrary
        case "bundle": self = .bundle
        case "unit-test-bundle": self = .unitTestBundle
        case "ui-test-bundle": self = .uiTestBundle
        case "app-extension": self = .appExtension
        case "watch-app": self = .watchApp
        case "watch-extension": self = .watchExtension
        case "tool": self = .tool
        default:
            throw XcodeGenSpecError.unsupported(
                path: "targets.<name>.type",
                detail: "target type '\(specValue)' is not generated. Known types: application, framework, static-library, dynamic-library, bundle, unit-test-bundle, ui-test-bundle, app-extension, watch-app, watch-extension, tool. Run xcodegen for anything else.")
        }
    }

    public var productType: String {
        switch self {
        case .application: "com.apple.product-type.application"
        case .framework: "com.apple.product-type.framework"
        case .staticLibrary: "com.apple.product-type.library.static"
        case .dynamicLibrary: "com.apple.product-type.library.dynamic"
        case .bundle: "com.apple.product-type.bundle"
        case .unitTestBundle: "com.apple.product-type.bundle.unit-test"
        case .uiTestBundle: "com.apple.product-type.bundle.ui-testing"
        case .appExtension: "com.apple.product-type.app-extension"
        case .watchApp: "com.apple.product-type.application.watchapp"
        case .watchExtension: "com.apple.product-type.watchkit-extension"
        case .tool: "com.apple.product-type.tool"
        }
    }

    public var productExtension: String {
        switch self {
        case .application, .watchApp: "app"
        case .framework: "framework"
        case .staticLibrary: "a"
        case .dynamicLibrary: "dylib"
        case .bundle: "bundle"
        case .unitTestBundle, .uiTestBundle: "xctest"
        case .appExtension, .watchExtension: "appex"
        case .tool: ""
        }
    }

    public var productFileType: String {
        switch self {
        case .application, .watchApp: "wrapper.application"
        case .framework: "wrapper.framework"
        case .staticLibrary: "archive.ar"
        case .dynamicLibrary: "compiled.mach-o.dylib"
        case .bundle, .unitTestBundle, .uiTestBundle: "wrapper.cfbundle"
        case .appExtension, .watchExtension: "wrapper.app-extension"
        case .tool: "compiled.mach-o.executable"
        }
    }

    public var isTestBundle: Bool {
        self == .unitTestBundle || self == .uiTestBundle
    }

    public var isApplication: Bool {
        self == .application || self == .watchApp
    }
}

public enum XcodeGenPlatform: Equatable, Sendable {
    case iOS
    case macOS
    case watchOS
    case tvOS
    case visionOS

    public init(specValue: String) throws {
        switch specValue {
        case "iOS": self = .iOS
        case "macOS": self = .macOS
        case "watchOS": self = .watchOS
        case "tvOS": self = .tvOS
        case "visionOS": self = .visionOS
        default:
            throw XcodeGenSpecError.unsupported(
                path: "targets.<name>.platform",
                detail: "platform '\(specValue)' is not generated. Known platforms: iOS, macOS, watchOS, tvOS, visionOS. Run xcodegen for anything else.")
        }
    }

    public var sdkRoot: String {
        switch self {
        case .iOS: "iphoneos"
        case .macOS: "macosx"
        case .watchOS: "watchos"
        case .tvOS: "appletvos"
        case .visionOS: "xros"
        }
    }

    public var deploymentTargetKey: String {
        switch self {
        case .iOS: "IPHONEOS_DEPLOYMENT_TARGET"
        case .macOS: "MACOSX_DEPLOYMENT_TARGET"
        case .watchOS: "WATCHOS_DEPLOYMENT_TARGET"
        case .tvOS: "TVOS_DEPLOYMENT_TARGET"
        case .visionOS: "XROS_DEPLOYMENT_TARGET"
        }
    }

    public var defaultDeploymentTarget: String {
        switch self {
        case .iOS: "18.0"
        case .macOS: "15.0"
        case .watchOS: "11.0"
        case .tvOS: "18.0"
        case .visionOS: "2.0"
        }
    }

    public var deviceSettings: [(String, String)] {
        switch self {
        case .iOS: [("TARGETED_DEVICE_FAMILY", "1,2"), ("SUPPORTED_PLATFORMS", "iphoneos iphonesimulator")]
        case .macOS: []
        case .watchOS: [("TARGETED_DEVICE_FAMILY", "4"), ("SUPPORTED_PLATFORMS", "watchos watchsimulator")]
        case .tvOS: [("TARGETED_DEVICE_FAMILY", "3"), ("SUPPORTED_PLATFORMS", "appletvos appletvsimulator")]
        case .visionOS: [("TARGETED_DEVICE_FAMILY", "7"), ("SUPPORTED_PLATFORMS", "xros xrsimulator")]
        }
    }
}

public struct XcodeGenSource: Equatable, Sendable {
    public var path: String
    public var group: String?
    public var excludes: [String] = []
    public var folderReference = false
}

public struct XcodeGenScript: Equatable, Sendable {
    public var name: String?
    public var script: String
    public var shell: String?
    public var inputFiles: [String] = []
    public var outputFiles: [String] = []
}

public enum XcodeGenDependency: Equatable, Sendable {
    case target(name: String, embed: Bool, link: Bool)
    case package(name: String, product: String?)
    case framework(path: String)
    case sdk(name: String)
}

public struct XcodeGenPackage: Equatable, Sendable {
    public var name: String
    public var url: String
    public var requirement: SwiftPackageRequirement
}

public struct XcodeGenTargetScheme: Equatable, Sendable {
    public var testTargets: [String] = []
    public var config: String?
    public var gatherCoverageData = false
}

public struct XcodeGenTarget: Sendable {
    public var name: String
    public var type: XcodeGenTargetType
    public var platform: XcodeGenPlatform = .iOS
    public var sources: [XcodeGenSource] = []
    public var settings = XcodeGenSettings()
    public var dependencies: [XcodeGenDependency] = []
    public var infoPath: String?
    public var infoProperties: [(String, XcodeGenYAMLValue)]?
    public var entitlementsPath: String?
    public var configFiles: [String: String] = [:]
    public var preBuildScripts: [XcodeGenScript] = []
    public var postBuildScripts: [XcodeGenScript] = []
    public var scheme: XcodeGenTargetScheme?
    public var deploymentTarget: String?
    public var transitivelyLinkDependencies = false
}

public struct XcodeGenScheme: Sendable {
    public var name: String
    public var buildTargets: [(name: String, flags: Set<String>)] = []
    public var runConfig: String?
    public var testConfig: String?
    public var testTargets: [String] = []
    public var profileConfig: String?
    public var analyzeConfig: String?
    public var archiveConfig: String?
    public var gatherCoverageData = false
}

public struct XcodeGenSpec: Sendable {
    public var name: String
    public var options = XcodeGenOptions()
    public var settings = XcodeGenSettings()
    public var targets: [XcodeGenTarget] = []
    public var packages: [XcodeGenPackage] = []
    public var schemes: [XcodeGenScheme] = []
    public var configFiles: [String: String] = [:]
    public var ignoredKeys: [String] = []

    public var configNames: [String] {
        var names = Set<String>()
        names.formUnion(settings.configNames)
        names.formUnion(configFiles.keys)
        for target in targets {
            names.formUnion(target.settings.configNames)
            names.formUnion(target.configFiles.keys)
        }
        for scheme in schemes {
            for config in [scheme.runConfig, scheme.testConfig, scheme.profileConfig, scheme.analyzeConfig, scheme.archiveConfig] {
                if let config { names.insert(config) }
            }
        }
        if names.isEmpty { return ["Debug", "Release"] }
        var ordered: [String] = []
        for preferred in ["Debug", "Release"] where names.contains(preferred) {
            ordered.append(preferred)
        }
        ordered += names.subtracting(ordered).sorted()
        return ordered
    }
}

extension XcodeGenSpec {
    public static func parse(_ text: String) throws -> XcodeGenSpec {
        let yaml = try XcodeGenYAMLParser.parse(text)
        guard let top = yaml.map else {
            throw XcodeGenSpecError.invalid(path: "", message: "the spec must be a mapping with a 'name' and 'targets'")
        }
        var spec = XcodeGenSpec(name: "")
        for (key, value) in top {
            switch key {
            case "name":
                guard let name = value.scalar, !name.isEmpty else {
                    throw XcodeGenSpecError.invalid(path: "name", message: "the project name must be a non-empty string")
                }
                spec.name = name
            case "options":
                spec.options = try parseOptions(value, ignored: &spec.ignoredKeys)
            case "settings":
                spec.settings = try parseSettings(value, path: "settings")
            case "targets":
                spec.targets = try parseTargets(value, ignored: &spec.ignoredKeys)
            case "packages":
                spec.packages = try parsePackages(value)
            case "schemes":
                spec.schemes = try parseSchemes(value, ignored: &spec.ignoredKeys)
            case "configFiles":
                spec.configFiles = try parseConfigFiles(value, path: "configFiles")
            default:
                spec.ignoredKeys.append(key)
            }
        }
        guard !spec.name.isEmpty else {
            throw XcodeGenSpecError.invalid(path: "name", message: "the spec has no project name")
        }
        guard !spec.targets.isEmpty else {
            throw XcodeGenSpecError.invalid(path: "targets", message: "the spec has no targets")
        }
        let targetNames = Set(spec.targets.map(\.name))
        let packageNames = Set(spec.packages.map(\.name))
        for target in spec.targets {
            for dep in target.dependencies {
                switch dep {
                case .target(let name, _, _):
                    guard targetNames.contains(name) else {
                        throw XcodeGenSpecError.invalid(path: "targets.\(target.name).dependencies", message: "no target named '\(name)'")
                    }
                case .package(let name, _):
                    guard packageNames.contains(name) else {
                        throw XcodeGenSpecError.invalid(path: "targets.\(target.name).dependencies", message: "no package named '\(name)'")
                    }
                case .framework, .sdk: break
                }
            }
            for testTarget in target.scheme?.testTargets ?? [] {
                guard targetNames.contains(testTarget) else {
                    throw XcodeGenSpecError.invalid(path: "targets.\(target.name).scheme.testTargets", message: "no target named '\(testTarget)'")
                }
            }
        }
        for scheme in spec.schemes {
            for (targetName, _) in scheme.buildTargets {
                guard targetNames.contains(targetName) else {
                    throw XcodeGenSpecError.invalid(path: "schemes.\(scheme.name).build.targets", message: "no target named '\(targetName)'")
                }
            }
            for testTarget in scheme.testTargets {
                guard targetNames.contains(testTarget) else {
                    throw XcodeGenSpecError.invalid(path: "schemes.\(scheme.name).test.targets", message: "no target named '\(testTarget)'")
                }
            }
        }
        return spec
    }

    private static func parseOptions(_ value: XcodeGenYAMLValue, ignored: inout [String]) throws -> XcodeGenOptions {
        guard let entries = value.map else {
            throw XcodeGenSpecError.invalid(path: "options", message: "expected a mapping")
        }
        var options = XcodeGenOptions()
        for (key, v) in entries {
            switch key {
            case "bundleIdPrefix":
                guard let s = v.scalar else {
                    throw XcodeGenSpecError.invalid(path: "options.bundleIdPrefix", message: "expected a string")
                }
                options.bundleIdPrefix = s
            case "deploymentTarget":
                if let s = v.scalar {
                    options.deploymentTarget = ["*": s]
                } else if let map = v.map {
                    for (platform, version) in map {
                        guard let versionString = version.scalar else {
                            throw XcodeGenSpecError.invalid(path: "options.deploymentTarget.\(platform)", message: "expected a version string")
                        }
                        options.deploymentTarget[platform] = versionString
                    }
                } else {
                    throw XcodeGenSpecError.invalid(path: "options.deploymentTarget", message: "expected a version string or a per-platform mapping")
                }
            case "developmentLanguage":
                options.developmentLanguage = v.scalar
            case "xcodeVersion":
                options.xcodeVersion = v.scalar
            case "createIntermediateGroups":
                if case .bool(let b) = v { options.createIntermediateGroups = b }
            default:
                ignored.append("options.\(key)")
            }
        }
        return options
    }

    private static func parseSettingsMap(_ value: XcodeGenYAMLValue, path: String) throws -> [(String, String)] {
        guard let entries = value.map else {
            throw XcodeGenSpecError.invalid(path: path, message: "expected a mapping of build settings")
        }
        var out: [(String, String)] = []
        for (key, v) in entries {
            switch v {
            case .string(let s): out.append((key, s))
            case .bool(let b): out.append((key, b ? "YES" : "NO"))
            case .list(let items):
                let parts = try items.map { item -> String in
                    guard let s = item.scalar else {
                        throw XcodeGenSpecError.invalid(path: "\(path).\(key)", message: "a settings list may only hold scalars")
                    }
                    return s
                }
                out.append((key, parts.joined(separator: " ")))
            case .map:
                throw XcodeGenSpecError.invalid(path: "\(path).\(key)", message: "a build setting cannot be a mapping")
            }
        }
        return out
    }

    private static func parseSettings(_ value: XcodeGenYAMLValue, path: String) throws -> XcodeGenSettings {
        guard let entries = value.map else {
            throw XcodeGenSpecError.invalid(path: path, message: "expected a mapping with 'base' and/or 'configs'")
        }
        var settings = XcodeGenSettings()
        for (key, v) in entries {
            switch key {
            case "base":
                settings.base = try parseSettingsMap(v, path: "\(path).base")
            case "configs":
                guard let configs = v.map else {
                    throw XcodeGenSpecError.invalid(path: "\(path).configs", message: "expected a mapping of configuration name to settings")
                }
                for (configName, configValue) in configs {
                    settings.configs[configName] = try parseSettingsMap(configValue, path: "\(path).configs.\(configName)")
                }
            default:
                switch v {
                case .string(let s): settings.base.append((key, s))
                case .bool(let b): settings.base.append((key, b ? "YES" : "NO"))
                case .list(let items):
                    let parts = try items.map { item -> String in
                        guard let s = item.scalar else {
                            throw XcodeGenSpecError.invalid(path: "\(path).\(key)", message: "a settings list may only hold scalars")
                        }
                        return s
                    }
                    settings.base.append((key, parts.joined(separator: " ")))
                case .map:
                    throw XcodeGenSpecError.invalid(path: "\(path).\(key)", message: "expected 'base' or 'configs', got a nested mapping")
                }
            }
        }
        return settings
    }

    private static func parseConfigFiles(_ value: XcodeGenYAMLValue, path: String) throws -> [String: String] {
        guard let entries = value.map else {
            throw XcodeGenSpecError.invalid(path: path, message: "expected a mapping of configuration name to .xcconfig path")
        }
        var out: [String: String] = [:]
        for (config, file) in entries {
            guard let filePath = file.scalar, !filePath.isEmpty else {
                throw XcodeGenSpecError.invalid(path: "\(path).\(config)", message: "expected an .xcconfig path")
            }
            out[config] = filePath
        }
        return out
    }

    private static func parseTargets(_ value: XcodeGenYAMLValue, ignored: inout [String]) throws -> [XcodeGenTarget] {
        guard let entries = value.map else {
            throw XcodeGenSpecError.invalid(path: "targets", message: "expected a mapping of target name to target")
        }
        var targets: [XcodeGenTarget] = []
        for (name, v) in entries {
            guard let targetEntries = v.map else {
                throw XcodeGenSpecError.invalid(path: "targets.\(name)", message: "expected a mapping")
            }
            var target = XcodeGenTarget(name: name, type: .application)
            var sawType = false
            for (key, tv) in targetEntries {
                let path = "targets.\(name).\(key)"
                switch key {
                case "type":
                    guard let typeString = tv.scalar else {
                        throw XcodeGenSpecError.invalid(path: path, message: "expected a target type string")
                    }
                    target.type = try XcodeGenTargetType(specValue: typeString)
                    sawType = true
                case "platform":
                    guard let platformString = tv.scalar else {
                        throw XcodeGenSpecError.invalid(path: path, message: "expected a platform string")
                    }
                    target.platform = try XcodeGenPlatform(specValue: platformString)
                case "sources":
                    target.sources = try parseSources(tv, path: path)
                case "settings":
                    target.settings = try parseSettings(tv, path: path)
                case "dependencies":
                    target.dependencies = try parseDependencies(tv, path: path)
                case "info":
                    if let infoPath = tv.scalar {
                        target.infoPath = infoPath
                    } else if let infoMap = tv.map {
                        for (infoKey, infoValue) in infoMap {
                            if infoKey == "path" {
                                guard let p = infoValue.scalar else {
                                    throw XcodeGenSpecError.invalid(path: "\(path).path", message: "expected an Info.plist path")
                                }
                                target.infoPath = p
                            } else if infoKey == "properties" {
                                guard let props = infoValue.map else {
                                    throw XcodeGenSpecError.invalid(path: "\(path).properties", message: "expected a mapping of plist keys to values")
                                }
                                target.infoProperties = props
                            } else {
                                ignored.append("\(path).\(infoKey)")
                            }
                        }
                    } else {
                        throw XcodeGenSpecError.invalid(path: path, message: "expected an Info.plist path or a mapping with 'path'/'properties'")
                    }
                case "entitlements":
                    guard let entitlements = tv.scalar else {
                        throw XcodeGenSpecError.invalid(path: path, message: "expected an entitlements path")
                    }
                    target.entitlementsPath = entitlements
                case "configFiles":
                    target.configFiles = try parseConfigFiles(tv, path: path)
                case "preBuildScripts":
                    target.preBuildScripts = try parseScripts(tv, path: path)
                case "postBuildScripts":
                    target.postBuildScripts = try parseScripts(tv, path: path)
                case "scheme":
                    target.scheme = try parseTargetScheme(tv, path: path)
                case "deploymentTarget":
                    guard let deploymentTarget = tv.scalar else {
                        throw XcodeGenSpecError.invalid(path: path, message: "expected a version string")
                    }
                    target.deploymentTarget = deploymentTarget
                case "transitivelyLinkDependencies":
                    if case .bool(let b) = tv { target.transitivelyLinkDependencies = b }
                default:
                    ignored.append(path)
                }
            }
            guard sawType else {
                throw XcodeGenSpecError.invalid(path: "targets.\(name).type", message: "every target needs a 'type'")
            }
            targets.append(target)
        }
        return targets
    }

    private static func parseSources(_ value: XcodeGenYAMLValue, path: String) throws -> [XcodeGenSource] {
        guard let items = value.list else {
            throw XcodeGenSpecError.invalid(path: path, message: "expected a list of source paths")
        }
        var sources: [XcodeGenSource] = []
        for item in items {
            if let pathString = item.scalar {
                sources.append(XcodeGenSource(path: pathString))
            } else if let map = item.map {
                var source = XcodeGenSource(path: "")
                for (key, v) in map {
                    switch key {
                    case "path":
                        guard let p = v.scalar else {
                            throw XcodeGenSpecError.invalid(path: path, message: "a source 'path' must be a string")
                        }
                        source.path = p
                    case "group":
                        source.group = v.scalar
                    case "excludes":
                        guard let excludes = v.list else {
                            throw XcodeGenSpecError.invalid(path: "\(path).excludes", message: "expected a list of paths")
                        }
                        source.excludes = try excludes.map { exclude in
                            guard let s = exclude.scalar else {
                                throw XcodeGenSpecError.invalid(path: "\(path).excludes", message: "expected a path string")
                            }
                            return s
                        }
                    case "type":
                        if v.scalar == "folder" {
                            source.folderReference = true
                        } else if v.scalar == "group" {
                            source.folderReference = false
                        } else {
                            throw XcodeGenSpecError.unsupported(
                                path: path,
                                detail: "source type '\(v.scalar ?? "")' is not generated (only 'group' and 'folder'). Run xcodegen for anything else.")
                        }
                    default:
                        throw XcodeGenSpecError.unsupported(
                            path: "\(path).\(key)",
                            detail: "source option '\(key)' is not generated. Run xcodegen for specs that need it.")
                    }
                }
                guard !source.path.isEmpty else {
                    throw XcodeGenSpecError.invalid(path: path, message: "a source mapping needs a 'path'")
                }
                sources.append(source)
            } else {
                throw XcodeGenSpecError.invalid(path: path, message: "a source must be a path string or a mapping with 'path'")
            }
        }
        return sources
    }

    private static func parseDependencies(_ value: XcodeGenYAMLValue, path: String) throws -> [XcodeGenDependency] {
        guard let items = value.list else {
            throw XcodeGenSpecError.invalid(path: path, message: "expected a list of dependencies")
        }
        var deps: [XcodeGenDependency] = []
        for item in items {
            if let name = item.scalar {
                deps.append(.target(name: name, embed: false, link: true))
                continue
            }
            guard let map = item.map else {
                throw XcodeGenSpecError.invalid(path: path, message: "a dependency must be a name or a mapping")
            }
            var targetName: String?
            var packageName: String?
            var productName: String?
            var frameworkPath: String?
            var sdkName: String?
            var embed = false
            var link = true
            for (key, v) in map {
                switch key {
                case "target":
                    targetName = v.scalar
                case "package":
                    packageName = v.scalar
                case "product":
                    productName = v.scalar
                case "framework":
                    frameworkPath = v.scalar
                case "sdk":
                    sdkName = v.scalar
                case "embed":
                    if case .bool(let b) = v { embed = b }
                case "link":
                    if case .bool(let b) = v { link = b }
                case "carthage":
                    throw XcodeGenSpecError.unsupported(
                        path: path,
                        detail: "Carthage dependencies are not generated: the Carthage build layout (Carthage/Build/<platform>) is outside this generator. Run xcodegen for Carthage specs.")
                default:
                    throw XcodeGenSpecError.unsupported(
                        path: "\(path).\(key)",
                        detail: "dependency option '\(key)' is not generated. Run xcodegen for specs that need it.")
                }
            }
            if let targetName {
                deps.append(.target(name: targetName, embed: embed, link: link))
            } else if let packageName {
                deps.append(.package(name: packageName, product: productName))
            } else if let frameworkPath {
                deps.append(.framework(path: frameworkPath))
            } else if let sdkName {
                deps.append(.sdk(name: sdkName))
            } else {
                throw XcodeGenSpecError.invalid(path: path, message: "a dependency mapping needs 'target', 'package', 'framework', or 'sdk'")
            }
        }
        return deps
    }

    private static func parseScripts(_ value: XcodeGenYAMLValue, path: String) throws -> [XcodeGenScript] {
        guard let items = value.list else {
            throw XcodeGenSpecError.invalid(path: path, message: "expected a list of build scripts")
        }
        var scripts: [XcodeGenScript] = []
        for item in items {
            if let script = item.scalar {
                scripts.append(XcodeGenScript(script: script))
                continue
            }
            guard let map = item.map else {
                throw XcodeGenSpecError.invalid(path: path, message: "a build script must be a script string or a mapping")
            }
            var parsed = XcodeGenScript(script: "")
            for (key, v) in map {
                switch key {
                case "name": parsed.name = v.scalar
                case "script":
                    guard let s = v.scalar else {
                        throw XcodeGenSpecError.invalid(path: "\(path).script", message: "expected a script string")
                    }
                    parsed.script = s
                case "shell": parsed.shell = v.scalar
                case "inputFiles":
                    guard let list = v.list else {
                        throw XcodeGenSpecError.invalid(path: "\(path).inputFiles", message: "expected a list of paths")
                    }
                    parsed.inputFiles = list.compactMap(\.scalar)
                case "outputFiles":
                    guard let list = v.list else {
                        throw XcodeGenSpecError.invalid(path: "\(path).outputFiles", message: "expected a list of paths")
                    }
                    parsed.outputFiles = list.compactMap(\.scalar)
                default:
                    throw XcodeGenSpecError.unsupported(
                        path: "\(path).\(key)",
                        detail: "build script option '\(key)' is not generated. Run xcodegen for specs that need it.")
                }
            }
            guard !parsed.script.isEmpty else {
                throw XcodeGenSpecError.invalid(path: path, message: "a build script mapping needs a 'script'")
            }
            scripts.append(parsed)
        }
        return scripts
    }

    private static func parseTargetScheme(_ value: XcodeGenYAMLValue, path: String) throws -> XcodeGenTargetScheme {
        guard let entries = value.map else {
            throw XcodeGenSpecError.invalid(path: path, message: "expected a mapping with 'testTargets', 'config', or 'gatherCoverageData'")
        }
        var scheme = XcodeGenTargetScheme()
        for (key, v) in entries {
            switch key {
            case "testTargets":
                guard let list = v.list else {
                    throw XcodeGenSpecError.invalid(path: "\(path).testTargets", message: "expected a list of target names")
                }
                scheme.testTargets = list.compactMap(\.scalar)
            case "config":
                scheme.config = v.scalar
            case "gatherCoverageData":
                if case .bool(let b) = v { scheme.gatherCoverageData = b }
            default:
                throw XcodeGenSpecError.unsupported(
                    path: "\(path).\(key)",
                    detail: "target scheme option '\(key)' is not generated. Run xcodegen for specs that need it.")
            }
        }
        return scheme
    }

    private static func parsePackages(_ value: XcodeGenYAMLValue) throws -> [XcodeGenPackage] {
        guard let entries = value.map else {
            throw XcodeGenSpecError.invalid(path: "packages", message: "expected a mapping of package name to package")
        }
        var packages: [XcodeGenPackage] = []
        for (name, v) in entries {
            guard let packageEntries = v.map else {
                throw XcodeGenSpecError.invalid(path: "packages.\(name)", message: "expected a mapping with 'url' and a version rule")
            }
            var url: String?
            var requirement: SwiftPackageRequirement?
            for (key, pv) in packageEntries {
                switch key {
                case "url":
                    url = pv.scalar
                case "path":
                    throw XcodeGenSpecError.unsupported(
                        path: "packages.\(name)",
                        detail: "local packages ('path:') are not generated: the local package must be vendored into the workspace first. Run xcodegen for local-package specs.")
                case "from":
                    guard let version = pv.scalar else {
                        throw XcodeGenSpecError.invalid(path: "packages.\(name).from", message: "expected a version string")
                    }
                    requirement = .upToNextMajor(from: version)
                case "exact":
                    guard let version = pv.scalar else {
                        throw XcodeGenSpecError.invalid(path: "packages.\(name).exact", message: "expected a version string")
                    }
                    requirement = .exact(version)
                case "version":
                    guard let version = pv.scalar else {
                        throw XcodeGenSpecError.invalid(path: "packages.\(name).version", message: "expected a version string")
                    }
                    requirement = .exact(version)
                case "branch":
                    guard let branch = pv.scalar else {
                        throw XcodeGenSpecError.invalid(path: "packages.\(name).branch", message: "expected a branch name")
                    }
                    requirement = .branch(branch)
                case "revision":
                    guard let revision = pv.scalar else {
                        throw XcodeGenSpecError.invalid(path: "packages.\(name).revision", message: "expected a revision")
                    }
                    requirement = .revision(revision)
                case "minVersion":
                    guard let min = pv.scalar else {
                        throw XcodeGenSpecError.invalid(path: "packages.\(name).minVersion", message: "expected a version string")
                    }
                    if case .range(_, let max) = requirement {
                        requirement = .range(from: min, to: max)
                    } else {
                        requirement = .range(from: min, to: min)
                    }
                case "maxVersion":
                    guard let max = pv.scalar else {
                        throw XcodeGenSpecError.invalid(path: "packages.\(name).maxVersion", message: "expected a version string")
                    }
                    if case .range(let min, _) = requirement {
                        requirement = .range(from: min, to: max)
                    } else {
                        requirement = .range(from: max, to: max)
                    }
                default:
                    throw XcodeGenSpecError.unsupported(
                        path: "packages.\(name).\(key)",
                        detail: "package option '\(key)' is not generated. Run xcodegen for specs that need it.")
                }
            }
            guard let url, !url.isEmpty else {
                throw XcodeGenSpecError.invalid(path: "packages.\(name)", message: "a remote package needs a 'url'")
            }
            guard let requirement else {
                throw XcodeGenSpecError.invalid(path: "packages.\(name)", message: "a package needs a version rule ('from', 'exact', 'branch', or 'revision')")
            }
            packages.append(XcodeGenPackage(name: name, url: url, requirement: requirement))
        }
        return packages
    }

    private static func parseSchemes(_ value: XcodeGenYAMLValue, ignored: inout [String]) throws -> [XcodeGenScheme] {
        guard let entries = value.map else {
            throw XcodeGenSpecError.invalid(path: "schemes", message: "expected a mapping of scheme name to scheme")
        }
        var schemes: [XcodeGenScheme] = []
        for (name, v) in entries {
            guard let schemeEntries = v.map else {
                throw XcodeGenSpecError.invalid(path: "schemes.\(name)", message: "expected a mapping")
            }
            var scheme = XcodeGenScheme(name: name)
            for (key, sv) in schemeEntries {
                let path = "schemes.\(name).\(key)"
                switch key {
                case "build":
                    guard let buildEntries = sv.map else {
                        throw XcodeGenSpecError.invalid(path: path, message: "expected a mapping with 'targets'")
                    }
                    for (buildKey, buildValue) in buildEntries {
                        guard buildKey == "targets" else {
                            ignored.append("\(path).\(buildKey)")
                            continue
                        }
                        scheme.buildTargets = try parseSchemeBuildTargets(buildValue, path: "\(path).targets")
                    }
                case "run":
                    scheme.runConfig = try parseSchemeConfig(sv, path: path, ignored: &ignored)
                case "test":
                    guard let testEntries = sv.map else {
                        throw XcodeGenSpecError.invalid(path: path, message: "expected a mapping with 'config' and/or 'targets'")
                    }
                    for (testKey, testValue) in testEntries {
                        switch testKey {
                        case "config": scheme.testConfig = testValue.scalar
                        case "targets":
                            guard let list = testValue.list else {
                                throw XcodeGenSpecError.invalid(path: "\(path).targets", message: "expected a list of target names")
                            }
                            scheme.testTargets = list.compactMap(\.scalar)
                        case "gatherCoverageData":
                            if case .bool(let b) = testValue { scheme.gatherCoverageData = b }
                        default:
                            ignored.append("\(path).\(testKey)")
                        }
                    }
                case "profile":
                    scheme.profileConfig = try parseSchemeConfig(sv, path: path, ignored: &ignored)
                case "analyze":
                    scheme.analyzeConfig = try parseSchemeConfig(sv, path: path, ignored: &ignored)
                case "archive":
                    scheme.archiveConfig = try parseSchemeConfig(sv, path: path, ignored: &ignored)
                default:
                    ignored.append(path)
                }
            }
            schemes.append(scheme)
        }
        return schemes
    }

    private static func parseSchemeConfig(_ value: XcodeGenYAMLValue, path: String, ignored: inout [String]) throws -> String? {
        if let name = value.scalar { return name }
        guard let entries = value.map else {
            throw XcodeGenSpecError.invalid(path: path, message: "expected a configuration name or a mapping with 'config'")
        }
        var config: String?
        for (key, v) in entries {
            if key == "config" {
                config = v.scalar
            } else {
                ignored.append("\(path).\(key)")
                _ = v
            }
        }
        return config
    }

    private static func parseSchemeBuildTargets(_ value: XcodeGenYAMLValue, path: String) throws -> [(name: String, flags: Set<String>)] {
        if let list = value.list {
            return try list.map { item in
                guard let name = item.scalar else {
                    throw XcodeGenSpecError.invalid(path: path, message: "expected a target name")
                }
                return (name, ["all"])
            }
        }
        guard let entries = value.map else {
            throw XcodeGenSpecError.invalid(path: path, message: "expected a list or a mapping of target name to build-for flags")
        }
        var out: [(name: String, flags: Set<String>)] = []
        for (name, flags) in entries {
            guard let flagList = flags.list else {
                throw XcodeGenSpecError.invalid(path: "\(path).\(name)", message: "expected a list of build-for flags")
            }
            out.append((name, Set(flagList.compactMap(\.scalar))))
        }
        return out
    }
}

public struct XcodeGenGeneratedProject: Sendable {
    public var projectName: String
    public var files: [(relativePath: String, content: String)]
    public var ignoredKeys: [String]
    public var warnings: [String]
    public var targetNames: [String]
    public var schemeNames: [String]
}

public enum XcodeGenNativeGenerator {
    public static func generate(specText: String, specDirectory: URL) throws -> XcodeGenGeneratedProject {
        let spec = try XcodeGenSpec.parse(specText)
        let builder = try XcodeGenProjectBuilder(spec: spec, specDirectory: specDirectory)
        return try builder.build()
    }
}

private final class XcodeGenProjectBuilder {
    let spec: XcodeGenSpec
    let specDirectory: URL
    var project: PBXProj
    var warnings: [String] = []

    private var refCache: [String: String] = [:]
    private var variantGroups: [String: String] = [:]
    private var projectID = ""
    private var targetIDs: [String: String] = [:]
    private var productIDs: [String: String] = [:]
    private var packageReferenceIDsByName: [String: String] = [:]
    private var targetPhases: [String: [String: String]] = [:]
    private var embedPhases: [String: String] = [:]
    private var hasSwiftSources = false

    init(spec: XcodeGenSpec, specDirectory: URL) throws {
        self.spec = spec
        self.specDirectory = specDirectory
        self.project = try PBXProj(parsing: "// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 77; objects = {}; rootObject = 000000000000000000000000; }\n")
    }

    private func obj(_ attrs: [(String, PlistValue)]) -> String {
        let id = project.makeObjectID()
        project[id] = PBXObject(id: id, attributes: PlistDictionary(attrs))
        return id
    }

    private func strings(_ ids: [String]) -> PlistValue { .array(ids.map(PlistValue.string)) }

    private func config(_ name: String, _ settings: [(String, PlistValue)], baseConfigurationReference: String? = nil) -> String {
        var attrs: [(String, PlistValue)] = [
            ("isa", "XCBuildConfiguration"),
            ("buildSettings", .dictionary(PlistDictionary(settings))),
            ("name", .string(name)),
        ]
        if let baseConfigurationReference {
            attrs.append(("baseConfigurationReference", .string(baseConfigurationReference)))
        }
        return obj(attrs)
    }

    private func list(_ ids: [String]) -> String {
        obj([("isa", "XCConfigurationList"), ("buildConfigurations", strings(ids)),
             ("defaultConfigurationIsVisible", "0"), ("defaultConfigurationName", "Release")])
    }

    private func ref(_ path: String, _ type: String, sourceTree: String = "<group>", name: String? = nil) -> String {
        var attrs: [(String, PlistValue)] = [
            ("isa", "PBXFileReference"), ("lastKnownFileType", .string(type)),
            ("path", .string(path)), ("sourceTree", .string(sourceTree)),
        ]
        if let name { attrs.append(("name", .string(name))) }
        return obj(attrs)
    }

    private func buildFile(_ fileRef: String) -> String {
        obj([("isa", "PBXBuildFile"), ("fileRef", .string(fileRef))])
    }

    private func buildFile(productRef: String) -> String {
        obj([("isa", "PBXBuildFile"), ("productRef", .string(productRef))])
    }

    private func phase(_ isa: String, _ files: [String]) -> String {
        obj([("isa", .string(isa)), ("buildActionMask", "2147483647"), ("files", strings(files)),
             ("runOnlyForDeploymentPostprocessing", "0")])
    }

    private func scriptPhase(_ script: XcodeGenScript) -> String {
        var attrs: [(String, PlistValue)] = [
            ("isa", "PBXShellScriptBuildPhase"), ("buildActionMask", "2147483647"),
            ("files", strings([])), ("inputPaths", strings(script.inputFiles)),
            ("outputPaths", strings(script.outputFiles)),
            ("runOnlyForDeploymentPostprocessing", "0"),
            ("shellPath", .string(script.shell ?? "/bin/sh")),
            ("shellScript", .string(script.script)),
        ]
        if let name = script.name { attrs.append(("name", .string(name))) }
        return obj(attrs)
    }

    private func product(_ path: String, _ type: String) -> String {
        obj([("isa", "PBXFileReference"), ("explicitFileType", .string(type)), ("includeInIndex", "0"),
             ("path", .string(path)), ("sourceTree", "BUILT_PRODUCTS_DIR")])
    }

    private func group(_ path: String?, _ children: [String], name: String? = nil, sourceTree: String = "<group>") -> String {
        var attrs: [(String, PlistValue)] = [("isa", "PBXGroup"), ("children", strings(children))]
        if let name { attrs.append(("name", .string(name))) }
        if let path { attrs.append(("path", .string(path))) }
        attrs.append(("sourceTree", .string(sourceTree)))
        return obj(attrs)
    }

    func build() throws -> XcodeGenGeneratedProject {
        try validateFilesExist()
        let projectID = project.makeObjectID()
        self.projectID = projectID
        var targetIDsInOrder: [String] = []
        var productIDsInOrder: [String] = []
        var targetGroups: [String] = []
        var packageReferenceIDs: [String] = []

        for package in spec.packages {
            let refID = obj([
                ("isa", "XCRemoteSwiftPackageReference"),
                ("repositoryURL", .string(package.url)),
                ("requirement", package.requirement.plist),
            ])
            packageReferenceIDs.append(refID)
            packageReferenceIDsByName[package.name] = refID
        }

        for target in spec.targets {
            let built = try buildTarget(target, projectID: projectID)
            targetIDs[target.name] = built.targetID
            productIDs[target.name] = built.productID
            targetIDsInOrder.append(built.targetID)
            productIDsInOrder.append(built.productID)
            targetGroups.append(built.groupID)
        }

        for target in spec.targets {
            try linkDependencies(of: target)
        }

        let productsGroup = group(nil, productIDsInOrder, name: "Products")
        let topLevelConfigRefs = spec.configFiles.values.map { fileReference(for: $0) }
        let mainGroup = group(nil, targetGroups + topLevelConfigRefs + [productsGroup])
        let projectList = list(spec.configNames.map { configName in
            config(configName, projectSettings(for: configName), baseConfigurationReference: configFileReference(for: configName, topLevel: true))
        })
        project[projectID] = PBXObject(id: projectID, attributes: PlistDictionary([
            ("isa", "PBXProject"),
            ("buildConfigurationList", .string(projectList)),
            ("developmentRegion", "en"),
            ("hasScannedForEncodings", "0"),
            ("knownRegions", .array(knownRegions.map(PlistValue.string))),
            ("mainGroup", .string(mainGroup)),
            ("packageReferences", strings(packageReferenceIDs)),
            ("productRefGroup", .string(productsGroup)),
            ("projectDirPath", ""),
            ("projectRoot", ""),
            ("targets", strings(targetIDsInOrder)),
        ]))
        project.rootObject = projectID

        var files: [(relativePath: String, content: String)] = []
        let bundle = "\(spec.name).xcodeproj"
        files.append((relativePath: "\(bundle)/project.pbxproj", content: project.serialized(projectName: spec.name)))
        files.append((relativePath: "\(bundle)/project.xcworkspace/contents.xcworkspacedata", content: SwiftCodeMCPHost.projectModelSelfWorkspace))
        let schemes = schemesToGenerate()
        for scheme in schemes {
            let xml = try schemeXML(scheme)
            files.append((relativePath: "\(bundle)/xcshareddata/xcschemes/\(scheme.name).xcscheme", content: xml))
        }
        for (path, content) in generatedInfoPlists.sorted(by: { $0.0 < $1.0 }) {
            files.insert((relativePath: path, content: content), at: 0)
        }
        return XcodeGenGeneratedProject(
            projectName: spec.name, files: files,
            ignoredKeys: spec.ignoredKeys, warnings: warnings,
            targetNames: spec.targets.map(\.name), schemeNames: schemes.map(\.name))
    }

    private var generatedInfoPlists: [String: String] = [:]

    private var knownRegions: [String] {
        var regions = ["en", "Base"]
        if let language = spec.options.developmentLanguage, !regions.contains(language) {
            regions.append(language)
        }
        return regions
    }

    private func projectSettings(for configName: String) -> [(String, PlistValue)] {
        var settings: [(String, PlistValue)] = []
        if hasSwiftSources { settings.append(("SWIFT_VERSION", "6.0")) }
        settings.append(("ALWAYS_SEARCH_USER_PATHS", "NO"))
        for (key, value) in spec.settings.merged(for: configName) {
            settings.append((key, .string(value)))
        }
        return settings
    }

    private func configFileReference(for configName: String, topLevel: Bool, target: XcodeGenTarget? = nil) -> String? {
        let path: String?
        if topLevel {
            path = spec.configFiles[configName]
        } else {
            path = target?.configFiles[configName]
        }
        guard let path else { return nil }
        return fileReference(for: path)
    }

    private func validateFilesExist() throws {
        let fm = FileManager.default
        func check(_ path: String, at keyPath: String) throws {
            let url = url(for: path)
            guard fm.fileExists(atPath: url.path) else {
                throw XcodeGenSpecError.invalid(path: keyPath, message: "file not found: '\(path)' (resolved to \(url.path))")
            }
        }
        for target in spec.targets {
            if target.type.isApplication, spec.options.bundleIdPrefix == nil {
                throw XcodeGenSpecError.invalid(
                    path: "options.bundleIdPrefix",
                    message: "application target '\(target.name)' needs a bundle ID prefix (options.bundleIdPrefix). Run xcodegen or add the prefix.")
            }
            for source in target.sources {
                try check(source.path, at: "targets.\(target.name).sources")
            }
            if let infoPath = target.infoPath {
                try check(infoPath, at: "targets.\(target.name).info")
            }
            if let entitlements = target.entitlementsPath {
                try check(entitlements, at: "targets.\(target.name).entitlements")
            }
            for (config, file) in target.configFiles {
                try check(file, at: "targets.\(target.name).configFiles.\(config)")
            }
        }
        for (config, file) in spec.configFiles {
            try check(file, at: "configFiles.\(config)")
        }
    }

    private func url(for path: String) -> URL {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return specDirectory.appendingPathComponent(path)
    }

    private func relativePath(for path: String) -> String {
        if path.hasPrefix("/") { return path }
        return path
    }

    private struct BuiltTarget {
        var targetID: String
        var productID: String
        var groupID: String
    }

    private func buildTarget(_ target: XcodeGenTarget, projectID: String) throws -> BuiltTarget {
        let productName = target.name
        let ext = target.type.productExtension
        let productPath = ext.isEmpty ? productName : "\(productName).\(ext)"
        let productID = product(productPath, target.type.productFileType)

        var sourceBuildFiles: [String] = []
        var headerBuildFiles: [String] = []
        var resourceBuildFiles: [String] = []
        var groupChildren: [String] = []
        var hasSwift = false
        for source in target.sources {
            let expanded = try expandSource(source, target: target)
            for file in expanded.files {
                if file.isFolderReference {
                    groupChildren.append(file.refID)
                    continue
                }
                if file.isVariantGroup {
                    groupChildren.append(file.refID)
                    resourceBuildFiles.append(buildFile(file.refID))
                    continue
                }
                if Self.sourceExtensions.contains(file.extension) {
                    sourceBuildFiles.append(buildFile(file.refID))
                    if file.extension == "swift" { hasSwift = true }
                } else if Self.headerExtensions.contains(file.extension) {
                    headerBuildFiles.append(buildFile(file.refID))
                } else {
                    resourceBuildFiles.append(buildFile(file.refID))
                }
            }
            if let subgroup = expanded.groupID {
                groupChildren.append(subgroup)
            }
        }
        if hasSwift { hasSwiftSources = true }

        var infoPlistFile: String?
        if let infoPath = target.infoPath {
            infoPlistFile = infoPath
            let refID = fileReference(for: infoPath)
            groupChildren.append(refID)
        } else if let properties = target.infoProperties {
            let plistPath = "\(target.name)/Info.plist"
            generatedInfoPlists[plistPath] = infoPlistXML(properties)
            infoPlistFile = plistPath
            groupChildren.append(fileReference(for: plistPath))
        }
        if let entitlements = target.entitlementsPath {
            groupChildren.append(fileReference(for: entitlements))
        }
        for (_, configPath) in target.configFiles {
            groupChildren.append(fileReference(for: configPath))
        }

        let targetGroup = group(nil, groupChildren, name: target.name)

        var phaseIDs: [String] = []
        for script in target.preBuildScripts { phaseIDs.append(scriptPhase(script)) }
        phaseIDs.append(phase("PBXSourcesBuildPhase", sourceBuildFiles))
        if !headerBuildFiles.isEmpty { phaseIDs.append(phase("PBXHeadersBuildPhase", headerBuildFiles)) }
        let frameworksPhase = phase("PBXFrameworksBuildPhase", [])
        phaseIDs.append(frameworksPhase)
        phaseIDs.append(phase("PBXResourcesBuildPhase", resourceBuildFiles))
        phaseIDs.append(contentsOf: target.postBuildScripts.map(scriptPhase))
        targetPhases[target.name] = ["PBXFrameworksBuildPhase": frameworksPhase]

        let targetList = list(spec.configNames.map { configName in
            config(configName, targetSettings(target, for: configName, infoPlistFile: infoPlistFile, hasSwift: hasSwift),
                   baseConfigurationReference: configFileReference(for: configName, topLevel: false, target: target))
        })
        let targetID = obj([
            ("isa", "PBXNativeTarget"),
            ("buildConfigurationList", .string(targetList)),
            ("buildPhases", strings(phaseIDs)),
            ("buildRules", strings([])),
            ("dependencies", strings([])),
            ("name", .string(target.name)),
            ("productName", .string(productName)),
            ("productReference", .string(productID)),
            ("productType", .string(target.type.productType)),
        ])
        return BuiltTarget(targetID: targetID, productID: productID, groupID: targetGroup)
    }

    private func targetSettings(_ target: XcodeGenTarget, for configName: String, infoPlistFile: String?, hasSwift: Bool) -> [(String, PlistValue)] {
        var settings: [(String, PlistValue)] = []
        let deploymentTarget = target.deploymentTarget
            ?? spec.options.deploymentTarget[target.platform.platformName]
            ?? spec.options.deploymentTarget["*"]
            ?? target.platform.defaultDeploymentTarget
        settings += [
            ("PRODUCT_NAME", "$(TARGET_NAME)"),
            ("SDKROOT", .string(target.platform.sdkRoot)),
            (target.platform.deploymentTargetKey, .string(deploymentTarget)),
        ]
        settings += target.platform.deviceSettings.map { ($0.0, PlistValue.string($0.1)) }
        if target.type.isApplication {
            let prefix = spec.options.bundleIdPrefix ?? ""
            let bundleID = prefix + "." + target.name.filter { $0.isLetter || $0.isNumber }
            settings.append(("PRODUCT_BUNDLE_IDENTIFIER", .string(bundleID)))
        }
        if let infoPlistFile {
            settings.append(("GENERATE_INFOPLIST_FILE", "NO"))
            settings.append(("INFOPLIST_FILE", .string(infoPlistFile)))
        } else {
            settings.append(("GENERATE_INFOPLIST_FILE", "YES"))
        }
        if let entitlements = target.entitlementsPath {
            settings.append(("CODE_SIGN_ENTITLEMENTS", .string(entitlements)))
        }
        switch target.type {
        case .staticLibrary, .dynamicLibrary:
            break
        default:
            settings.append(("CODE_SIGN_STYLE", "Automatic"))
        }
        settings.append(("MARKETING_VERSION", "1.0"))
        settings.append(("CURRENT_PROJECT_VERSION", "1"))
        if hasSwift { settings.append(("SWIFT_VERSION", "6.0")) }
        for (key, value) in target.settings.merged(for: configName) {
            if let index = settings.firstIndex(where: { $0.0 == key }) {
                settings[index] = (key, .string(value))
            } else {
                settings.append((key, .string(value)))
            }
        }
        return settings
    }

    private struct ExpandedFile {
        var refID: String
        var `extension`: String
        var isFolderReference = false
        var isVariantGroup = false
    }

    private struct ExpandedSource {
        var files: [ExpandedFile]
        var groupID: String?
    }

    private static let sourceExtensions: Set<String> = ["swift", "m", "mm", "c", "cpp", "cc", "cxx", "s", "metal"]
    private static let headerExtensions: Set<String> = ["h", "hpp", "hh"]
    private static let resourceExtensions: Set<String> = [
        "xcassets", "png", "jpg", "jpeg", "gif", "pdf", "json", "xcstrings",
        "mp3", "wav", "caf", "aiff", "mov", "mp4", "ttf", "otf", "data", "txt", "md", "html", "xml",
    ]

    private func expandSource(_ source: XcodeGenSource, target: XcodeGenTarget) throws -> ExpandedSource {
        let sourceURL = url(for: source.path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            throw XcodeGenSpecError.invalid(path: "targets.\(target.name).sources", message: "source not found: '\(source.path)'")
        }
        if source.folderReference || !isDirectory.boolValue {
            let refID = fileReference(for: source.path, isFolder: source.folderReference, resolvedPath: sourceURL.standardizedFileURL.path)
            return ExpandedSource(files: [ExpandedFile(refID: refID, extension: (source.path as NSString).pathExtension.lowercased(), isFolderReference: source.folderReference)], groupID: nil)
        }
        let fm = FileManager.default
        var files: [URL] = []
        if let enumerator = fm.enumerator(at: sourceURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            while let url = enumerator.nextObject() as? URL {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir {
                    let name = url.lastPathComponent
                    if ["DerivedData", "build", ".build", "Pods", "node_modules"].contains(name) || name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") || name.hasSuffix(".playground") {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                files.append(url)
            }
        }
        files.sort { $0.path < $1.path }
        let basePath = sourceURL.standardizedFileURL.path
        var buckets: [String: [ExpandedFile]] = [:]
        var bucketOrder: [String] = []
        func bucket(_ dir: String, _ file: ExpandedFile) {
            if buckets[dir] == nil { bucketOrder.append(dir) }
            buckets[dir, default: []].append(file)
        }
        for url in files {
            let relative = String(url.path.dropFirst(basePath.count + 1))
            if isExcluded(relative: relative, fullRelative: relativePath(for: source.path) + "/" + relative, excludes: source.excludes) {
                continue
            }
            let ext = (url.path as NSString).pathExtension.lowercased()
            let parts = relative.split(separator: "/").map(String.init)
            if parts.count >= 2, parts[parts.count - 2].hasSuffix(".lproj"),
               ["storyboard", "xib", "strings", "stringsdict"].contains(ext) {
                let parentDir = parts.dropLast(2).joined(separator: "/")
                let groupDir = groupDir(for: parentDir)
                let baseName = parts.last!
                let key = "\(source.path)/\(groupDir)/\(baseName)"
                let refPath = "\(parts[parts.count - 2])/\(baseName)"
                let refID = fileReference(for: refPath, type: PBXProj.fileType(forPath: baseName), resolvedPath: url.standardizedFileURL.path)
                if let variantID = variantGroups[key] {
                    appendChild(variantID, child: refID)
                    continue
                }
                let variantID = obj([
                    ("isa", "PBXVariantGroup"), ("children", strings([refID])),
                    ("name", .string(baseName)), ("sourceTree", "<group>"),
                ])
                variantGroups[key] = variantID
                bucket(groupDir, ExpandedFile(refID: variantID, extension: ext, isVariantGroup: true))
                continue
            }
            let groupDir = groupDir(for: parts.dropLast().joined(separator: "/"))
            let refPath: String
            if spec.options.createIntermediateGroups {
                refPath = parts.last!
            } else if groupDir.isEmpty {
                refPath = relative
            } else {
                refPath = parts.dropFirst().joined(separator: "/")
            }
            let refID = fileReference(for: refPath, resolvedPath: url.standardizedFileURL.path)
            if !Self.sourceExtensions.contains(ext) && !Self.headerExtensions.contains(ext) && !Self.resourceExtensions.contains(ext) {
                warnings.append("targets source '\(relative)' has an unrecognised extension '.\(ext)'; placed in the resources phase")
            }
            bucket(groupDir, ExpandedFile(refID: refID, extension: ext))
        }
        var children: [String] = []
        var allFiles: [ExpandedFile] = []
        for dir in bucketOrder {
            let dirFiles = buckets[dir] ?? []
            allFiles += dirFiles
            if dir.isEmpty {
                children += dirFiles.map(\.refID)
            } else {
                children.append(buildDirectoryGroup(dir: dir, files: dirFiles))
            }
        }
        let isAbsolute = source.path.hasPrefix("/")
        let groupID = group(source.path, children,
                            name: source.group ?? (source.path as NSString).lastPathComponent,
                            sourceTree: isAbsolute ? "<absolute>" : "<group>")
        return ExpandedSource(files: allFiles, groupID: groupID)
    }

    private func groupDir(for dir: String) -> String {
        if dir.isEmpty { return "" }
        if spec.options.createIntermediateGroups { return dir }
        return String(dir.split(separator: "/").first!)
    }

    private func buildDirectoryGroup(dir: String, files: [ExpandedFile]) -> String {
        let parts = dir.split(separator: "/").map(String.init)
        if !spec.options.createIntermediateGroups || parts.count == 1 {
            return group(dir, files.map(\.refID), name: parts.last!)
        }
        var child = group(parts.last!, files.map(\.refID), name: parts.last!)
        for part in parts.dropLast().reversed() {
            child = group(part, [child], name: part)
        }
        return child
    }

    private func appendChild(_ groupID: String, child: String) {
        guard var groupObject = project[groupID] else { return }
        var children = groupObject.references("children")
        guard !children.contains(child) else { return }
        children.append(child)
        groupObject["children"] = .array(children.map(PlistValue.string))
        project[groupID] = groupObject
    }

    private func isExcluded(relative: String, fullRelative: String, excludes: [String]) -> Bool {
        for pattern in excludes {
            if globMatch(pattern: pattern, string: relative) || globMatch(pattern: pattern, string: fullRelative) {
                return true
            }
        }
        return false
    }

    private func globMatch(pattern: String, string: String) -> Bool {
        if pattern == string || string.hasSuffix("/" + pattern) { return true }
        var regex = "^"
        var index = pattern.startIndex
        while index < pattern.endIndex {
            let ch = pattern[index]
            if ch == "*" {
                let next = pattern.index(after: index)
                if next < pattern.endIndex, pattern[next] == "*" {
                    regex += ".*"
                    index = pattern.index(after: next)
                } else {
                    regex += "[^/]*"
                    index = next
                }
            } else if ch == "?" {
                regex += "."
                index = pattern.index(after: index)
            } else {
                regex += NSRegularExpression.escapedPattern(for: String(ch))
                index = pattern.index(after: index)
            }
        }
        regex += "$"
        return (try? NSRegularExpression(pattern: regex).firstMatch(in: string, range: NSRange(string.startIndex..., in: string))) != nil
    }

    private func fileReference(for path: String, isFolder: Bool = false, type: String? = nil, resolvedPath: String? = nil) -> String {
        let key = (resolvedPath ?? "") + "|" + path + (isFolder ? ":folder" : "")
        if let cached = refCache[key] { return cached }
        if let resolvedPath {
            if let first = resolvedPaths[resolvedPath], first != path {
                warnings.append("file '\(resolvedPath)' is referenced from two groups ('\(first)' and '\(path)'); it appears twice in the navigator")
            } else {
                resolvedPaths[resolvedPath] = path
            }
        }
        let fileType = type ?? (isFolder ? "folder" : PBXProj.fileType(forPath: path))
        let id = ref(path, fileType)
        refCache[key] = id
        return id
    }

    private var resolvedPaths: [String: String] = [:]

    private func linkDependencies(of target: XcodeGenTarget) throws {
        guard let targetID = targetIDs[target.name],
              let frameworksPhase = targetPhases[target.name]?["PBXFrameworksBuildPhase"] else { return }
        var linkedProducts: [String] = []
        func linkProduct(_ productID: String, embed: Bool) {
            let buildFileID = buildFile(productID)
            appendToPhase(frameworksPhase, buildFileID)
            linkedProducts.append(productID)
            if embed {
                embedProduct(targetID: targetID, productID: productID)
            }
        }
        var directTargetDeps: [String] = []
        for dep in target.dependencies {
            switch dep {
            case .target(let name, let embed, let link):
                guard let depTargetID = targetIDs[name], let depProductID = productIDs[name] else { continue }
                directTargetDeps.append(name)
                let proxy = obj([
                    ("isa", "PBXContainerItemProxy"), ("containerPortal", .string(projectID)),
                    ("proxyType", "1"), ("remoteGlobalIDString", .string(depTargetID)), ("remoteInfo", .string(name)),
                ])
                let dependency = obj([
                    ("isa", "PBXTargetDependency"), ("target", .string(depTargetID)), ("targetProxy", .string(proxy)),
                ])
                appendReference(dependency, key: "dependencies", to: targetID)
                if link {
                    linkProduct(depProductID, embed: embed)
                }
            case .package(let name, let product):
                guard spec.packages.contains(where: { $0.name == name }),
                      let packageRefID = packageReferenceIDsByName[name] else { continue }
                let productName = product ?? name
                let productDep = obj([
                    ("isa", "XCSwiftPackageProductDependency"),
                    ("package", .string(packageRefID)),
                    ("productName", .string(productName)),
                ])
                appendReference(productDep, key: "packageProductDependencies", to: targetID)
                appendToPhase(frameworksPhase, buildFile(productRef: productDep))
            case .framework(let path):
                let refID = try frameworkReference(for: path, target: target)
                appendToPhase(frameworksPhase, buildFile(refID))
            case .sdk(let name):
                let refID = sdkReference(for: name)
                appendToPhase(frameworksPhase, buildFile(refID))
            }
        }
        if target.transitivelyLinkDependencies {
            var visited = Set(directTargetDeps)
            var queue = directTargetDeps
            while let name = queue.first {
                queue.removeFirst()
                guard let depTarget = spec.targets.first(where: { $0.name == name }) else { continue }
                for dep in depTarget.dependencies {
                    if case .target(let transitiveName, _, _) = dep, !visited.contains(transitiveName) {
                        visited.insert(transitiveName)
                        queue.append(transitiveName)
                        if let transitiveProduct = productIDs[transitiveName], !linkedProducts.contains(transitiveProduct) {
                            linkProduct(transitiveProduct, embed: false)
                        }
                    }
                }
            }
        }
    }

    private func embedProduct(targetID: String, productID: String) {
        if embedPhases[targetID] == nil {
            let phaseID = obj([
                ("isa", "PBXCopyFilesBuildPhase"), ("buildActionMask", "2147483647"),
                ("dstPath", ""), ("dstSubfolderSpec", "10"),
                ("files", strings([])), ("name", "Embed Frameworks"),
                ("runOnlyForDeploymentPostprocessing", "0"),
            ])
            embedPhases[targetID] = phaseID
            guard var targetObject = project[targetID] else { return }
            var phases = targetObject.references("buildPhases")
            if let frameworksIndex = phases.firstIndex(where: { project[$0]?.isa == "PBXFrameworksBuildPhase" }) {
                phases.insert(phaseID, at: frameworksIndex + 1)
            } else {
                phases.append(phaseID)
            }
            targetObject["buildPhases"] = .array(phases.map(PlistValue.string))
            project[targetID] = targetObject
        }
        let phaseID = embedPhases[targetID]!
        let buildFileID = obj([
            ("isa", "PBXBuildFile"), ("fileRef", .string(productID)),
            ("settings", .dictionary(PlistDictionary([
                ("ATTRIBUTES", .array([.string("CodeSignOnCopy"), .string("RemoveHeadersOnCopy")])),
            ]))),
        ])
        appendToPhase(phaseID, buildFileID)
    }

    private func frameworkReference(for path: String, target: XcodeGenTarget) throws -> String {
        if path.hasPrefix("/") {
            return ref(path, PBXProj.fileType(forPath: path), sourceTree: "<absolute>")
        }
        let url = url(for: path)
        if FileManager.default.fileExists(atPath: url.path) {
            return fileReference(for: path)
        }
        if !(path as NSString).pathExtension.isEmpty, !path.contains("/") {
            return ref(path, PBXProj.fileType(forPath: path), sourceTree: "SDKROOT")
        }
        throw XcodeGenSpecError.invalid(path: "targets.\(target.name).dependencies", message: "framework not found: '\(path)'")
    }

    private func sdkReference(for name: String) -> String {
        ref(name, PBXProj.fileType(forPath: name), sourceTree: "SDKROOT")
    }

    private func appendToPhase(_ phaseID: String, _ buildFileID: String) {
        guard var phaseObject = project[phaseID] else { return }
        var files = phaseObject.references("files")
        files.append(buildFileID)
        phaseObject["files"] = .array(files.map(PlistValue.string))
        project[phaseID] = phaseObject
    }

    private func appendReference(_ refID: String, key: String, to ownerID: String) {
        guard var owner = project[ownerID] else { return }
        var refs = owner.references(key)
        refs.append(refID)
        owner[key] = .array(refs.map(PlistValue.string))
        project[ownerID] = owner
    }

    private func schemesToGenerate() -> [XcodeGenScheme] {
        if !spec.schemes.isEmpty { return spec.schemes }
        return spec.targets.map { target in
            var scheme = XcodeGenScheme(name: target.name)
            scheme.buildTargets = [(target.name, ["all"])]
            scheme.runConfig = "Debug"
            scheme.testConfig = "Debug"
            scheme.profileConfig = "Release"
            scheme.analyzeConfig = "Debug"
            scheme.archiveConfig = "Release"
            if let targetScheme = target.scheme {
                scheme.testTargets = targetScheme.testTargets
                scheme.gatherCoverageData = targetScheme.gatherCoverageData
                if let config = targetScheme.config { scheme.runConfig = config }
            } else {
                scheme.testTargets = spec.targets
                    .filter { $0.type.isTestBundle && $0.dependencies.contains { dep in
                        if case .target(let name, _, _) = dep { return name == target.name }
                        return false
                    } }
                    .map(\.name)
            }
            return scheme
        }
    }

    private func schemeXML(_ scheme: XcodeGenScheme) throws -> String {
        let lastUpgradeVersion = lastUpgradeVersion()
        func buildable(for targetName: String) throws -> (id: String, name: String, product: String) {
            guard let id = targetIDs[targetName], let productID = productIDs[targetName],
                  let target = spec.targets.first(where: { $0.name == targetName }),
                  let productObject = project[productID] else {
                throw XcodeGenSpecError.invalid(path: "schemes.\(scheme.name)", message: "no target named '\(targetName)'")
            }
            let productName = productObject.string("path") ?? target.name
            return (id, target.name, productName)
        }
        func reference(_ b: (id: String, name: String, product: String)) -> String {
            """
               <BuildableReference
                  BuildableIdentifier = "primary"
                  BlueprintIdentifier = "\(xmlEscape(b.id))"
                  BuildableName = "\(xmlEscape(b.product))"
                  BlueprintName = "\(xmlEscape(b.name))"
                  ReferencedContainer = "container:\(xmlEscape(spec.name)).xcodeproj">
               </BuildableReference>
            """
        }
        func buildEntry(_ b: (id: String, name: String, product: String), flags: Set<String>) -> String {
            let all = flags.contains("all")
            func flag(_ name: String) -> String {
                (all || flags.contains(name)) ? "YES" : "NO"
            }
            let isTest = spec.targets.first(where: { $0.name == b.name })?.type.isTestBundle ?? false
            let running = isTest ? "NO" : flag("running")
            let profiling = isTest ? "NO" : flag("profiling")
            let archiving = isTest ? "NO" : flag("archiving")
            return """
                  <BuildActionEntry
                     buildForTesting = "\(flag("testing"))"
                     buildForRunning = "\(running)"
                     buildForProfiling = "\(profiling)"
                     buildForArchiving = "\(archiving)"
                     buildForAnalyzing = "\(flag("analyzing"))">
            \(reference(b))
                  </BuildActionEntry>
            """
        }
        var buildEntries: [String] = []
        for (targetName, flags) in scheme.buildTargets {
            buildEntries.append(try buildEntry(buildable(for: targetName), flags: flags))
        }
        let buildAction = """
           <BuildAction
              parallelizeBuildables = "YES"
              buildImplicitDependencies = "YES">
              <BuildActionEntries>
        \(buildEntries.joined(separator: "\n"))
              </BuildActionEntries>
           </BuildAction>
        """
        var testables: [String] = []
        for testTarget in scheme.testTargets {
            let b = try buildable(for: testTarget)
            testables.append("""
                  <TestableReference
                     skipped = "NO">
            \(reference(b))
                  </TestableReference>
            """)
        }
        let testAction = """
           <TestAction
              buildConfiguration = "\(xmlEscape(scheme.testConfig ?? "Debug"))"
              selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
              selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
              shouldUseLaunchSchemeArgsEnv = "YES"
              codeCoverageEnabled = "\(scheme.gatherCoverageData ? "YES" : "NO")">
              <Testables>
        \(testables.joined(separator: "\n"))
              </Testables>
           </TestAction>
        """
        let runnableName = scheme.buildTargets
            .map(\.name)
            .first { name in spec.targets.first(where: { $0.name == name })?.type.isApplication ?? false }
        let runnableXML: String
        let macroExpansion: String
        if let runnableName, let b = try? buildable(for: runnableName) {
            runnableXML = """
              <BuildableProductRunnable
                 runnableDebuggingMode = "0">
        \(reference(b))
              </BuildableProductRunnable>
        """
            macroExpansion = """
              <MacroExpansion>
        \(reference(b))
              </MacroExpansion>
        """
        } else if let first = scheme.buildTargets.first, let b = try? buildable(for: first.name) {
            runnableXML = ""
            macroExpansion = """
              <MacroExpansion>
        \(reference(b))
              </MacroExpansion>
        """
        } else {
            runnableXML = ""
            macroExpansion = ""
        }
        let launchAction = """
           <LaunchAction
              buildConfiguration = "\(xmlEscape(scheme.runConfig ?? "Debug"))"
              selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
              selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
              launchStyle = "0"
              useCustomWorkingDirectory = "NO"
              ignoresPersistentStateOnLaunch = "NO"
              debugDocumentVersioning = "YES"
              debugServiceExtension = "internal"
              allowLocationSimulation = "YES">
        \(runnableXML)\(macroExpansion)   </LaunchAction>
        """
        let profileAction = """
           <ProfileAction
              buildConfiguration = "\(xmlEscape(scheme.profileConfig ?? "Release"))"
              shouldUseLaunchSchemeArgsEnv = "YES"
              savedToolIdentifier = ""
              useCustomWorkingDirectory = "NO"
              debugDocumentVersioning = "YES">
        \(macroExpansion)   </ProfileAction>
        """
        let analyzeAction = """
           <AnalyzeAction
              buildConfiguration = "\(xmlEscape(scheme.analyzeConfig ?? "Debug"))">
           </AnalyzeAction>
        """
        let archiveAction = """
           <ArchiveAction
              buildConfiguration = "\(xmlEscape(scheme.archiveConfig ?? "Release"))"
              revealArchiveInOrganizer = "YES">
           </ArchiveAction>
        """
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme
           LastUpgradeVersion = "\(lastUpgradeVersion)"
           version = "1.7">
        \(buildAction)
        \(testAction)
        \(launchAction)
        \(profileAction)
        \(analyzeAction)
        \(archiveAction)
        </Scheme>

        """
    }

    private func lastUpgradeVersion() -> String {
        guard let version = spec.options.xcodeVersion else { return "1600" }
        let digits = version.filter { $0.isNumber }
        if digits.count >= 4 { return String(digits.prefix(4)) }
        return (digits + "00").prefix(4).description
    }

    private func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func infoPlistXML(_ properties: [(String, XcodeGenYAMLValue)]) -> String {
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>

        """
        for (key, value) in properties {
            out += "\t<key>\(xmlEscape(key))</key>\n"
            out += plistXML(value, indent: 1)
        }
        out += "</dict>\n</plist>\n"
        return out
    }

    private func plistXML(_ value: XcodeGenYAMLValue, indent: Int) -> String {
        let pad = String(repeating: "\t", count: indent)
        switch value {
        case .string(let s):
            return "\(pad)<string>\(xmlEscape(s))</string>\n"
        case .bool(let b):
            return "\(pad)<\(b ? "true" : "false")/>\n"
        case .list(let items):
            var out = "\(pad)<array>\n"
            for item in items { out += plistXML(item, indent: indent + 1) }
            out += "\(pad)</array>\n"
            return out
        case .map(let entries):
            var out = "\(pad)<dict>\n"
            for (key, v) in entries {
                out += "\(pad)\t<key>\(xmlEscape(key))</key>\n"
                out += plistXML(v, indent: indent + 1)
            }
            out += "\(pad)</dict>\n"
            return out
        }
    }
}

private extension XcodeGenPlatform {
    var platformName: String {
        switch self {
        case .iOS: "iOS"
        case .macOS: "macOS"
        case .watchOS: "watchOS"
        case .tvOS: "tvOS"
        case .visionOS: "visionOS"
        }
    }
}
