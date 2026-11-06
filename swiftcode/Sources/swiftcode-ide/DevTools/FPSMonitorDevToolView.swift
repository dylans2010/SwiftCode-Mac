// Ported from SwiftCode-Legacy `SwiftCode/Views/Dev Tools/FPSMonitorDevToolView.swift` (Dylan's own code; direct port authorised under MIT).
// V10 (independent verification): confirmed genuinely missing from production at bc28f653.
// Verbatim port: no references to Legacy-only types; `import SwiftCodeUI` added for .liquidGlass.
//
// CLEANUP (2026-11-06, A1): updateFPS() invented its reading with
// a random-number call in the 118...120 range, and the "Adaptive Sync Status: Enabled
// (ProMotion)" / "Drawing Backing Engine: Metal CoreAnimation Pipeline"
// rows were invented claims, not measurements. Replaced with real frame
// measurement: a CVDisplayLink on the active display calls back once per
// vsync; FPS is the rolling mean of the last 30 measured output intervals
// and frame duration is its reciprocal. Nominal refresh rate comes from
// CVDisplayLinkGetNominalOutputVideoRefreshPeriod and the display id from
// CVDisplayLinkGetCurrentCGDisplay — both real. Where CoreVideo is
// unavailable the view honestly says so instead of showing a number.
import SwiftUI
import SwiftCodeUI
import os.log
#if canImport(CoreVideo)
import CoreVideo
#endif

#if canImport(CoreVideo)
/// CVDisplayLink output callback: forwards each vsync timestamp to the
/// view model on the main actor. The context is the unretained view model;
/// the model owns the link and stops it before it can be deallocated.
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
    /// Measured frames per second (rolling mean of the last 30 vsync
    /// intervals). Nil until real frames have been observed.
    var fps: Double?
    /// Measured mean frame duration in milliseconds. Nil until observed.
    var frameDurationMs: Double?
    /// Nominal refresh rate of the active display, in Hz. Nil until read.
    var nominalRefreshHz: Double?
    /// The display the link is attached to. Nil until read.
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

    /// Records one measured vsync timestamp. Intervals outside (0, 1s]
    /// are discarded (first frame, or a glitch), so no invented rate can
    /// leak in from a bad sample.
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
