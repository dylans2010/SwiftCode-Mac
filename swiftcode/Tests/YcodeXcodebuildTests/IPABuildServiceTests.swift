#if os(macOS)

import Foundation
import Testing
import YcodeXcodebuild

@Suite("IPABuildService")
@MainActor
struct IPABuildServiceTests {

    @Test("getShellScriptPath resolves to an existing script file")
    func shellScriptPathResolves() {
        let service = IPABuildService.shared
        let path = service.getShellScriptPath()
        #expect(!path.isEmpty)
        #expect(FileManager.default.fileExists(atPath: path),
                "expected the resolved build_ipa.sh (bundle, CWD, or embedded fallback) to exist")
        #expect(path.hasSuffix("build_ipa.sh"))
    }

    @Test("newestManagedAppBundle is nil for a project with no managed builds")
    func newestManagedAppBundleNil() {
        let service = IPABuildService.shared
        #expect(service.newestManagedAppBundle(projectName: "NoSuchProject-\(UUID().uuidString)") == nil)
    }

    @Test("managedBuildsDirectory is namespaced per project")
    func managedBuildsDirectoryNamespaced() {
        let service = IPABuildService.shared
        let dir = service.managedBuildsDirectory(projectName: "MyApp")
        #expect(dir.lastPathComponent.contains("MyApp"))
    }
}

#endif
