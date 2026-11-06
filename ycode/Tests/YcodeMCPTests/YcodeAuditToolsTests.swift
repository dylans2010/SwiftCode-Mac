import Foundation
import Testing
@testable import YcodeMCP

/// The ported Legacy security / privacy / platform audit tools (Wave 6,
/// slice C), each driven through the server's real write-policy path
/// against a copy of `Samples/AgentSamples/Greeter`.
@MainActor
@Suite(.serialized) struct YcodeAuditToolsTests {
    /// Opens a copy of Greeter and installs the audit tools on the
    /// server. (Wiring `auditTools` into `installTools()` is the
    /// coordinator's integration step; the tests install them directly
    /// so the tools still run through `MCPServer.run`'s write-policy
    /// gate.)
    func opened(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> YcodeMCPHost {
        let host = YcodeMCPHost()
        host.server.writePolicy = policy
        host.server.tools += host.auditTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    /// Writes `content` to `rel` inside the sample workspace, creating
    /// parent directories.
    func write(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = sample.url.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func writeData(_ sample: TempSample, _ rel: String, _ data: Data) throws {
        let url = sample.url.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// Serializes a dictionary as an XML plist at `rel`.
    func writePlist(_ sample: TempSample, _ rel: String, _ dict: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try writeData(sample, rel, data)
    }

    /// A minimal 64-bit Mach-O header (32 bytes, no load commands):
    /// magic `0xFEEDFACF`, arm64, file type executable.
    static func minimalMachO() -> Data {
        var bytes: [UInt8] = []
        func u32(_ v: UInt32) { bytes += [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)] }
        u32(0xFEEDFACF); u32(0x0100000C); u32(0); u32(2); u32(0); u32(0); u32(0); u32(0)
        return Data(bytes)
    }

    /// A minimal arm64 Mach-O executable with one `LC_LOAD_DYLIB`
    /// (`/usr/lib/libSystem.B.dylib`, current/compat version 1.0).
    static func machOWithDylib() -> Data {
        var bytes: [UInt8] = []
        func u32(_ v: UInt32) { bytes += [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)] }
        u32(0xFEEDFACF); u32(0x0100000C); u32(0); u32(2); u32(1); u32(56); u32(0); u32(0)
        u32(0x0C); u32(56); u32(24); u32(0); u32(0x00010000); u32(0x00010000)
        var name = Array("/usr/lib/libSystem.B.dylib".utf8) + [0]
        while name.count < 32 { name.append(0) }
        bytes += name
        return Data(bytes)
    }

    @Test func toolsAreListedWithSchemasAndAnnotations() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        #expect(host.auditTools.map(\.name) == ["memory_leak_detector", "security_audit_scanner", "bundle_resource_auditor",
                                                 "core_data_model_inspector", "swift_data_schema_auditor", "privacy_manifest_auditor",
                                                 "mach_o_binary_analyzer", "framework_linker_auditor", "network_security_auditor",
                                                 "accessibility_audit_scanner", "license_header_check", "access_level_audit",
                                                 "binary_size_report", "secrets_scan", "permissions_audit", "accessibility_audit",
                                                 "dependency_licenses", "image_asset_size_report"])
        let list = try await host.server.handle(method: "tools/list", params: nil, connection: MCPServer.Connection())
        let tools = list["tools"]?.array ?? []
        func listing(_ name: String) throws -> AnyJSON { try #require(tools.first { $0["name"] == name }) }
        func required(_ name: String) throws -> [String] {
            try listing(name)["inputSchema"]?["required"]?.array?.compactMap(\.string) ?? []
        }
        #expect(try required("memory_leak_detector") == ["path"])
        #expect(try required("security_audit_scanner") == ["path"])
        #expect(try required("privacy_manifest_auditor") == ["action"])
        #expect(try required("mach_o_binary_analyzer") == ["binaryPath"])
        #expect(try required("accessibility_audit_scanner") == ["path"])
        #expect(try required("license_header_check") == [])
        #expect(try required("permissions_audit") == [])
        #expect(try required("dependency_licenses") == [])
        #expect(try required("image_asset_size_report") == [])
        // Catalogue §1.3 risk table: safeRead → read-only, safeMutation
        // → writes. Only privacy_manifest_auditor writes in this family.
        let manifest = try listing("privacy_manifest_auditor")
        #expect(manifest["annotations"]?["readOnlyHint"] == false && manifest["annotations"]?["idempotentHint"] == true)
        let scanner = try listing("security_audit_scanner")
        #expect(scanner["annotations"]?["readOnlyHint"] == true && scanner["annotations"]?["idempotentHint"] == true)
        #expect(try listing("security_audit_scanner")["description"]?.string
            == "Scans Swift source files for hardcoded secrets, API keys, insecure HTTP endpoints, and unsafe storage practices.")
        #expect(try listing("mach_o_binary_analyzer")["description"]?.string
            == "Inspects built application binaries, architectures (arm64, x86_64), and linked dynamic libraries via otool and file.")
        #expect(try listing("secrets_scan")["description"]?.string
            == "Scans source and config files for secret patterns. Reports file:line:pattern only and never outputs matched secret values.")
        #expect(try listing("mach_o_binary_analyzer")["inputSchema"]?["properties"]?["binaryPath"]?["description"]?.string
            == "Relative or absolute path to the compiled binary or executable file.")
    }

    @Test func securityAuditFlagsHttpCredentialAndPrint() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try write(sample, "Audit/Bad.swift", """
            import Foundation
            let url = URL(string: "http://example.com/api")!
            let api_key = "abc123"
            print("token is \\(url)")
            """)
        let flagged = try await host.server.callTool("security_audit_scanner", ["path": .string("Audit")])
        #expect(!flagged.isToolError)
        #expect(flagged.firstText.contains("[ATS] Insecure plaintext HTTP URL detected"))
        #expect(flagged.firstText.contains("[Credential] Potential hardcoded credential"))
        #expect(flagged.firstText.contains("[Privacy] Sensitive credential leaked"))
        try write(sample, "Audit/Clean.swift", "import Foundation\nlet url = URL(string: \"https://example.com\")!\n")
        let clean = try await host.server.callTool("security_audit_scanner", ["path": .string("Audit/Clean.swift")])
        #expect(!clean.isToolError && clean.firstText.contains("Security Audit passed: 0 vulnerabilities"))
        let missing = try await host.server.callTool("security_audit_scanner", ["path": .string("Audit/Nope.swift")])
        #expect(missing.isToolError && missing.firstText.contains("Path does not exist: Audit/Nope.swift"))
    }

    @Test func networkSecurityAuditorReadsATS() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let none = try await host.server.callTool("network_security_auditor")
        #expect(!none.isToolError && none.firstText.contains("No valid Info.plist found in workspace."))
        try writePlist(sample, "App/Info.plist", ["NSAppTransportSecurity": [
            "NSAllowsArbitraryLoads": true,
            "NSExceptionDomains": ["example.com": ["NSIncludesSubdomains": true]],
        ] as [String: Any]])
        let flagged = try await host.server.callTool("network_security_auditor")
        #expect(!flagged.isToolError)
        #expect(flagged.firstText.contains("Allows Arbitrary HTTP Loads**: ⚠️ YES (Potential App Store Review Risk)"))
        #expect(flagged.firstText.contains("example.com"))
        try writePlist(sample, "App2/Info.plist", ["CFBundleName": "Greeter"])
        let secure = try await host.server.callTool("network_security_auditor", ["path": .string("App2/Info.plist")])
        #expect(!secure.isToolError && secure.firstText.contains("default secure mode"))
    }

    @Test func permissionsAuditFindsMissingLocationDescription() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writePlist(sample, "App/Info.plist", ["NSCameraUsageDescription": "To take photos."])
        try writePlist(sample, "PrivacyInfo.xcprivacy", [
            "NSPrivacyTracking": false,
            "NSPrivacyAccessedAPITypes": [["NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
                                           "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]]],
        ])
        try write(sample, "Sources/Location.swift", "import CoreLocation\nlet manager = CLLocationManager()\n")
        let r = try await host.server.callTool("permissions_audit")
        #expect(!r.isToolError)
        #expect(r.firstText.contains("CLLocationManager used in Sources/Location.swift but NSLocationWhenInUseUsageDescription is missing"))
        #expect(r.structured?["missing_count"] == 1)
        #expect(r.structured?["usage_description_count"] == 1)
        #expect(r.structured?["privacy_tracking"] == "false")
        #expect(r.structured?["privacy_api_count"] == 1)
    }

    @Test func privacyManifestAuditAndGenerate() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try write(sample, "Sources/Prefs.swift", "import Foundation\nlet defaults = UserDefaults.standard\n")
        let audit = try await host.server.callTool("privacy_manifest_auditor", ["action": .string("audit")])
        #expect(!audit.isToolError)
        #expect(audit.firstText.contains("PrivacyInfo.xcprivacy Present**: ❌ No (Action recommended)"))
        #expect(audit.firstText.contains("UserDefaults Usage**: 1 file(s)"))
        // Generate is a write: refused while the server is read-only.
        let refused = try await host.server.callTool("privacy_manifest_auditor", ["action": .string("generate")])
        #expect(refused.isToolError && refused.firstText.contains("read-only"))
        #expect(!FileManager.default.fileExists(atPath: sample.path("PrivacyInfo.xcprivacy")))
        let allowed = try await opened(sample, policy: .allow)
        let generated = try await allowed.server.callTool("privacy_manifest_auditor", ["action": .string("generate")])
        #expect(!generated.isToolError && generated.firstText.contains("Successfully generated compliant PrivacyInfo.xcprivacy"))
        #expect(sample.read("PrivacyInfo.xcprivacy").contains("NSPrivacyAccessedAPICategoryUserDefaults"))
        #expect(sample.read("PrivacyInfo.xcprivacy").contains("CA92.1"))
    }

    @Test func accessibilityAuditFlagsUnlabelledControls() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try write(sample, "Audit/A11y.swift", """
            import SwiftUI
            struct V: View {
                var body: some View {
                    Button("OK") { }.accessibilityLabel("OK")
                    Button("Tap") { }
                    Image(systemName: "star")
                    TextField("", text: .constant(""))
                    Text("x").foregroundColor(.red)
                }
            }
            """)
        let r = try await host.server.callTool("accessibility_audit", ["path": .string("Audit/A11y.swift")])
        #expect(!r.isToolError)
        #expect(r.structured?["finding_count"] == 4)
        #expect(r.structured?["files_scanned"] == 1)
        #expect(r.firstText.contains("Button without .accessibilityLabel (heuristic)"))
        #expect(r.firstText.contains("Image without .accessibilityLabel / .accessibilityHidden (heuristic)"))
        #expect(r.firstText.contains("TextField with empty label (heuristic)"))
        #expect(r.firstText.contains("Color-only state via foregroundColor (heuristic)"))
        let traversal = try await host.server.callTool("accessibility_audit", ["path": .string("../..")])
        #expect(traversal.isToolError && traversal.firstText.contains("Invalid path"))
    }

    @Test func accessibilityAuditScannerFlagsSymbolImages() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try write(sample, "Audit/Icons.swift", """
            import SwiftUI
            struct V: View {
                var body: some View {
                    Image(systemName: "moon")
                        .accessibilityLabel("Moon")
                    Image(systemName: "star")
                    Button("") { }
                }
            }
            """)
        let r = try await host.server.callTool("accessibility_audit_scanner", ["path": .string("Audit/Icons.swift")])
        #expect(!r.isToolError)
        #expect(r.firstText.contains("SF Symbol Image has no explicit `.accessibilityLabel`"))
        #expect(r.firstText.contains("Button with empty label has no VoiceOver text description."))
        #expect(!r.firstText.contains("moon"))
        let missing = try await host.server.callTool("accessibility_audit_scanner", ["path": .string("Audit/Nope.swift")])
        #expect(missing.isToolError && missing.firstText.contains("Path not found: Audit/Nope.swift"))
    }

    @Test func accessLevelAuditCountsDeclarations() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try write(sample, "Audit/Levels.swift", """
            public struct Foo { }
            open class Qux { }
            private func bar() { }
            func baz() { }
            """)
        let r = try await host.server.callTool("access_level_audit", ["path": .string("Audit/Levels.swift")])
        #expect(!r.isToolError)
        #expect(r.structured?["public"] == 1)
        #expect(r.structured?["open"] == 1)
        #expect(r.structured?["private"] == 1)
        #expect(r.structured?["internal"] == 1)
        #expect(r.structured?["total"] == 4)
        #expect(r.firstText.contains("Audit/Levels.swift: 2 public/open declaration(s)"))
        let greeter = try await host.server.callTool("access_level_audit", ["path": .string("Sources/Greeter")])
        #expect(!greeter.isToolError && greeter.firstText.contains("scanned 1 Swift file(s), 3 declaration(s)"))
        let traversal = try await host.server.callTool("access_level_audit", ["path": .string("..")])
        #expect(traversal.isToolError && traversal.firstText.contains("Invalid path: path must stay inside the workspace"))
    }

    @Test func dependencyLicensesReadsPackageResolved() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let none = try await host.server.callTool("dependency_licenses")
        #expect(!none.isToolError && none.firstText.contains("No resolvable dependency lockfiles found"))
        #expect(none.structured?["count"] == 0)
        try write(sample, "Package.resolved", """
            {"pins": [{"package": "Alamofire", "state": {"version": "5.9.0"}}]}
            """)
        let r = try await host.server.callTool("dependency_licenses")
        #expect(!r.isToolError)
        #expect(r.structured?["count"] == 1)
        #expect(r.firstText.contains("Alamofire"))
        #expect(r.firstText.contains("5.9.0"))
        #expect(r.firstText.contains("SwiftPM"))
    }

    @Test func frameworkLinkerAuditorReadsBuildPhase() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let none = try await host.server.callTool("framework_linker_auditor")
        #expect(!none.isToolError && none.firstText.contains("No project.pbxproj file found in workspace."))
        try write(sample, "App.xcodeproj/project.pbxproj", """
            // !$*UTF8*$!
            {
            \tobjects = {
            \t\tABC123 = {isa = PBXBuildFile; };
            \t\tDEF456 /* Frameworks */ = {
            \t\t\tisa = PBXFrameworksBuildPhase;
            \t\t\tfiles = (
            \t\t\t\tABC123 /* Foundation.framework in Frameworks */,
            \t\t\t);
            \t\t};
            \t};
            }
            """)
        let r = try await host.server.callTool("framework_linker_auditor")
        #expect(!r.isToolError)
        #expect(r.firstText.contains("Linked Frameworks & Dependencies (1)"))
        #expect(r.firstText.contains("Foundation.framework"))
    }

    @Test func memoryLeakDetectorFlagsStrongSelfAndDelegate() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try write(sample, "Audit/Leaks.swift", """
            import Combine
            final class C {
                var delegate: AnyObject?
                var cancellables = Set<AnyCancellable>()
                func go(_ p: AnyPublisher<Void, Never>) {
                    p.sink { self.update() }
                }
                func update() { }
            }
            """)
        let r = try await host.server.callTool("memory_leak_detector", ["path": .string("Audit/Leaks.swift")])
        #expect(!r.isToolError)
        #expect(r.firstText.contains("Potential retain cycle: escaping closure captures strong 'self'"))
        #expect(r.firstText.contains("Retain cycle risk: Delegate property should be declared 'weak var delegate'"))
        try write(sample, "Audit/Clean.swift", "import Foundation\nfinal class D { weak var delegate: AnyObject? }\n")
        let clean = try await host.server.callTool("memory_leak_detector", ["path": .string("Audit/Clean.swift")])
        #expect(!clean.isToolError && clean.firstText.contains("Memory Leak Scan passed"))
        let missing = try await host.server.callTool("memory_leak_detector", ["path": .string("Audit/Nope.swift")])
        #expect(missing.isToolError && missing.firstText.contains("Path not found: Audit/Nope.swift"))
    }

    @Test func machOBinaryAnalyzerParsesWithYcodeMachO() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let missing = try await host.server.callTool("mach_o_binary_analyzer", ["binaryPath": .string("Nope")])
        #expect(missing.isToolError && missing.firstText.contains("Binary file not found at:"))
        try write(sample, "not-a-binary.txt", "hello, world\n")
        let notMachO = try await host.server.callTool("mach_o_binary_analyzer", ["binaryPath": .string("not-a-binary.txt")])
        #expect(notMachO.isToolError && notMachO.firstText.contains("Not a Mach-O binary:"))
        try writeData(sample, "thin.bin", Self.minimalMachO())
        let thin = try await host.server.callTool("mach_o_binary_analyzer", ["binaryPath": .string("thin.bin")])
        #expect(!thin.isToolError)
        #expect(thin.firstText.contains("arm64"))
        #expect(thin.firstText.contains("executable"))
        #expect(thin.firstText.contains("Linked Dynamic Libraries (0)"))
        try writeData(sample, "dylib.bin", Self.machOWithDylib())
        let linked = try await host.server.callTool("mach_o_binary_analyzer", ["binaryPath": .string("dylib.bin")])
        #expect(!linked.isToolError)
        #expect(linked.firstText.contains("/usr/lib/libSystem.B.dylib"))
        #expect(linked.firstText.contains("current 1.0"))
        #expect(linked.firstText.contains("Linked Dynamic Libraries (1)"))
    }

    @Test func coreDataModelInspectorParsesEntities() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let none = try await host.server.callTool("core_data_model_inspector")
        #expect(!none.isToolError && none.firstText.contains("No .xcdatamodeld Core Data models found"))
        try write(sample, "Model.xcdatamodeld/Model.xcdatamodel/contents", """
            <?xml version="1.0" encoding="UTF-8"?>
            <model>
            <entity name="Person">
            <attribute name="name" attributeType="String"/>
            <attribute name="age" attributeType="Integer 16"/>
            </entity>
            </model>
            """)
        let r = try await host.server.callTool("core_data_model_inspector", ["path": .string("Model.xcdatamodeld")])
        #expect(!r.isToolError)
        #expect(r.firstText.contains("Core Data Model: `Model.xcdatamodeld` (1 entities)"))
        #expect(r.firstText.contains("Entity `Person`"))
        #expect(r.firstText.contains("name: String"))
        #expect(r.firstText.contains("age: Integer 16"))
    }

    @Test func swiftDataSchemaAuditorFindsModels() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let none = try await host.server.callTool("swift_data_schema_auditor")
        #expect(!none.isToolError && none.firstText.contains("No SwiftData `@Model` classes discovered"))
        try write(sample, "Sources/Note.swift", """
            import SwiftData
            @Model
            final class Note {
                var title: String
                @Attribute(.unique) var id: UUID
            }
            """)
        let r = try await host.server.callTool("swift_data_schema_auditor")
        #expect(!r.isToolError)
        #expect(r.firstText.contains("@Model class Note"))
        #expect(r.firstText.contains("var title: String"))
    }

    @Test func bundleResourceAuditorFindsMissingImage() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try FileManager.default.createDirectory(at: sample.url.appendingPathComponent("Assets.xcassets"),
                                                withIntermediateDirectories: true)
        try write(sample, "a.imageset.json/Contents.json", """
            {"images": [{"filename": "gone.png"}]}
            """)
        let r = try await host.server.callTool("bundle_resource_auditor")
        #expect(!r.isToolError)
        #expect(r.firstText.contains("Asset Catalogs**: 1 found"))
        #expect(r.firstText.contains("Missing image asset: `a.imageset.json/Contents.json` references `gone.png`"))
    }

    @Test func binarySizeReportSizesAppBundles() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let none = try await host.server.callTool("binary_size_report", ["path": .string("Sources")])
        #expect(!none.isToolError && none.firstText.contains("No .app bundles found under 'Sources'."))
        #expect(none.structured?["appCount"] == 0)
        try write(sample, "build/MyApp.app/Contents/MacOS/MyApp", String(repeating: "x", count: 100))
        try write(sample, "build/MyApp.app/Contents/Resources/big.dat", String(repeating: "y", count: 5000))
        let r = try await host.server.callTool("binary_size_report", ["path": .string("build")])
        #expect(!r.isToolError)
        #expect(r.structured?["appCount"] == 1)
        #expect(r.structured?["totalBytes"] == 5100)
        #expect(r.firstText.contains("MyApp.app — total 5.0 KB (5100 bytes)"))
        #expect(r.firstText.contains("Grand total: 5.0 KB (5100 bytes)"))
        let missing = try await host.server.callTool("binary_size_report", ["path": .string("nope")])
        #expect(missing.isToolError && missing.firstText.contains("Path not found at 'nope'."))
    }

    @Test func imageAssetSizeReportFlagsOversized() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let none = try await host.server.callTool("image_asset_size_report")
        #expect(!none.isToolError && none.firstText.contains("No image files found inside .xcassets catalogs."))
        try writeData(sample, "Assets.xcassets/Big.imageset/big.png", Data(repeating: 0, count: 600_000))
        try writeData(sample, "Assets.xcassets/Small.imageset/small.png", Data(repeating: 0, count: 100))
        let r = try await host.server.callTool("image_asset_size_report")
        #expect(!r.isToolError)
        #expect(r.structured?["imageCount"] == 2)
        #expect(r.structured?["oversizedCount"] == 1)
        #expect(r.structured?["totalBytes"] == 600_100)
        #expect(r.firstText.contains("Oversized (≥500 KB): 1"))
        #expect(r.firstText.contains("Assets.xcassets/Big.imageset/big.png"))
        let lenient = try await host.server.callTool("image_asset_size_report", ["thresholdKB": .int(1000)])
        #expect(!lenient.isToolError && lenient.structured?["oversizedCount"] == 0)
        #expect(lenient.firstText.contains("All images are under the threshold."))
    }

    @Test func licenseHeaderCheckCountsMissingHeaders() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try write(sample, "Audit/With.swift", "// Copyright (c) 2026 Dylan\nimport Foundation\n")
        try write(sample, "Audit/Without.swift", "import Foundation\nstruct S { }\n")
        let r = try await host.server.callTool("license_header_check", ["path": .string("Audit")])
        #expect(!r.isToolError)
        #expect(r.structured?["scannedFiles"] == 2)
        #expect(r.structured?["withHeader"] == 1)
        #expect(r.structured?["missingHeader"] == 1)
        #expect(r.firstText.contains("Audit/Without.swift"))
        let custom = try await host.server.callTool("license_header_check",
                                                    ["path": .string("Audit"), "requiredText": .string("MIT License")])
        #expect(!custom.isToolError && custom.structured?["missingHeader"] == 2)
    }

    @Test func secretsScanNeverOutputsSecretValues() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        // The AWS example key from the public documentation (not a real secret),
        // assembled from parts so the literal never appears in tracked source
        // (scan-public flags the AKIA pattern).
        let awsExampleKey = "AKIA" + "IOSFODNN7EXAMPLE"
        try write(sample, "Audit/Secrets.swift", """
            import Foundation
            let key = "\(awsExampleKey)"
            let password = "hunter2"
            """)
        try write(sample, "Audit/Clean.swift", "import Foundation\nlet greeting = \"hello\"\n")
        let r = try await host.server.callTool("secrets_scan", ["path": .string("Audit")])
        #expect(!r.isToolError)
        #expect(r.structured?["finding_count"] == 2)
        #expect(r.structured?["files_scanned"] == 2)
        #expect(r.structured?["files_with_findings"] == 1)
        #expect(r.firstText.contains("Audit/Secrets.swift:2:AWS Access Key ID"))
        #expect(r.firstText.contains("Audit/Secrets.swift:3:password assignment"))
        #expect(!r.firstText.contains(awsExampleKey))
        #expect(!r.firstText.contains("hunter2"))
        let traversal = try await host.server.callTool("secrets_scan", ["path": .string("../..")])
        #expect(traversal.isToolError && traversal.firstText.contains("Invalid path: '../..'"))
    }
}
