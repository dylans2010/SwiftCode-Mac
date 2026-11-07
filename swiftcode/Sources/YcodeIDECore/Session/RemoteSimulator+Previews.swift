import Foundation
import YcodePreviews
import YcodeSubprocess

extension RemoteSimulator {
    public static let previewDeviceSuffix = "-previews"

    public var previewDevice: RemoteSimulator {
        var r = self
        if var t = r.target {
            t.deviceDirectoryName += Self.previewDeviceSuffix
            r.target = t
        } else {
            r.settings.deviceName += Self.previewDeviceSuffix
        }
        let name = r.target?.deviceDirectoryName ?? r.settings.deviceName
        r.displaySocketName = "pv-" + String(UInt64(bitPattern: Int64(PreviewInputs.hash(name))) % 0xffff_ffff, radix: 16) + ".sock"
        return r
    }

    public var previewDirectory: String { "\(remoteDevicePath)/\(YcodePreviews.PreviewHost.deviceRelativeDirectory)" }

    public func remotePreviewHostPath(platform: PreviewPlatform) -> String {
        "\(settings.dataDirectory)/apps/previews-\(platform.rawValue)/\(YcodePreviews.PreviewHost.appName)"
    }

    public func previewCommand(platform: PreviewPlatform) -> String {
        let q = Self.quote
        let lean = leanBootVariables
        return "mkdir -p \(q("\(settings.dataDirectory)/display")) \(q(previewDirectory)); rm -f \(q(previewDirectory))/payload-*.dylib \(q(previewDirectory))/plan.json; "
            + ": > \(q(previewDirectory + "/host.log")); echo SWIFTCODE-REMOTE-PID $$; exec env SWIFTCODE_WARM_BOOT=1 \(lean)\(q(settings.simdPath))"
            + " --device \(q(remoteDevicePath)) --runtime-root \(q(runtimeRoot))"
            + (target?.deviceTypeArguments ?? []).map { " " + q($0) }.joined()
            + " --install-app \(q(remotePreviewHostPath(platform: platform))) --launch \(q(YcodePreviews.PreviewHost.bundleIdentifier))"
            + displayServerArguments.map { " " + q($0) }.joined()
            + Self.words(settings.additionalArguments).map { " " + q($0) }.joined()
            + cameraArguments.map { " " + q($0) }.joined()
    }

    public var previewReportCommand: String {
        let f = Self.quote(previewDirectory + "/host.log")
        return "mkdir -p \(Self.quote(previewDirectory)) && touch \(f) && exec tail -n 0 -F \(f)"
    }

    public func previewDeliverCommand(payloadName: String?, plan: Data, keep: Int) -> String {
        let q = Self.quote
        let d = q(previewDirectory)
        var c = "mkdir -p \(d) && cd \(d) && "
        if let p = payloadName { c += "cat > \(q(p + ".part")) && mv \(q(p + ".part")) \(q(p)) && " }
        c += "printf '%s' \(q(String(decoding: plan, as: UTF8.self))) > plan.json.part && mv plan.json.part plan.json"
        c += " && (ls -t payload-*.dylib 2>/dev/null | tail -n +\(keep + 1) | xargs -r rm -f)"
        return c
    }
}
