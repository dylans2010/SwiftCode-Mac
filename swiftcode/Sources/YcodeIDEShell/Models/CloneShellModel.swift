import Foundation
import YcodeSubprocess
import Observation
import YcodeIDECore

public struct ShellNotice: Equatable, Sendable {
    public var title: String
    public var message: String
    public init(_ title: String, _ message: String) {
        self.title = title
        self.message = message
    }
}

@MainActor
@Observable
public final class CloneShellModel {
    public var address = ""
    public var location: String
    public var isFolderDialogShown = false
    public private(set) var isRunning = false
    public private(set) var error: String?

    @ObservationIgnored var git: String
    @ObservationIgnored var finished: (URL) -> Void = { _ in }

    public init(location: String? = nil, git: String = HostTool.path("git")) {
        self.git = git
        let home = FileManager.default.homeDirectoryForCurrentUser
        let developer = home.appendingPathComponent("Developer")
        self.location = location ?? (FileManager.default.fileExists(atPath: developer.path) ? developer : home).path
    }

    public var trimmedAddress: String { address.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var canClone: Bool { !trimmedAddress.isEmpty && !location.isEmpty && !isRunning }
    public var destination: URL {
        URL(fileURLWithPath: (location as NSString).expandingTildeInPath).appendingPathComponent(GitRepository.cloneFolderName(for: trimmedAddress))
    }

    @discardableResult
    public func clone() -> Task<Void, Never> {
        guard canClone else { return Task {} }
        guard FileManager.default.isExecutableFile(atPath: git) else {
            error = "Git was not found at \(git). Install git, then try again."
            return Task {}
        }
        error = nil
        isRunning = true
        let address = trimmedAddress, destination = destination, git = git
        return Task { [weak self] in
            let failure: String? = await Task.detached {
                do { try GitRepository.clone(address, into: destination, git: git); return nil } catch { return error.localizedDescription }
            }.value
            guard let self else { return }
            self.isRunning = false
            if let failure { self.error = failure } else { self.finished(destination) }
        }
    }
}

extension ShellAppModel {
    public func showClone() {
        let m = CloneShellModel()
        m.finished = { [weak self] folder in self?.cloneFinished(folder) }
        clone = m
    }

    public func cancelClone() { clone = nil }

    func cloneFinished(_ folder: URL) {
        clone = nil
        if let w = Self.workspace(in: folder) {
            open(path: w.path)
        } else {
            notice = ShellNotice("Cloned \(folder.lastPathComponent)", "The repository is in \(folder.path). It has no project, workspace or Package.swift at its top level to open.")
        }
    }

    static func workspace(in dir: URL) -> URL? {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
        if let w = names.first(where: { $0.hasSuffix(".xcworkspace") }) { return dir.appendingPathComponent(w) }
        if let p = names.first(where: { $0.hasSuffix(".xcodeproj") }) { return dir.appendingPathComponent(p) }
        return names.contains("Package.swift") ? dir : nil
    }

    public func openLink(_ url: URL) { openExternally(url) }

    public func linkCouldNotOpen(_ url: URL) {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.query = nil
        notice = ShellNotice("Open This Address in a Browser", "No web browser could be opened. The address is \(c?.string ?? url.absoluteString)")
    }

    public func explainSimulator() {
        notice = ShellNotice("SwiftCode Simulator (\(ExperimentalNotice.label))", "\(ExperimentalNotice.simulator) Pair a host with `swiftcode sim remote pair`; its devices then show as run destinations.")
    }
}
