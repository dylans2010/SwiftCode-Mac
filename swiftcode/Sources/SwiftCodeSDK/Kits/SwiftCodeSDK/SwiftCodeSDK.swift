import Foundation

public final class SwiftCodeSDKCoordinator: Sendable {
    public let configuration: SDKConfiguration
    public let projectInspector: ProjectInspector
    public let projectGenerator: ProjectGenerator
    public let projectValidator: ProjectValidator
    public let buildService: BuildService
    public let sourceControl: SourceControlService
    public let extensionValidator: SDKManifestValidator
    public let extensionPackager: ExtensionPackager
    public let doctor: SDKDoctor

    public init(configuration: SDKConfiguration = .standard()) {
        self.configuration = configuration
        self.projectInspector = ProjectInspector()
        self.projectGenerator = ProjectGenerator()
        self.projectValidator = ProjectValidator()
        self.buildService = BuildService()
        self.sourceControl = SourceControlService()
        self.extensionValidator = SDKManifestValidator()
        self.extensionPackager = ExtensionPackager()
        self.doctor = SDKDoctor()
    }
}
