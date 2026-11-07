import Foundation

public struct HostSetupOutput: Sendable, Equatable {
    public struct Step: Sendable, Equatable, Identifiable {
        public var id: String
        public var command: String
        public var needsRoot: Bool
    }

    public var mode = ""
    public var facts: [String: String] = [:]
    public var steps: [Step] = []
    public var checks: [RuntimeCheck] = []
    public var ran: [String: Bool] = [:]
    public var sve: [String: String]?
    public var passed: Bool?
    public var errors: [String] = []

    public init() {}

    public var rootSteps: [Step] { steps.filter(\.needsRoot) }
    public var userSteps: [Step] { steps.filter { !$0.needsRoot } }
    public var isSettled: Bool { steps.isEmpty }

    public static func parse(_ text: String) -> HostSetupOutput {
        var o = HostSetupOutput()
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            guard line.hasPrefix("SWIFTCODE-") else { continue }
            let body = line.dropFirst("SWIFTCODE-".count)
            let (kind, rest) = split(String(body))
            switch kind {
            case "SETUP":
                o.mode = keyValues(rest)["mode"] ?? ""
            case "FACT":
                if let eq = rest.firstIndex(of: "=") { o.facts[String(rest[..<eq])] = String(rest[rest.index(after: eq)...]) }
            case "ROOT", "USER":
                let (id, cmd) = split(rest)
                o.steps.append(Step(id: id, command: cmd, needsRoot: kind == "ROOT"))
            case "CHECK":
                let (id, r1) = split(rest)
                let (state, reason) = split(r1)
                o.checks.append(RuntimeCheck(id, title(of: id), SetupCheckState(rawValue: state) ?? .unknown, reason))
            case "RAN":
                let (id, status) = split(rest)
                o.ran[id] = status == "ok"
            case "SVE":
                o.sve = keyValues(rest)
            case "DONE":
                o.passed = rest == "pass"
            case "ERROR":
                o.errors.append(rest)
            default: break
            }
        }
        o.steps = o.rootSteps + o.userSteps
        return o
    }

    static func split(_ s: String) -> (String, String) {
        guard let sp = s.firstIndex(of: " ") else { return (s, "") }
        return (String(s[..<sp]), String(s[s.index(after: sp)...]))
    }

    static func keyValues(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for w in s.split(separator: " ") {
            guard let eq = w.firstIndex(of: "=") else { continue }
            out[String(w[..<eq])] = String(w[w.index(after: eq)...])
        }
        return out
    }

    public static func title(of id: String) -> String {
        switch id {
        case "setup.os": "Operating system"
        case "setup.arch": "Architecture"
        case "setup.kvm": "KVM access"
        case "setup.packages": "Packages"
        case "setup.swift": "Swift toolchain"
        case "setup.data": "Data folder"
        case "setup.service": "Simulator service"
        case "setup.simhost": "swiftcode-simhost"
        case "setup.firewall": "Firewall"
        case "setup.ports": "Link ports"
        case "setup.selftest": "Service self-test"
        case "setup.sve": "Kernel: KVM SVE fix"
        default: id
        }
    }

    public func checklist(destination: String, invocation: HostSetupInvocation) -> [RuntimeCheck] {
        var out = checks.map { c -> RuntimeCheck in
            var c = c
            guard c.state != .ok else { return c }
            let key = c.id.replacingOccurrences(of: "setup.", with: "")
            let related: [String: [String]] = ["kvm": ["kvm-group"], "packages": ["packages"], "swift": ["swift"],
                                               "data": ["data-dir", "data-owner", "data-folders"], "service": ["service-config", "service-unit", "launcher"],
                                               "simhost": ["release"], "selftest": ["release", "launcher", "service-config"], "firewall": ["firewall"]]
            let ids = related[key] ?? []
            if steps.contains(where: { ids.contains($0.id) && $0.needsRoot }) {
                c.fix = .command(invocation.rootCommand(destination: destination))
            } else if steps.contains(where: { ids.contains($0.id) }) {
                c.fix = .action(.provisionApply)
            }
            return c
        }
        if let sve { out.append(KVMSVEProbe.check(KVMSVEProbe.Facts(sve))) }
        return out
    }
}

public struct HostSetupInvocation: Sendable, Equatable {
    public var dataDirectory: String
    public var configDirectory = ""
    public var swiftVersion = "6.4"
    public var probeSeconds = 3
    public var remotePath = "~/.cache/swiftcode/swiftcode-host-setup"

    public var swiftcodeVersion = ""
    public var tcpPort = 47800
    public var udpPort = 47801

    public init(dataDirectory: String, configDirectory: String = "", swiftVersion: String = "6.4", probeSeconds: Int = 3, swiftcodeVersion: String = "",
                tcpPort: Int = 47800, udpPort: Int = 47801) {
        self.dataDirectory = dataDirectory
        self.configDirectory = configDirectory
        self.swiftVersion = swiftVersion
        self.probeSeconds = probeSeconds
        self.swiftcodeVersion = swiftcodeVersion
        self.tcpPort = tcpPort
        self.udpPort = udpPort
    }

