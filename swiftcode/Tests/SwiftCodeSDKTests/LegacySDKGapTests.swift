import XCTest
@testable import SwiftCodeSDK
import SwiftCodeExtensions

// MARK: - Legacy SDK gap tests (Wave 18)
//
// Two leftovers from Legacy's SDK test files that the Wave 14/15 ports
// did not carry over, ported from Dylan's own code (direct port
// authorised under MIT):
//
//   - `testCloudModelKeylessKeepsGrantPath`, from
//     `SwiftCode/SDK/Host/APIKeys/SDKAssistEnforcementTests.swift`:
//     a keyless caller keeps the pre-entitlement grant path, so a
//     grantless extension gets `.permissionDenied`, not the
//     entitlement denial. The other two Legacy tests this file was
//     missing are already covered: the "no key" session case is the
//     unentitled-key case in `SDKAssistEnforcementTests` (SwiftCode
//     requires a key for every Assist call), and the
//     allows-cloud-only case is
//     `testAllowsCloudEntitlementAloneOpensCloudGate`.
//   - the canonical-capability check from
//     `SwiftCode/SDK/Tests/SDKTestRunner/main.swift` (test 5): every
//     one of the 32 canonical capability ids must parse as an
//     `SDKCapabilityID`. SwiftCode adds one more (`assist.main`); the
//     count assertion is a lower bound so a future capability does
//     not break this test.
//
// No Swift toolchain exists in this environment, so these tests have
// NOT been compiled or run — statically verified only. On Dylan's Mac:
// run with `swift test --filter LegacySDKGapTests`.

final class LegacySDKGapTests: XCTestCase {

    func testCloudModelKeylessKeepsGrantPath() async {
        // No grant for this extension id: the keyless caller must get
        // .permissionDenied from the grant lookup, not the cloud-model
        // entitlement denial (which only applies to keyed callers).
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
        // The exact 32 ids Legacy's SDK test runner asserted.
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
        // SwiftCode adds `assist.main`; the set must only grow.
        XCTAssertGreaterThanOrEqual(SDKCapabilityID.allCases.count, 32)
        XCTAssertTrue(Set(legacyCanonical).isSubset(of: Set(SDKCapabilityID.allCases.map(\.rawValue))))
    }
}
