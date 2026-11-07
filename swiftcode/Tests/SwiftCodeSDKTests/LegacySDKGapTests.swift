import XCTest
@testable import SwiftCodeSDK
import SwiftCodeExtensions

final class LegacySDKGapTests: XCTestCase {

    func testCloudModelKeylessKeepsGrantPath() async {
        let caller = SDKCallerIdentity(
            extensionID: "com.swiftcode.sdk.test.no-grants-\(UUID().uuidString)",
            packageDigest: "",
            projectRootPath: "",
            apiKey: nil)
        do {
            try await SDKCapabilityBroker.authorize(.useSwiftCodeModel, for: caller)
            XCTFail("expected .permissionDenied for a grantless keyless caller")
        } catch let sdkError as SDKError {
            XCTAssertEqual(sdkError.code, .permissionDenied)
        } catch {
            XCTFail("expected SDKError, got \(type(of: error))")
        }
    }

    func testLegacyCanonicalCapabilitiesRecognized() {
        let legacyCanonical = [
            "project.read", "workspace.read", "workspace.write",
            "source-control.read", "source-control.write",
            "build.execute", "task.execute", "network.request",
            "ui.contribute", "credentials.use", "use.Security",
            "assist.invoke", "assist.ui", "assist.headless",
            "db.ExploreView", "ci.VisualWF", "virtualization.view",
            "deployConsole.view", "use.SwiftCodeModel", "terminal.sandbox",
            "simulator.view", "preview.live", "uibuilder.open",
            "symbols.browse", "docs.search", "dictionary.open",
            "deviceconnect.open", "security.addValue", "security.hasValue",
            "security.listValueIDs", "security.deleteValue", "security.useValue",
        ]
        XCTAssertEqual(legacyCanonical.count, 32)
        for id in legacyCanonical {
            XCTAssertNotNil(SDKCapabilityID(rawValue: id),
                            "Canonical capability \(id) is not recognized")
        }
        XCTAssertGreaterThanOrEqual(SDKCapabilityID.allCases.count, 32)
        XCTAssertTrue(Set(legacyCanonical).isSubset(of: Set(SDKCapabilityID.allCases.map(\.rawValue))))
    }
}
