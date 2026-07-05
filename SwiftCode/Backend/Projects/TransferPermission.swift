import Foundation

public struct TransferPermission: Codable, Hashable {
    public enum AccessPreset: String, Codable, CaseIterable, Identifiable {
        case readOnly = "read-only"
        case limitedEdit = "limited-edit"
        case fullAccess = "full-access"
        case custom

        public var id: String { rawValue }
    }

    public struct FileSystemPermissions: Codable, Hashable {
        var viewFiles: Bool
        var editFiles: Bool
        var createFiles: Bool
        var deleteFiles: Bool
        var renameFiles: Bool
        var moveFiles: Bool
        var bulkOperations: Bool
    }

    public struct ProjectManagementPermissions: Codable, Hashable {
        var modifyProjectSettings: Bool
        var renameProject: Bool
        var editMetadata: Bool
        var manageDependencies: Bool
        var editEnvironmentConfigs: Bool
    }

    public struct VersionControlPermissions: Codable, Hashable {
        var enableDisableGit: Bool
        var commit: Bool
        var push: Bool
        var pull: Bool
        var branchCreateDelete: Bool
        var merge: Bool
        var revert: Bool
    }

    public struct ExecutionPermissions: Codable, Hashable {
        var buildProject: Bool
        var runProject: Bool
        var executeScripts: Bool
        var terminalAccess: Bool
        var backgroundProcesses: Bool
    }

    public struct PluginPermissions: Codable, Hashable {
        var installPlugins: Bool
        var removePlugins: Bool
        var runPlugins: Bool
        var allowPluginFileModification: Bool
    }

    public struct AgentPermissions: Codable, Hashable {
        var allowAgentAccess: Bool
        var allowAgentFileModification: Bool
        var allowAgentCodeGeneration: Bool
        var allowAgentProjectRefactoring: Bool
        var allowAgentToRunCommands: Bool
        var allowAgentToInitiateTransfers: Bool
    }

    public struct TransferControlPermissions: Codable, Hashable {
        var allowRetransfer: Bool
        var allowExternalSharing: Bool
        var restrictToOriginalSender: Bool
        var expirationDate: Date?
        var oneTimeAccessMode: Bool
    }

    public struct SecurityRestrictions: Codable, Hashable {
        var restrictedSensitivePaths: [String]
        var readOnlyZones: [String]
        var blockedExecutionExtensions: [String]
        var encryptionRequired: Bool
        var hiddenFiles: Bool
        var encryptedStorage: Bool
    }

    public struct AuditConfiguration: Codable, Hashable {
        var logAllActions: Bool
        var trackEdits: Bool
        var trackDeletions: Bool
        var trackExecutions: Bool
        var allowAuditReview: Bool
    }

    public enum Scope: String, Codable, CaseIterable {
        case isCollaborative
        case viewFiles
        case editFiles
        case createFiles
        case deleteFiles
        case renameFiles
        case moveFiles
        case bulkOperations
        case modifyProjectSettings
        case renameProject
        case editMetadata
        case manageDependencies
        case editEnvironmentConfigs
        case enableDisableGit
        case commit
        case push
        case pull
        case branchCreateDelete
        case merge
        case revert
        case buildProject
        case runProject
        case executeScripts
        case terminalAccess
        case backgroundProcesses
        case installPlugins
        case removePlugins
        case runPlugins
        case allowPluginFileModification
        case allowAgentAccess
        case allowAgentFileModification
        case allowAgentCodeGeneration
        case allowAgentProjectRefactoring
        case allowAgentToRunCommands
        case allowAgentToInitiateTransfers
        case allowRetransfer
        case allowExternalSharing
        case restrictToOriginalSender
        case oneTimeAccessMode
        case encryptionRequired
        case logAllActions
        case trackEdits
        case trackDeletions
        case trackExecutions
        case allowAuditReview
    }

