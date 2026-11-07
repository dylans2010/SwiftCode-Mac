import Foundation

public enum StringCatalogConverter {
    public struct LanguageTable: Sendable {
        public var language: String
        public var strings: [StringsFile.Entry]
        public var stringsdict: [(String, StringsDictValue)]
        public init(language: String, strings: [StringsFile.Entry] = [], stringsdict: [(String, StringsDictValue)] = []) {
            self.language = language
            self.strings = strings
            self.stringsdict = stringsdict
        }

        public static func read(language: String, strings: String?, stringsdict: String?) throws -> LanguageTable {
            var t = LanguageTable(language: language)
            if let p = strings { t.strings = try StringsFile.parse(Data(contentsOf: URL(fileURLWithPath: p))) }
            if let p = stringsdict { t.stringsdict = try StringsDictFile.parse(Data(contentsOf: URL(fileURLWithPath: p))) }
            return t
        }
    }

    public struct Warning: Equatable, Sendable, CustomStringConvertible {
        public var language: String
        public var key: String
        public var message: String
        public var description: String { "warning: \(message) (\(language): \(key))" }
    }

    public static func catalog(sourceLanguage: String, tables: [LanguageTable]) -> (StringCatalog, [Warning]) {
        var catalog = StringCatalog(sourceLanguage: sourceLanguage)
        var warnings: [Warning] = []
        var strings = OrderedJSON.object([])
        let ordered = tables.sorted { ($0.language == sourceLanguage ? 0 : 1, $0.language) < ($1.language == sourceLanguage ? 0 : 1, $1.language) }
        for t in ordered {
            let dictKeys = Set(t.stringsdict.map(\.0))
            for e in t.strings where !dictKeys.contains(e.key) {
                var entry = strings[e.key] ?? .object([("extractionState", .string("migrated"))])
                if entry["comment"] == nil, let c = e.comment, !c.isEmpty, !isPlaceholderComment(c) { entry["comment"] = .string(c) }
                var locs = entry["localizations"] ?? .object([])
                locs[t.language] = .object([("stringUnit", unit(e.value))])
                entry["localizations"] = locs
                strings[e.key] = entry
            }
            for (key, value) in t.stringsdict {
                guard let loc = localization(value, warn: { warnings.append(Warning(language: t.language, key: key, message: $0)) }) else { continue }
                var entry = strings[key] ?? .object([("extractionState", .string("migrated"))])
                var locs = entry["localizations"] ?? .object([])
                locs[t.language] = loc
                entry["localizations"] = locs
                strings[key] = entry
            }
        }
        catalog.json["strings"] = strings
        return (catalog, warnings)
    }

    static func isPlaceholderComment(_ c: String) -> Bool { c == "No comment provided by engineer." }

    static func unit(_ value: String) -> OrderedJSON {
        .object([("state", .string("translated")), ("value", .string(value))])
    }

    static func localization(_ value: StringsDictValue, warn: (String) -> Void) -> OrderedJSON? {
        if let s = value.string { return .object([("stringUnit", unit(s))]) }
        if let device = value["NSStringDeviceSpecificRuleType"] {
            var cases = OrderedJSON.object([])
            for (name, v) in device.pairs {
                if let loc = localization(v, warn: warn) { cases[name] = loc }
            }
            return .object([("variations", .object([("device", cases)]))])
        }
        guard let format = value["NSStringLocalizedFormatKey"]?.string else {
            warn("No NSStringLocalizedFormatKey")
            return nil
        }
        let specs = FormatSpecifier.parse(format)
        let variables = specs.filter { $0.variable != nil }
        if variables.count == 1, specs.count == 1, specs[0].text == format, let name = variables[0].variable,
           let rule = value[name], rule["NSStringFormatSpecTypeKey"]?.string == "NSStringPluralRuleType" {
            return .object([("variations", .object([("plural", pluralCases(rule, argText: nil))]))])
        }
        var subs = OrderedJSON.object([])
        var sequential = 0
        for spec in specs where spec.takesArgument {
            sequential += 1
            guard let name = spec.variable else { continue }
            guard let rule = value[name] else {
                warn("The variable '\(name)' has no rule")
                continue
            }
            guard rule["NSStringFormatSpecTypeKey"]?.string == "NSStringPluralRuleType" else {
                warn("The variable '\(name)' is not a plural rule")
                continue
            }
            let type = rule["NSStringFormatValueTypeKey"]?.string ?? "lld"
            let arg = spec.position ?? sequential
            subs[name] = .object([("argNum", .number(String(arg))), ("formatSpecifier", .string(type)),
                                  ("variations", .object([("plural", pluralCases(rule, argText: (type, arg)))]))])
        }
        var loc = OrderedJSON.object([("stringUnit", unit(format))])
        if !subs.objectPairs.isEmpty { loc["substitutions"] = subs }
        return loc
    }

    static func pluralCases(_ rule: StringsDictValue, argText: (type: String, arg: Int)?) -> OrderedJSON {
        var cases = OrderedJSON.object([])
        for (category, v) in rule.pairs where StringCatalogCompiler.pluralCategories.contains(category) {
            guard var s = v.string else { continue }
            if let a = argText {
                let edits = FormatSpecifier.parse(s).filter { $0.variable == nil && $0.valueType == a.type && ($0.position == nil || $0.position == a.arg) }
                    .map { ($0.offset, $0.text.utf16.count, "%arg") }
                s = s.replacingUTF16(edits)
            }
            cases[category] = .object([("stringUnit", unit(s))])
        }
        return cases
    }
}
