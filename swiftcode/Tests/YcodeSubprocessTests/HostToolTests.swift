import Foundation
import Testing
import YcodeSubprocess

@Suite struct HostToolTests {
    private let flatpak = ["FLATPAK_ID": "io.github.MarcoDotIO.Ycode"]

    @Test func aToolIsInUsrBinOutsideTheFlatpak() {
        #expect(HostTool.path("git", environment: [:], toolDirectory: "/p/libexec/swiftcode-host") == "/usr/bin/git")
        #expect(!HostTool.isInFlatpak(environment: ["FLATPAK_ID": ""]))
    }

    @Test func aToolIsTheWrapperInTheFlatpak() {
        #expect(HostTool.path("git", environment: flatpak, toolDirectory: "/p/libexec/swiftcode-host") == "/p/libexec/swiftcode-host/git")
        #expect(HostTool.path("git", environment: flatpak, toolDirectory: nil) == "/usr/bin/git")
    }

    @Test func theWrappersAreFoundFromTheExecutableWhereverThePackageIs() {
        let exe = URL(fileURLWithPath: "/anywhere/SwiftCode-x/bin/swiftcode-ide")
        #expect(HostTool.packagedToolDirectory(executable: exe) { $0 == "/anywhere/SwiftCode-x/libexec/swiftcode-host" } == "/anywhere/SwiftCode-x/libexec/swiftcode-host")
        #expect(HostTool.packagedToolDirectory(executable: exe) { _ in false } == nil)
    }

    @Test func aHostProcessRunsAnOwnToolDirectlyOutsideTheFlatpak() {
        #expect(HostTool.commandOnHost(tool: "/x/swiftcode-bsp", arguments: ["serve"], environment: [:]) == ["/x/swiftcode-bsp", "serve"])
    }

    @Test func aHostProcessRunsAnOwnToolThroughFlatpakRun() {
        #expect(HostTool.commandOnHost(tool: "/app/bin/swiftcode-bsp", arguments: ["serve", "/p"], environment: flatpak)
            == ["flatpak", "run", "--command=swiftcode-bsp", "io.github.MarcoDotIO.Ycode", "serve", "/p"])
    }
}
