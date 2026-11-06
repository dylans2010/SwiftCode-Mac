// Ported from Legacy `SwiftCode/SDK/Studio/Views/SDKFirstLaunchInstallerView.swift` (Audit E §5 partial entry; H-E5).
// Types ported here: SDKFirstLaunchInstallerModel.
// Combine/@Published converted to @Observable.

import SwiftUI

/// View model driving the install sheet. All installer callbacks hop
/// back to the main actor before touching `@Published` state.
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
        // Bound the transcript; the full log is also in the result.
        if logLines.count > 1000 {
            logLines.removeFirst(logLines.count - 1000)
        }
    }
}
