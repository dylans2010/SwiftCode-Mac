import SwiftUI
import YcodeUI
import os.log
#if canImport(CoreVideo)
import CoreVideo
#endif

#if canImport(CoreVideo)
private func fpsDisplayLinkCallback(
    _ displayLink: CVDisplayLink,
    _ inNow: UnsafePointer<CVTimeStamp>,
    _ inOutputTime: UnsafePointer<CVTimeStamp>,
    _ flagsIn: CVOptionFlags,
    _ flagsOut: UnsafeMutablePointer<CVOptionFlags>,
    _ context: UnsafeMutableRawPointer?
) -> CVReturn {
    guard let context else { return kCVReturnSuccess }
    let viewModel = Unmanaged<FPSMonitorViewModel>.fromOpaque(context).takeUnretainedValue()
    let outputTime = inOutputTime.pointee
    guard outputTime.videoTimeScale > 0 else { return kCVReturnSuccess }
    let seconds = Double(outputTime.videoTime) / Double(outputTime.videoTimeScale)
    Task { @MainActor in viewModel.recordFrame(timestampSeconds: seconds) }
    return kCVReturnSuccess
}
#endif

@Observable
@MainActor
final class FPSMonitorViewModel {
    var fps: Double?
    var frameDurationMs: Double?
    var nominalRefreshHz: Double?
    var displayID: UInt32?
    var sampleCount: Int = 0
    var unavailableReason: String?

    private var lastTimestampSeconds: Double?
    private var recentIntervals: [Double] = []
    #if canImport(CoreVideo)
    private var displayLink: CVDisplayLink?
    #endif

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "FPSMonitor")

    deinit {
        #if canImport(CoreVideo)
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        #endif
    }

    func start() {
        #if canImport(CoreVideo)
        guard displayLink == nil else { return }
        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess, let link else {
            unavailableReason = "Could not create a display link for the active display."
            return
        }
        displayLink = link
        let context = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, fpsDisplayLinkCallback, context)
        let period = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link)
        if period.timeScale > 0, period.timeValue > 0 {
            nominalRefreshHz = Double(period.timeScale) / Double(period.timeValue)
        }
        displayID = CVDisplayLinkGetCurrentCGDisplay(link)
        guard CVDisplayLinkStart(link) == kCVReturnSuccess else {
            unavailableReason = "Display link could not be started."
            displayLink = nil
            return
        }
        logger.info("Started CVDisplayLink frame measurement")
        #else
        unavailableReason = "Live frame measurement needs CVDisplayLink, which is macOS-only."
        #endif
    }

    func stop() {
        #if canImport(CoreVideo)
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
        #endif
    }

    func recordFrame(timestampSeconds: Double) {
        defer { lastTimestampSeconds = timestampSeconds }
        guard let last = lastTimestampSeconds else { return }
        let interval = timestampSeconds - last
        guard interval > 0, interval <= 1 else { return }
        recentIntervals.append(interval)
        if recentIntervals.count > 30 {
            recentIntervals.removeFirst(recentIntervals.count - 30)
        }
        sampleCount += 1
        let mean = recentIntervals.reduce(0, +) / Double(recentIntervals.count)
        guard mean > 0 else { return }
        fps = 1 / mean
        frameDurationMs = mean * 1000
    }
}

struct FPSMonitorDevToolView: View {
    @State private var viewModel = FPSMonitorViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Monitor visual drawing frame-rate performance for custom animations and layout loops.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    Text("Current Screen Frame Rate")
                        .font(.headline)

                    Text(viewModel.fps.map { "\(String(format: "%.1f", $0)) FPS" } ?? "— FPS")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.green)

                    Text(viewModel.frameDurationMs.map { "Frame Duration: \(String(format: "%.2f", $0)) ms" } ?? "Waiting for frames…")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)

                    if let reason = viewModel.unavailableReason {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .liquidGlass(style: .standard, cornerRadius: 12)

                Divider()

                LabeledContent("Nominal Refresh Rate", value: viewModel.nominalRefreshHz.map { String(format: "%.1f Hz", $0) } ?? "Unavailable")
                LabeledContent("Display", value: viewModel.displayID.map { "Display \($0)" } ?? "Unavailable")
                LabeledContent("Frames Measured", value: "\(viewModel.sampleCount)")
            }
            .padding()
        }
        .navigationTitle("FPS Performance Monitor")
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}