    var isCollaborative: Bool
    var preset: AccessPreset
    var fileSystem: FileSystemPermissions
    var projectManagement: ProjectManagementPermissions
    var versionControl: VersionControlPermissions
    var execution: ExecutionPermissions
    var plugin: PluginPermissions
    var agent: AgentPermissions
    var transferControl: TransferControlPermissions
    var security: SecurityRestrictions
    var audit: AuditConfiguration

    static func makePreset(_ preset: AccessPreset) -> TransferPermission {
        switch preset {
        case .readOnly:
            return TransferPermission(
                isCollaborative: false,
                preset: preset,
                fileSystem: .init(viewFiles: true, editFiles: false, createFiles: false, deleteFiles: false, renameFiles: false, moveFiles: false, bulkOperations: false),
                projectManagement: .init(modifyProjectSettings: false, renameProject: false, editMetadata: false, manageDependencies: false, editEnvironmentConfigs: false),
                versionControl: .init(enableDisableGit: false, commit: false, push: false, pull: false, branchCreateDelete: false, merge: false, revert: false),
                execution: .init(buildProject: false, runProject: false, executeScripts: false, terminalAccess: false, backgroundProcesses: false),
                plugin: .init(installPlugins: false, removePlugins: false, runPlugins: false, allowPluginFileModification: false),
                agent: .init(allowAgentAccess: true, allowAgentFileModification: false, allowAgentCodeGeneration: false, allowAgentProjectRefactoring: false, allowAgentToRunCommands: false, allowAgentToInitiateTransfers: false),
                transferControl: .init(allowRetransfer: false, allowExternalSharing: false, restrictToOriginalSender: true, expirationDate: nil, oneTimeAccessMode: false),
                security: .init(restrictedSensitivePaths: [], readOnlyZones: [], blockedExecutionExtensions: ["sh", "command", "zsh"], encryptionRequired: true, hiddenFiles: true, encryptedStorage: false),
                audit: .init(logAllActions: true, trackEdits: true, trackDeletions: true, trackExecutions: true, allowAuditReview: true)
            )
        case .limitedEdit:
            var permission = makePreset(.readOnly)
            permission.preset = preset
            permission.fileSystem.editFiles = true
            permission.fileSystem.createFiles = true
            permission.fileSystem.renameFiles = true
            permission.projectManagement.editMetadata = true
            permission.versionControl.commit = true
            permission.execution.buildProject = true
            permission.execution.runProject = true
            permission.plugin.runPlugins = true
            permission.agent.allowAgentFileModification = true
            permission.agent.allowAgentCodeGeneration = true
            return permission
        case .fullAccess:
            return TransferPermission(
                isCollaborative: true,
                preset: preset,
                fileSystem: .init(viewFiles: true, editFiles: true, createFiles: true, deleteFiles: true, renameFiles: true, moveFiles: true, bulkOperations: true),
                projectManagement: .init(modifyProjectSettings: true, renameProject: true, editMetadata: true, manageDependencies: true, editEnvironmentConfigs: true),
                versionControl: .init(enableDisableGit: true, commit: true, push: true, pull: true, branchCreateDelete: true, merge: true, revert: true),
                execution: .init(buildProject: true, runProject: true, executeScripts: true, terminalAccess: true, backgroundProcesses: true),
                plugin: .init(installPlugins: true, removePlugins: true, runPlugins: true, allowPluginFileModification: true),
                agent: .init(allowAgentAccess: true, allowAgentFileModification: true, allowAgentCodeGeneration: true, allowAgentProjectRefactoring: true, allowAgentToRunCommands: true, allowAgentToInitiateTransfers: true),
                transferControl: .init(allowRetransfer: true, allowExternalSharing: true, restrictToOriginalSender: false, expirationDate: nil, oneTimeAccessMode: false),
                security: .init(restrictedSensitivePaths: [], readOnlyZones: [], blockedExecutionExtensions: [], encryptionRequired: true, hiddenFiles: false, encryptedStorage: true),
                audit: .init(logAllActions: true, trackEdits: true, trackDeletions: true, trackExecutions: true, allowAuditReview: true)
            )
        case .custom:
            return makePreset(.limitedEdit)
        }
    }

