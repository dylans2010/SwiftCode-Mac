import SwiftUI

@MainActor
@Observable
final class SDKFirstLaunchInstallerModel {
    enum Phase: Equatable {
        case prompt
        case installing
        case succeeded(SDKInstaller.InstallResult)
        case failed(SDKInstaller.InstallResult)
    }

    private(set) var phase: Phase = .prompt
    private(set) var logLines: [SDKInstaller.LogLine] = []

    func startInstall() {
        switch phase {
        case .installing:
            return
        case .prompt, .succeeded, .failed:
            break
        }
        phase = .installing
        logLines = []

        Task { [weak self] in
            let result = await SDKInstaller.install { [weak self] line in
                Task { @MainActor [weak self] in
                    self?.append(line: line)
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if result.success {
                    SDKStudioFirstLaunchChoice.recordInstalled()
                    self.phase = .succeeded(result)
                } else {
                    self.phase = .failed(result)
                }
            }
        }
    }

    private func append(line: SDKInstaller.LogLine) {
        logLines.append(line)
        if logLines.count > 1000 {
            logLines.removeFirst(logLines.count - 1000)
        }
    }
}
