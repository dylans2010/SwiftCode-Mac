import Foundation
import Testing
import YcodeSigning
@testable import YcodeIDECore

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/StoreKit")

private func tempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@MainActor
struct EntitlementsEditorModelTests {
    @Test("A real .entitlements file round-trips through save and re-read")
    func roundTrip() throws {
        let source = fixtures.appendingPathComponent("App.entitlements")
        let model = try EntitlementsEditorModel(url: source)
        #expect(model.entitlements.count == 4)
        #expect(model.sandboxIsOn)
        #expect(model.stringArray(forKey: "com.apple.security.application-groups") == ["group.com.example.app"])

        let sandbox = try #require(EntitlementCapabilityCatalog.definition(for: "com.apple.security.app-sandbox"))
        model.setCapability(sandbox, on: false)
        #expect(model.entitlements["com.apple.security.app-sandbox"] == nil)
        #expect(model.isDirty)
        model.setCapability(sandbox, on: true)
        #expect(model.entitlements["com.apple.security.app-sandbox"] == .bool(true))

        let out = tempDir().appendingPathComponent("Out.entitlements")
        try model.save(to: out)
        let reparsed = try EntitlementsEditorModel(url: out)
        #expect(reparsed.entitlements == model.entitlements)
        #expect(reparsed.entitlements["aps-environment"] == .string("development"))
    }

    @Test("A missing file starts empty, like Legacy's readEntitlements")
    func missingFileStartsEmpty() throws {
        let missing = tempDir().appendingPathComponent("Missing.entitlements")
        let model = try EntitlementsEditorModel(url: missing)
        #expect(model.entitlements.isEmpty)
        #expect(!model.sandboxIsOn)
    }

    @Test("The catalog has one definition per raw key")
    func catalogUniqueKeys() throws {
        let defs = EntitlementCapabilityCatalog.definitions
        #expect(defs.count == 123)
        #expect(Set(defs.map(\.rawKey)).count == defs.count)
        #expect(defs.filter { $0.requiresSpecialApproval }.count == 33)
        for section in EntitlementCapabilitySection.allCases where section != .all && section != .other {
            #expect(!EntitlementCapabilityCatalog.definitions(in: section).isEmpty, "empty section \(section)")
        }
    }

    @Test("The catalog covers Legacy's 17-entry manager catalog")
    func catalogCoversManagerKeys() throws {
        let managerKeys = [
            "com.apple.security.app-sandbox",
            "com.apple.security.network.client",
            "com.apple.security.network.server",
            "com.apple.security.device.camera",
            "com.apple.security.device.audio-input",
            "com.apple.security.assets.downloads.read-write",
            "com.apple.security.device.usb",
            "com.apple.security.application-groups",
            "keychain-access-groups",
            "aps-environment",
            "com.apple.developer.applesignin",
            "com.apple.developer.associated-domains",
            "com.apple.developer.live-activities",
            "com.apple.developer.weatherkit",
            "com.apple.developer.virtualization",
            "com.apple.developer.proximity-reader.payment.acceptance",
            "com.apple.developer.dock-accessory",
        ]
        #expect(managerKeys.count == 17)
        for key in managerKeys {
            #expect(EntitlementCapabilityCatalog.definition(for: key) != nil, "missing \(key)")
        }
    }

    @Test("Toggling a capability writes its default and removes it again")
    func capabilityToggle() throws {
        let model = EntitlementsEditorModel()
        let push = try #require(EntitlementCapabilityCatalog.definition(for: "aps-environment"))
        #expect(!model.isCapabilityOn(push))
        model.setCapability(push, on: true)
        #expect(model.entitlements["aps-environment"] == .string("development"))
        model.setString("production", forKey: "aps-environment")
        #expect(model.entitlements["aps-environment"] == .string("production"))
        model.setCapability(push, on: false)
        #expect(model.entitlements["aps-environment"] == nil)
    }

    @Test("The iCloud toggle controls all three composite keys")
    func iCloudCompositeToggle() throws {
        let model = EntitlementsEditorModel()
        let iCloud = try #require(EntitlementCapabilityCatalog.definition(for: EntitlementCapabilityCatalog.iCloudContainersKey))
        model.setCapability(iCloud, on: true)
        #expect(model.entitlements[EntitlementCapabilityCatalog.iCloudContainersKey] == .array([]))
        #expect(model.entitlements[EntitlementCapabilityCatalog.iCloudKVStoreKey] == .string("$(TeamIdentifierPrefix)$(CFBundleIdentifier)"))
        #expect(model.isCapabilityOn(iCloud))
        model.setICloudContainers(["iCloud.com.example.app"])
        model.setUbiquitousContainer(id: "iCloud.com.example.app", name: "Example", isPublic: false, folderLevels: "")
        #expect(model.ubiquitousContainers().count == 1)
        model.setCapability(iCloud, on: false)
        #expect(model.entitlements[EntitlementCapabilityCatalog.iCloudContainersKey] == nil)
        #expect(model.entitlements[EntitlementCapabilityCatalog.iCloudKVStoreKey] == nil)
        #expect(model.entitlements[EntitlementCapabilityCatalog.ubiquitousContainersKey] == nil)
    }

