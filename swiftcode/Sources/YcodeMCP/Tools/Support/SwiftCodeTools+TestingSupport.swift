import Foundation
import YcodeIDECore

extension SwiftCodeMCPHost {

    nonisolated static func testingIsValidTestId(_ value: String) -> Bool {
        if value.contains(" ") || value.contains("\n") || value.contains("\r") { return false }
        if value.components(separatedBy: "/").count < 2 { return false }
        let forbidden = CharacterSet(charactersIn: ";|&$`\"'<>\\!(){}[]*?~#")
        if value.rangeOfCharacter(from: forbidden) != nil { return false }
        if value.contains("..") { return false }
        return true
    }

    nonisolated static func testingHasUnsafeShellCharacters(_ value: String) -> Bool {
        let forbidden = CharacterSet(charactersIn: ";|&$`\"'<>\\!()\n\r")
        return value.rangeOfCharacter(from: forbidden) != nil
    }

    nonisolated static func testingIsValidSwiftIdentifier(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first else { return false }
        guard CharacterSet.letters.contains(first) || first == "_" else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    struct TestingTestOutcome: Sendable {
        var test: String
        var passed: Bool
    }

    nonisolated static func testingExtractTestName(from line: String) -> String? {
        if let start = line.range(of: "Test Case '"),
           let end = line.range(of: "'", options: [], range: start.upperBound..<line.endIndex) {
            let name = String(line[start.upperBound..<end.lowerBound])
            if !name.isEmpty { return name }
        }
        if let bracketStart = line.range(of: "-["),
           let bracketEnd = line.range(of: "]", options: [], range: bracketStart.upperBound..<line.endIndex) {
            let name = String(line[bracketStart.upperBound..<bracketEnd.lowerBound])
            if !name.isEmpty { return name }
        }
        return nil
    }

    nonisolated static func testingParseTestLogLines(_ content: String) -> (passed: Int, failed: Int, failedTests: [String], suiteLines: [String], errorLines: [String]) {
        var passed = 0
        var failed = 0
        var failedTests: [String] = []
        var suiteLines: [String] = []
        var errorLines: [String] = []
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.contains("Test Case") {
                let isPassed = line.contains(" passed")
                let isFailed = line.contains(" failed")
                if isPassed && !isFailed {
                    passed += 1
                } else if isFailed && !isPassed {
                    failed += 1
                    if let name = testingExtractTestName(from: line), !failedTests.contains(name) {
                        failedTests.append(name)
                    }
                }
            }
            if line.contains("Test Suite") && (line.contains("passed") || line.contains("failed")) {
                suiteLines.append(line)
            }
            if line.contains(": error:") || line.hasPrefix("error:") {
                errorLines.append(line)
            }
        }
        return (passed, failed, failedTests, suiteLines, errorLines)
    }

