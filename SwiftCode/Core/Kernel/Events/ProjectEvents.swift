import Foundation

/// Event triggered when a project is opened.
public struct ProjectOpenedEvent: KernelEvent {
    public let timestamp = Date()
    public let projectName: String
}

/// Event triggered when a file is saved.
public struct FileSavedEvent: KernelEvent {
    public let timestamp = Date()
    public let filePath: String
}
