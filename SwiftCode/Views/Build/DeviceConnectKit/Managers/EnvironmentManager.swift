import Foundation
import Observation

@Observable
@MainActor
public final class EnvironmentManager {
    public static let shared = EnvironmentManager()

    public private(set) var currentEnvironment: DeviceEnvironment = DeviceEnvironment()
    public private(set) var diagnostics: [String] = []
    public private(set) var isValidating = false
    public private(set) var isDerivedDataClearing = false
    public private(set) var derivedDataSize: Double = 0

    private init() {}

    public func validateEnvironment() async {
        isValidating = true
        let result = await DeviceConnectEngine.shared.validate()
        self.currentEnvironment = result.environment
        self.diagnostics = result.diagnostics

        // Update derived data size
        do {
            self.derivedDataSize = try await DerivedDataCommand().getDerivedDataSize()
        } catch {
            self.derivedDataSize = 0
        }

        isValidating = false
    }

    public func clearDerivedData() async {
        isDerivedDataClearing = true
        do {
            _ = try await DerivedDataCommand().clearDerivedData()
            self.derivedDataSize = 0
        } catch {}
        isDerivedDataClearing = false
    }
}