    static let owner = makePreset(.fullAccess)

    var isExpired: Bool {
        if let expirationDate = transferControl.expirationDate {
            return expirationDate < Date()
        }
        return false
    }

    func allows(_ scope: Scope, path: String? = nil) -> Bool {
        guard !isExpired else { return false }
        if let path, isRestricted(path: path, for: scope) {
            return false
        }
        switch scope {
        case .isCollaborative: return isCollaborative
        case .viewFiles: return fileSystem.viewFiles
        case .editFiles: return fileSystem.editFiles
        case .createFiles: return fileSystem.createFiles
        case .deleteFiles: return fileSystem.deleteFiles
        case .renameFiles: return fileSystem.renameFiles
        case .moveFiles: return fileSystem.moveFiles
        case .bulkOperations: return fileSystem.bulkOperations
        case .modifyProjectSettings: return projectManagement.modifyProjectSettings
        case .renameProject: return projectManagement.renameProject
        case .editMetadata: return projectManagement.editMetadata
        case .manageDependencies: return projectManagement.manageDependencies
        case .editEnvironmentConfigs: return projectManagement.editEnvironmentConfigs
        case .enableDisableGit: return versionControl.enableDisableGit
        case .commit: return versionControl.commit
        case .push: return versionControl.push
        case .pull: return versionControl.pull
        case .branchCreateDelete: return versionControl.branchCreateDelete
        case .merge: return versionControl.merge
        case .revert: return versionControl.revert
        case .buildProject: return execution.buildProject
        case .runProject: return execution.runProject
        case .executeScripts: return execution.executeScripts && !isBlockedExecutable(path: path)
        case .terminalAccess: return execution.terminalAccess
        case .backgroundProcesses: return execution.backgroundProcesses
        case .installPlugins: return plugin.installPlugins
        case .removePlugins: return plugin.removePlugins
        case .runPlugins: return plugin.runPlugins
        case .allowPluginFileModification: return plugin.allowPluginFileModification
        case .allowAgentAccess: return agent.allowAgentAccess
        case .allowAgentFileModification: return agent.allowAgentFileModification
        case .allowAgentCodeGeneration: return agent.allowAgentCodeGeneration
        case .allowAgentProjectRefactoring: return agent.allowAgentProjectRefactoring
        case .allowAgentToRunCommands: return agent.allowAgentToRunCommands
        case .allowAgentToInitiateTransfers: return agent.allowAgentToInitiateTransfers
        case .allowRetransfer: return transferControl.allowRetransfer
        case .allowExternalSharing: return transferControl.allowExternalSharing
        case .restrictToOriginalSender: return transferControl.restrictToOriginalSender
        case .oneTimeAccessMode: return transferControl.oneTimeAccessMode
        case .encryptionRequired: return security.encryptionRequired
        case .logAllActions: return audit.logAllActions
        case .trackEdits: return audit.trackEdits
        case .trackDeletions: return audit.trackDeletions
        case .trackExecutions: return audit.trackExecutions
        case .allowAuditReview: return audit.allowAuditReview
        }
    }

    func isRestricted(path: String, for scope: Scope) -> Bool {
        if security.restrictedSensitivePaths.contains(where: { path.hasPrefix($0) }) { return true }
        if [.editFiles, .createFiles, .deleteFiles, .renameFiles, .moveFiles, .bulkOperations, .allowAgentFileModification].contains(scope),
           security.readOnlyZones.contains(where: { path.hasPrefix($0) }) {
            return true
        }
        if security.hiddenFiles && path.hasPrefix(".") { return true }
        return false
    }

    func isBlockedExecutable(path: String?) -> Bool {
        guard let path else { return false }
        return security.blockedExecutionExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }
}
