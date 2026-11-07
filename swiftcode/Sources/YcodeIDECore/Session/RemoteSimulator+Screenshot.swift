import Foundation

extension RemoteSimulator {
    public func screenshotCommand(display: String = "active", token: String = UUID().uuidString) -> String {
        let q = Self.quote
        let dir = "\(settings.dataDirectory)/shots"
        let file = "\(dir)/agent-\(token).png"
        let control = controlCommand(["screenshot", display, file])
        return "mkdir -p \(q(dir)) && \(control.hasPrefix("exec ") ? String(control.dropFirst(5)) : control) >&2"
            + " && cat \(q(file)); s=$?; rm -f \(q(file)); exit $s"
    }

    public func screenshot(display: String = "active") -> Result<Data, RemoteRunFailure> {
        let (status, data) = runLocalData(settings.ssh, sshArguments(screenshotCommand(display: display)), errors: false)
        guard status == 0, data.starts(with: [0x89, 0x50, 0x4E, 0x47]) else {
            return .failure(RemoteRunFailure(description: status == 0
                ? "the device sent no picture"
                : "no picture (ssh status \(status)); is the device running? Boot it or launch an app first"))
        }
        return .success(data)
    }
}