    nonisolated static func testingParseTestOutcomes(from content: String) -> [TestingTestOutcome] {
        var results: [TestingTestOutcome] = []
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.contains("Test Case") else { continue }
            let isPassed = line.contains(" passed")
            let isFailed = line.contains(" failed")
            guard isPassed != isFailed else { continue }
            if let name = testingExtractTestName(from: line) {
                results.append(TestingTestOutcome(test: name, passed: isPassed))
            }
        }
        return results
    }

    nonisolated static func testingParseCrashLog(_ text: String) -> (exception: String, terminationReason: String, crashedThread: String, frames: [String]) {
        var exception = ""
        var terminationReason = ""
        var crashedThread = ""
        var frames: [String] = []
        var inCrashedThread = false
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("Exception Type:") { exception = t }
            else if t.hasPrefix("Termination Reason:") { terminationReason = t }
            else if t.hasPrefix("Triggered by Thread:") || t.hasPrefix("Crashed Thread:") {
                crashedThread = t
                inCrashedThread = true
            } else if inCrashedThread {
                if t.isEmpty || (t.hasPrefix("Thread ") && !t.contains("Crashed")) { inCrashedThread = false }
                else if t.range(of: #"^\d+\s+\S+"#, options: .regularExpression) != nil {
                    frames.append(String(t.prefix(160)))
                    if frames.count >= 12 { inCrashedThread = false }
                }
            }
        }
        if exception.isEmpty, let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            exception = "Exception Type: \((json["exception"] as? [String: Any])?["type"] as? String ?? "unknown")"
            terminationReason = "Termination Reason: \((json["termination"] as? [String: Any])?["reason"] as? String ?? "unknown")"
        }
        return (exception, terminationReason, crashedThread, frames)
    }

    nonisolated static func testingParseFixtureFields(_ raw: String) throws -> [(name: String, type: String)] {
        var fields: [(name: String, type: String)] = []
        for part in raw.components(separatedBy: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let pieces = trimmed.components(separatedBy: ":")
            let fieldName = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let fieldType = pieces.count > 1 ? pieces[1].trimmingCharacters(in: .whitespacesAndNewlines) : "String"
            guard testingIsValidSwiftIdentifier(fieldName) else {
                throw NSError(domain: "AssistTestDataFactoryTool", code: 1, userInfo: [NSLocalizedDescriptionKey: "Field name '\(fieldName)' is not a valid Swift identifier."])
            }
            guard !fieldType.isEmpty else {
                throw NSError(domain: "AssistTestDataFactoryTool", code: 2, userInfo: [NSLocalizedDescriptionKey: "Field '\(fieldName)' has an empty type."])
            }
            fields.append((name: fieldName, type: fieldType))
        }
        guard !fields.isEmpty else {
            throw NSError(domain: "AssistTestDataFactoryTool", code: 3, userInfo: [NSLocalizedDescriptionKey: "fields produced no usable fields."])
        }
        return fields
    }

    nonisolated static func testingSampleJSONValue(for type: String, fieldName: String) -> String {
        switch type.lowercased() {
        case "int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32", "uint64":
            return "1"
        case "double", "float", "cgfloat":
            return "3.14"
        case "bool", "boolean":
            return "true"
        case "date":
            return "\"2026-01-01T00:00:00Z\""
        case "url":
            return "\"https://example.com/\(fieldName)\""
        case "uuid":
            return "\"00000000-0000-4000-8000-000000000001\""
        case "[string]", "array<string>":
            return "[\"Sample \(fieldName)\"]"
        case "[int]":
            return "[1]"
        default:
            return "\"Sample \(fieldName)\""
        }
    }

    nonisolated static func testingSampleSwiftValue(for type: String, fieldName: String) -> String {
        switch type.lowercased() {
        case "int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32", "uint64":
            return "1"
        case "double", "float", "cgfloat":
            return "3.14"
        case "bool", "boolean":
            return "true"
        case "date":
            return "Date(timeIntervalSince1970: 1767225600)"
        case "url":
            return "URL(string: \"https://example.com/\(fieldName)\")!"
        case "uuid":
            return "UUID(uuidString: \"00000000-0000-4000-8000-000000000001\")!"
        default:
            return "\"Sample \(fieldName)\""
        }
    }

    nonisolated static func testingBuildJSONFixture(fields: [(name: String, type: String)]) -> String {
        var lines: [String] = []
        lines.append("{")
        for (index, field) in fields.enumerated() {
            let comma = index < fields.count - 1 ? "," : ""
            lines.append("  \"\(field.name)\": \(testingSampleJSONValue(for: field.type, fieldName: field.name))\(comma)")
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    nonisolated static func testingBuildSwiftFixture(name: String, fields: [(name: String, type: String)]) -> String {
        var lines: [String] = []
        lines.append("import Foundation")
        lines.append("")
        lines.append("struct \(name) {")
        for field in fields {
            lines.append("    let \(field.name): \(field.type)")
        }
        lines.append("")
        lines.append("    static let sample = \(name)(")
        for (index, field) in fields.enumerated() {
            let comma = index < fields.count - 1 ? "," : ""
            lines.append("        \(field.name): \(testingSampleSwiftValue(for: field.type, fieldName: field.name))\(comma)")
        }
        lines.append("    )")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    func testingResolveFixtureURL(_ pathRaw: String, name: String, kind: String, in s: WorkspaceSession) -> URL? {
        if pathRaw.components(separatedBy: "/").contains("..") { return nil }
        let root = Self.folder(of: s.model).standardizedFileURL
        let ext = kind == "json" ? "json" : "swift"
        let candidate: URL
        if pathRaw.hasSuffix("/") {
            candidate = root.appendingPathComponent(pathRaw).appendingPathComponent("\(name).\(ext)").standardizedFileURL
        } else if pathRaw.hasSuffix(".json") || pathRaw.hasSuffix(".swift") {
            if pathRaw.hasPrefix("/") {
                candidate = URL(fileURLWithPath: pathRaw).standardizedFileURL
            } else {
                candidate = root.appendingPathComponent(pathRaw).standardizedFileURL
            }
        } else {
            candidate = root.appendingPathComponent(pathRaw).appendingPathComponent("\(name).\(ext)").standardizedFileURL
        }
        guard candidate.path != root.path, candidate.path.hasPrefix(root.path + "/") else { return nil }
        return candidate
    }

    nonisolated static func testingBuildUITestContent(testName: String, targetApp: String) -> String {
        var lines: [String] = []
        lines.append("import XCTest")
        lines.append("")
        lines.append("final class \(testName): XCTestCase {")
        lines.append("    private var app: XCUIApplication!")
        lines.append("")
        lines.append("    override func setUpWithError() throws {")
        lines.append("        continueAfterFailure = false")
        if targetApp.isEmpty {
            lines.append("        app = XCUIApplication()")
        } else {
            lines.append("        app = XCUIApplication(bundleIdentifier: \"\(targetApp)\")")
        }
        lines.append("    }")
        lines.append("")
        lines.append("    override func tearDownWithError() throws {")
        lines.append("        app = nil")
        lines.append("    }")
        lines.append("")
        lines.append("    func testLaunch() throws {")
        lines.append("        app.launch()")
        lines.append("        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), \"App did not reach the foreground after launch.\")")
        lines.append("        XCTAssertTrue(app.state == .runningForeground)")
        lines.append("    }")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    nonisolated static func testingBuildTestTargetContent(targetName: String, type: String) -> String {
        var lines: [String] = []
        lines.append("import XCTest")
        lines.append("")
        if type == "ui" {
            lines.append("final class \(targetName)Tests: XCTestCase {")
            lines.append("    func testLaunch() throws {")
            lines.append("        let app = XCUIApplication()")
            lines.append("        app.launch()")
            lines.append("        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))")
            lines.append("    }")
        } else {
            lines.append("final class \(targetName)Tests: XCTestCase {")
            lines.append("    func testExample() throws {")
            lines.append("        XCTAssertEqual(1 + 1, 2)")
            lines.append("    }")
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    func testingFindXcodeproj(in workspaceRoot: URL) -> URL? {
        let fm = FileManager.default
        if let top = try? fm.contentsOfDirectory(at: workspaceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for item in top where item.pathExtension == "xcodeproj" { return item }
        }
        guard let enumerator = fm.enumerator(at: workspaceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name == ".git" || name == "build" || name == "DerivedData" || name == "Pods" {
                enumerator.skipDescendants()
                continue
            }
            if url.pathExtension == "xcodeproj" { return url }
        }
        return nil
    }

    nonisolated static func testingMakePbxprojIDs(existing: String, count: Int) -> [String]? {
        var ids: [String] = []
        var attempts = 0
        while ids.count < count && attempts < 200 {
            attempts += 1
            let candidate = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24).uppercased())
            if candidate.count != 24 { continue }
            if existing.contains(candidate) { continue }
            if ids.contains(candidate) { continue }
            ids.append(candidate)
        }
        return ids.count == count ? ids : nil
    }

    nonisolated static func testingInsertPbxprojBlock(_ text: inout String, block: String, afterAnchor anchor: String) -> Bool {
        guard let range = text.range(of: anchor) else { return false }
        guard let lineEnd = text.range(of: "\n", options: [], range: range.upperBound..<text.endIndex) else { return false }
        text.insert(contentsOf: block, at: lineEnd.upperBound)
        return true
    }

    nonisolated static func testingInsertTestTarget(into pbxproj: String, targetName: String, type: String, ids: [String]) -> String? {
        guard ids.count >= 7 else { return nil }
        let targetID = ids[0]
        let productRefID = ids[1]
        let sourcesID = ids[2]
        let frameworksID = ids[3]
        let configListID = ids[4]
        let debugConfigID = ids[5]
        let releaseConfigID = ids[6]
        let productType = type == "ui" ? "com.apple.product-type.bundle.ui-testing" : "com.apple.product-type.bundle.unit-test"
        let productName = "\(targetName).xctest"
        let targetBlock = "\t\t\(targetID) /* \(targetName) */ = {\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = \(configListID) /* Build configuration list for PBXNativeTarget \"\(targetName)\" */;\n\t\t\tbuildPhases = (\n\t\t\t\t\(sourcesID) /* Sources */,\n\t\t\t\t\(frameworksID) /* Frameworks */,\n\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = \(targetName);\n\t\t\tproductName = \(targetName);\n\t\t\tproductReference = \(productRefID) /* \(productName) */;\n\t\t\tproductType = \"\(productType)\";\n\t\t};\n"
        let fileRefBlock = "\t\t\(productRefID) /* \(productName) */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = \(productName); sourceTree = BUILT_PRODUCTS_DIR; };\n"
        let sourcesBlock = "\t\t\(sourcesID) /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n"
        let frameworksBlock = "\t\t\(frameworksID) /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n"
        let configListBlock = "\t\t\(configListID) /* Build configuration list for PBXNativeTarget \"\(targetName)\" */ = {\n\t\t\tisa = XCBuildConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t\(debugConfigID) /* Debug */,\n\t\t\t\t\(releaseConfigID) /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t};\n"
        let debugBlock = "\t\t\(debugConfigID) /* Debug */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;\n\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;\n\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n\t\t\t\tSWIFT_EMBED_LIBRARIES_WITH_INSTALL = YES;\n\t\t\t};\n\t\t\tname = Debug;\n\t\t};\n"
        let releaseBlock = "\t\t\(releaseConfigID) /* Release */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;\n\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;\n\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n\t\t\t\tSWIFT_EMBED_LIBRARIES_WITH_INSTALL = YES;\n\t\t\t};\n\t\t\tname = Release;\n\t\t};\n"
        var text = pbxproj
        guard testingInsertPbxprojBlock(&text, block: targetBlock, afterAnchor: "/* Begin PBXNativeTarget section */"),
              testingInsertPbxprojBlock(&text, block: fileRefBlock, afterAnchor: "/* Begin PBXFileReference section */"),
              testingInsertPbxprojBlock(&text, block: sourcesBlock, afterAnchor: "/* Begin PBXSourcesBuildPhase section */"),
              testingInsertPbxprojBlock(&text, block: frameworksBlock, afterAnchor: "/* Begin PBXFrameworksBuildPhase section */"),
              testingInsertPbxprojBlock(&text, block: configListBlock, afterAnchor: "/* Begin XCBuildConfigurationList section */"),
              testingInsertPbxprojBlock(&text, block: debugBlock, afterAnchor: "/* Begin XCBuildConfiguration section */"),
              testingInsertPbxprojBlock(&text, block: releaseBlock, afterAnchor: "/* Begin XCBuildConfiguration section */"),
              testingInsertPbxprojBlock(&text, block: "\t\t\t\t\(targetID) /* \(targetName) */,\n", afterAnchor: "targets = (") else {
            return nil
        }
        return text
    }

    nonisolated static func testingFindSnapshotFiles(in workspaceRoot: URL) -> [URL] {
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: workspaceRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name == ".git" || name == "build" || name == "DerivedData" || name == "Pods" {
                enumerator.skipDescendants()
                continue
            }
            guard url.pathComponents.contains("__Snapshots__") else { continue }
            let ext = url.pathExtension.lowercased()
            guard ["png", "jpg", "jpeg", "gif", "txt", "json"].contains(ext) else { continue }
            results.append(url)
        }
        return results.sorted { $0.path < $1.path }
    }

    nonisolated static func testingCollectSwiftSourceText(in workspaceRoot: URL) -> String {
        var combined = ""
        guard let enumerator = FileManager.default.enumerator(at: workspaceRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return "" }
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name == ".git" || name == "build" || name == "DerivedData" || name == "Pods" {
                enumerator.skipDescendants()
                continue
            }
            guard url.pathExtension.lowercased() == "swift" else { continue }
            if url.pathComponents.contains("__Snapshots__") { continue }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                combined += "\n" + text
            }
        }
        return combined
    }

    nonisolated static func testingSnapshotIsReferenced(_ file: URL, in sourceText: String) -> Bool {
        let base = file.deletingPathExtension().lastPathComponent
        if base.isEmpty { return false }
        if sourceText.contains(base) { return true }
        let parts = base.components(separatedBy: ".").filter { !$0.isEmpty }
        for part in parts where part.count >= 3 {
            if sourceText.contains(part) { return true }
        }
        let stripped = base.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        if stripped.count >= 3 && sourceText.contains(stripped) { return true }
        return false
    }
}
