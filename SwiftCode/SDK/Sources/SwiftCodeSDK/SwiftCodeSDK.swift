import Foundation
@_exported import DiagnosticsKit
@_exported import WorkspaceKit
@_exported import ProjectKit
@_exported import BuildKit
@_exported import SourceControlKit
@_exported import ExtensionKit

public final class SwiftCodeSDKCoordinator: Sendable {
    public let configuration: SDKConfiguration
    public let projectInspector: ProjectInspector
    public let projectGenerator: ProjectGenerator
    public let projectValidator: ProjectValidator
    public let buildService: BuildService
    public let sourceControl: SourceControlService
    public let extensionValidator: ExtensionValidator
    public let extensionPackager: ExtensionPackager
    public let doctor: SDKDoctor

    public init(configuration: SDKConfiguration = .standard()) {
        self.configuration = configuration
        self.projectInspector = ProjectInspector()
        self.projectGenerator = ProjectGenerator()
        self.projectValidator = ProjectValidator()
        self.buildService = BuildService()
        self.sourceControl = SourceControlService()
        self.extensionValidator = ExtensionValidator()
        self.extensionPackager = ExtensionPackager()
        self.doctor = SDKDoctor()
    }
}
