import Foundation

public struct AssistGenerateTestsTool: AssistTool {
    public let id = "intel_generate_tests"
    public let name = "Generate Tests"
    public let description = "Generates unit test stubs for Swift types with proper setup and teardown."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }

        do {
            let source = try context.fileSystem.readFile(at: path)
            let sourceName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let testPath = (input["testPath"] as? String) ?? "Tests/\(sourceName)Tests.swift"

            // Extract function names for test generation
            let functionRegex = try NSRegularExpression(pattern: "\\bfunc\\s+([A-Za-z_][A-Za-z0-9_]*)", options: [])
            let range = NSRange(location: 0, length: source.utf16.count)
            let functionNames = functionRegex.matches(in: source, options: [], range: range).compactMap { match -> String? in
                guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: source) else { return nil }
                return String(source[r])
            }

            // Extract types (class, struct, enum, actor)
            let types = extractTypes(from: source)

            var body = """
import XCTest
@testable import SwiftCode

/// Generated tests for \(path)
final class \(sourceName)Tests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        try super.tearDownWithError()
    }


"""

            if functionNames.isEmpty && types.isEmpty {
                body += """
    func testPlaceholder() {
        // No functions detected in source file. Add your tests here.
        XCTAssertTrue(true, "Replace with actual test implementation")
    }

"""
            } else {
                // Generate tests for types
                for typeName in types.prefix(10) {
                    body += """
    // MARK: - Tests for \(typeName)

    func test\(typeName)_Initialization() {
        // TODO: Test initialization of \(typeName)
        // Example:
        // let instance = \(typeName)()
        // XCTAssertNotNil(instance, "\(typeName) should initialize")
    }


"""
                }

                // Generate tests for functions
                for funcName in functionNames.prefix(10) {
                    body += """
    func test_\(funcName)() {
        // TODO: Test \(funcName) behavior
        // Example:
        // let result = someInstance.\(funcName)()
        // XCTAssertEqual(result, expectedValue, "\(funcName) should return expected value")
    }


"""
                }
            }

            body += """
    func testPerformance() {
        measure {
            // Put performance test code here
        }
    }
}

"""

            try context.fileSystem.writeFile(at: testPath, content: body)

            let testCount = max(1, functionNames.count + types.count)
            await context.logger.info("Generated \(testCount) test stubs for \(types.count) types and \(functionNames.count) functions", toolId: id)

            return .success(
                "Tests generated for \(path) with \(testCount) test methods",
                data: [
                    "test_path": testPath,
                    "test_count": "\(testCount)",
                    "types_count": "\(types.count)",
                    "functions_count": "\(functionNames.count)"
                ]
            )
        } catch {
            return .failure("Failed generating tests for \(path): \(error.localizedDescription)")
        }
    }

    private func extractTypes(from content: String) -> [String] {
        var types: [String] = []
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Match: class MyClass, struct MyStruct, enum MyEnum, actor MyActor
            if let match = trimmed.range(of: "^(public |private |internal |fileprivate )?(final )?(class|struct|enum|actor)\\s+([A-Za-z0-9_]+)", options: .regularExpression) {
                let matched = String(trimmed[match])
                let components = matched.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                // Last component is the type name
                if let typeName = components.last, !typeName.contains("{") && !typeName.contains(":") {
                    types.append(typeName)
                }
            }
        }

        return types
    }
}