    public func arguments(mode: String) -> [String] {
        var a = ["--" + mode, "--data-dir", dataDirectory, "--swift", swiftVersion, "--probe-seconds", String(probeSeconds)]
        if !configDirectory.isEmpty { a += ["--config-dir", configDirectory] }
        if !swiftcodeVersion.isEmpty { a += ["--swiftcode-version", swiftcodeVersion] }
        if tcpPort != 47800 || udpPort != 47801 { a += ["--tcp-port", String(tcpPort), "--udp-port", String(udpPort)] }
        return a
    }

    public func streamedCommand(mode: String) -> String {
        "bash -s -- " + arguments(mode: mode).map(\.shellQuoted).joined(separator: " ")
    }

    public var saveCommand: String {
        "mkdir -p ~/.cache/swiftcode && cat > \(remotePath) && chmod 0700 \(remotePath)"
    }

    public func rootCommand(destination: String) -> String {
        "ssh -t \(destination.shellQuoted) " + ("sudo bash \(remotePath) " + arguments(mode: "root").map(\.shellQuoted).joined(separator: " ")).shellQuoted
    }
}

public enum KVMSVEProbe {
    public static let postmortem = "https://github.com/dylans2010/SwiftCode-Mac/blob/main/docs/postmortem-kvm-sve.md"
    public static let minimumRuns: UInt64 = 100_000

    public struct Facts: Sendable, Equatable {
        public var architecture: String
        public var hasSVE: Bool
        public var kvm: String
        public var kernel: String
        public var runs: UInt64?
        public var lost: UInt64?
        public var error: String?

        public init(architecture: String, hasSVE: Bool, kvm: String, kernel: String = "", runs: UInt64? = nil, lost: UInt64? = nil, error: String? = nil) {
            self.architecture = architecture
            self.hasSVE = hasSVE
            self.kvm = kvm
            self.kernel = kernel
            self.runs = runs
            self.lost = lost
            self.error = error
        }

        public init(_ kv: [String: String]) {
            self.init(architecture: kv["arch"] ?? "", hasSVE: kv["sve"] == "yes", kvm: kv["kvm"] ?? "", kernel: kv["kernel"] ?? "",
                      runs: kv["runs"].flatMap { UInt64($0) }, lost: kv["lost"].flatMap { UInt64($0) }, error: kv["error"])
        }
    }

    public enum Verdict: Sendable, Equatable {
        case notApplicable(String)
        case fixed(runs: UInt64)
        case affected(lost: UInt64, runs: UInt64)
        case unknown(String)
    }

    public static func verdict(_ f: Facts) -> Verdict {
        if !["aarch64", "arm64"].contains(f.architecture) {
            return .notApplicable("This host is \(f.architecture.isEmpty ? "not arm64" : f.architecture); the bug is in KVM on arm64 with SVE.")
        }
        if !f.hasSVE || f.error == "no-sve" { return .notApplicable("This CPU has no SVE, so its predicate registers cannot be lost.") }
        if let lost = f.lost, let runs = f.runs {
            if lost > 0 { return .affected(lost: lost, runs: runs) }
            if runs >= minimumRuns { return .fixed(runs: runs) }
            return .unknown("The probe ran only \(runs) times; that is too few to tell.")
        }
        switch f.error ?? "" {
        case "no-kvm-access": return .unknown("The probe needs /dev/kvm; fix KVM access first.")
        case "no-compiler": return .unknown("The probe needs a C compiler (cc or the Swift toolchain's clang).")
        case "skipped": return .unknown("The probe was skipped.")
        case "": return .unknown("The probe gave no result.")
        case let e: return .unknown("The probe failed (\(e)).")
        }
    }

    public static func check(_ f: Facts) -> RuntimeCheck {
        let title = HostSetupOutput.title(of: "setup.sve")
        let kernel = f.kernel.isEmpty ? "" : " Kernel \(f.kernel)."
        switch verdict(f) {
        case .notApplicable(let why):
            return RuntimeCheck("setup.sve", title, .notApplicable, why)
        case .fixed(let runs):
            return RuntimeCheck("setup.sve", title, .ok, "No SVE state was lost in \(runs) KVM runs: the kernel has the fix.\(kernel)")
        case .affected(let lost, let runs):
            return RuntimeCheck("setup.sve", title, .missing,
                                "The kernel lost the SVE predicate registers in \(lost) of \(runs) KVM runs. Without the upstream fix (commit fbc7e61195e2), copies made by the simulator's threads can silently not happen. SwiftCode's built-in mitigations are on, so the simulator still runs correctly; a fixed kernel removes the risk.\(kernel)",
                                fix: .instructions("How to get a kernel with the fix: \(postmortem)"))
        case .unknown(let why):
            return RuntimeCheck("setup.sve", title, .unknown, why + kernel + " SwiftCode's mitigations are on either way.")
        }
    }
}
