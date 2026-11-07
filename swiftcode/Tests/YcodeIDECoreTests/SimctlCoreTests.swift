import Foundation
import Testing
import YcodeIDECore
import YcodePreviews

@Suite struct SimctlCoreTests {
    @Test func decodesSimctlListResponse() throws {
        let json = """
        {
          "runtimes": [
            {
              "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-2",
              "name": "iOS 18.2",
              "version": "18.2",
              "buildversion": "22C146",
              "platform": "iOS",
              "isAvailable": true
            }
          ],
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-2": [
              {
                "udid": "A1B2C3D4-1111-2222-3333-444455556666",
                "name": "iPhone 16 Pro",
                "state": "Booted",
                "isAvailable": true
              }
            ]
          },
          "devicetypes": [
            {
              "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro",
              "name": "iPhone 16 Pro",
              "productFamily": "iPhone"
            }
          ]
        }
        """
        let response = try JSONDecoder().decode(SimctlListResponse.self, from: Data(json.utf8))
        #expect(response.runtimes?.count == 1)
        #expect(response.runtimes?.first?.name == "iOS 18.2")
        let devices = response.devices?["com.apple.CoreSimulator.SimRuntime.iOS-18-2"]
        #expect(devices?.count == 1)
        #expect(devices?.first?.name == "iPhone 16 Pro")
        #expect(devices?.first?.state == "Booted")
        #expect(devices?.first?.isAvailable == true)
    }

    @Test func simulatorStateIsRunning() {
        #expect(SimulatorState.booted.isRunning)
        #expect(SimulatorState.booting.isRunning)
        #expect(SimulatorState.ready.isRunning)
        #expect(!SimulatorState.shutdown.isRunning)
        #expect(!SimulatorState.failed.isRunning)
        #expect(!SimulatorState.unknown.isRunning)
    }

    @Test func snapshotFindsOrphanedDevices() {
        let runtime = SimulatorRuntime(
            identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-2",
            name: "iOS 18.2",
            version: "18.2",
            platform: "iOS"
        )
        let matched = SimulatorDevice(
            udid: "11111111-1111-1111-1111-111111111111",
            name: "iPhone 16 Pro",
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-2",
            platform: "iOS",
            osVersion: "18.2",
            architecture: "arm64",
            state: .booted
        )
        let orphaned = SimulatorDevice(
            udid: "22222222-2222-2222-2222-222222222222",
            name: "iPhone 15",
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-5",
            platform: "iOS",
            osVersion: "17.5",
            architecture: "arm64",
            state: .shutdown
        )
        let snapshot = SimulatorSnapshot(
            runtimes: [runtime],
            devices: [matched, orphaned],
            bootedDeviceIDs: ["11111111-1111-1111-1111-111111111111"],
            generatedAt: Date(),
            discoveryDuration: .seconds(1)
        )
        #expect(snapshot.orphanedDevices.count == 1)
        #expect(snapshot.orphanedDevices.first?.udid == "22222222-2222-2222-2222-222222222222")
    }

    @Test func previewSandboxPolicyBlocksSystemPaths() {
        let project = URL(fileURLWithPath: "/tmp/SwiftCodeTestProject")
        let policy = PreviewSandbox().makePolicy(projectDirectory: project)
        #expect(policy.projectDirectory == project)
        #expect(policy.allowNetwork == false)
        #expect(policy.blockedPaths.contains("/System"))
        #expect(policy.blockedPaths.contains("/private"))
    }

    @Test func simulatorRebootCommandConstruction() {
        let cmd = SimulatorCommand.reboot(udid: "A1B2C3D4-5678-90AB-CDEF-1234567890AB")
        #expect(cmd.arguments == ["simctl", "reboot", "A1B2C3D4-5678-90AB-CDEF-1234567890AB"])
        #expect(cmd.executable == "/usr/bin/xcrun")
    }

    @Test func simulatorNotifyPostCommandConstruction() {
        let cmd = SimulatorCommand.notifyPost(udid: "A1B2C3D4-5678-90AB-CDEF-1234567890AB", notification: "com.apple.UIKit.SimulatorPreferences.ShakeDevice")
        #expect(cmd.arguments == ["simctl", "notify_post", "A1B2C3D4-5678-90AB-CDEF-1234567890AB", "com.apple.UIKit.SimulatorPreferences.ShakeDevice"])
    }
}