    @Test("The App Store Sandbox preset sets its three keys")
    func presetSandbox() throws {
        let model = EntitlementsEditorModel()
        model.applyPreset(.appStoreSandbox)
        #expect(model.entitlements["com.apple.security.app-sandbox"] == .bool(true))
        #expect(model.entitlements["com.apple.security.files.user-selected.read-write"] == .bool(true))
        #expect(model.entitlements["com.apple.security.network.client"] == .bool(true))
    }

    @Test("Validation warns when App Sandbox is missing")
    func validationSandboxMissing() throws {
        let model = EntitlementsEditorModel()
        #expect(model.validate().contains { $0.rawKey == "com.apple.security.app-sandbox" && $0.severity == .warning })
        #expect(model.isValid)
    }

    @Test("Validation errors on a bad aps-environment value")
    func validationBadApsEnvironment() throws {
        let model = EntitlementsEditorModel()
        model.setString("staging", forKey: "aps-environment")
        let errors = model.errors
        #expect(errors.contains { $0.rawKey == "aps-environment" })
        #expect(!model.isValid)
    }

    @Test("Validation warns on network without sandbox")
    func validationNetworkWithoutSandbox() throws {
        let model = EntitlementsEditorModel()
        model.setBool(true, forKey: "com.apple.security.network.client")
        #expect(model.validate().contains { $0.message.contains("App Sandbox is inactive") })
    }

    @Test("Validation errors when App Groups is not an array of strings")
    func validationAppGroupsFormat() throws {
        let model = EntitlementsEditorModel()
        model.set(.array([.integer(1)]), forKey: "com.apple.security.application-groups")
        #expect(model.errors.contains { $0.rawKey == "com.apple.security.application-groups" })
        model.setStringArray(["group.com.example.app"], forKey: "com.apple.security.application-groups")
        #expect(model.errors.isEmpty)
    }

    @Test("Validation warns on redundant read-only + read-write pairs")
    func validationRedundantReadWrite() throws {
        let model = EntitlementsEditorModel()
        model.setBool(true, forKey: "com.apple.security.assets.downloads.read-only")
        model.setBool(true, forKey: "com.apple.security.assets.downloads.read-write")
        #expect(model.warnings.contains { $0.message.contains("redundant") })
    }

    @Test("Raw XML text round-trips, and bad XML throws")
    func rawXMLRoundTrip() throws {
        let model = try EntitlementsEditorModel(url: fixtures.appendingPathComponent("App.entitlements"))
        let xml = model.xmlText()
        #expect(xml.contains("com.apple.security.app-sandbox"))
        let other = EntitlementsEditorModel()
        try other.setXMLText(xml)
        #expect(other.entitlements == model.entitlements)
        #expect(throws: (any Error).self) {
            try other.setXMLText("<plist><string>not a dict</string></plist>")
        }
    }

    @Test("Keys no toggle manages are listed as uncovered")
    func uncoveredKeys() throws {
        let model = EntitlementsEditorModel()
        model.setString("custom", forKey: "com.example.custom-key")
        #expect(model.uncoveredKeys == ["com.example.custom-key"])
        model.searchText = "custom"
        #expect(model.uncoveredKeys == ["com.example.custom-key"])
        model.searchText = "zzz"
        #expect(model.uncoveredKeys.isEmpty)
    }

    @Test("Edits are recorded in the change history")
    func historyRecordsChanges() throws {
        let model = EntitlementsEditorModel()
        let sandbox = try #require(EntitlementCapabilityCatalog.definition(for: "com.apple.security.app-sandbox"))
        model.setCapability(sandbox, on: true)
        #expect(model.history.count == 1)
        #expect(model.history[0].rawKey == "com.apple.security.app-sandbox")
        #expect(model.history[0].oldValue == "(absent)")
        #expect(model.history[0].newValue == "true")
    }

    @Test("Save and revert restore the on-disk dictionary")
    func saveAndRevert() throws {
        let dir = tempDir()
        let url = dir.appendingPathComponent("Test.entitlements")
        let model = EntitlementsEditorModel()
        model.setBool(true, forKey: "com.apple.security.app-sandbox")
        try model.save(to: url)
        #expect(!model.isDirty)
        let reopened = try EntitlementsEditorModel(url: url)
        reopened.setBool(true, forKey: "com.apple.security.network.client")
        #expect(reopened.isDirty)
        try reopened.revert()
        #expect(reopened.entitlements["com.apple.security.network.client"] == nil)
        #expect(!reopened.isDirty)
    }

    @Test("Profile mismatches report restricted keys the profile lacks")
    func profileMismatch() throws {
        let model = try EntitlementsEditorModel(url: fixtures.appendingPathComponent("App.entitlements"))
        let profile = ProvisioningProfile(
            uuid: "00000000-0000-0000-0000-000000000000", name: "Test",
            teamIdentifiers: ["ABCDE12345"], platforms: ["iOS"],
            entitlements: ["com.apple.security.application-groups": .array([.string("group.com.example.app")])],
            certificateHashes: [])
        let mismatches = model.profileMismatches(profile: profile, platform: .device)
        #expect(mismatches.contains(.missing("com.apple.security.app-sandbox")))
        #expect(mismatches.contains(.missing("aps-environment")))
        #expect(!mismatches.contains(.missing("com.apple.security.application-groups")))
    }
}
