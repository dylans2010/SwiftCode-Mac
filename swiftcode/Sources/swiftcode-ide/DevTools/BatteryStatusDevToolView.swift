import SwiftUI
import SwiftCodeUI
import os.log
#if canImport(IOKit)
import IOKit
#endif

@Observable
@MainActor
final class BatteryStatusViewModel {
    var level: Double?
    var isCharging: Bool?
    var timeRemaining: String?
    var sourceType: String?
    var capacityText: String?
    var unavailableReason: String?

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "BatteryStatus")

    func refreshStatus() {
        level = nil
        isCharging = nil
        timeRemaining = nil
        sourceType = nil
        capacityText = nil
        unavailableReason = nil

        #if canImport(IOKit)
        refreshFromIOKit()
        #else
        unavailableReason = "Battery status needs IOKit, which is macOS-only."
        logger.info("Battery status unavailable: IOKit is not available on this platform")
        #endif
    }

    #if canImport(IOKit)
    private func refreshFromIOKit() {
        let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        guard let sources = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            unavailableReason = "No battery found — this Mac has no internal battery."
            logger.info("Battery status unavailable: no power sources reported by IOKit")
            return
        }

        var description: [String: Any]?
        for source in sources {
            guard let details = IOPSGetPowerSourceDescription(blob, source).takeUnretainedValue() as? [String: Any] else { continue }
            if (details[kIOPSTypeKey as String] as? String) == (kIOPSInternalBatteryType as String) {
                description = details
                break
            }
            if description == nil { description = details }
        }
        guard let details = description else {
            unavailableReason = "No battery found — this Mac has no internal battery."
            logger.info("Battery status unavailable: no readable power source description")
            return
        }

        let current = details[kIOPSCurrentCapacityKey as String] as? Int
        let max = details[kIOPSMaxCapacityKey as String] as? Int
        if let current, let max, max > 0 {
            level = Double(current) / Double(max) * 100
            capacityText = "\(current) of \(max)"
        }

        if let charging = details[kIOPSIsChargingKey as String] as? Bool {
            isCharging = charging
        } else if let state = details[kIOPSPowerSourceStateKey as String] as? String {
            isCharging = (state == (kIOPSACPowerValue as String))
        }

        if let type = details[kIOPSTypeKey as String] as? String {
            sourceType = type == (kIOPSInternalBatteryType as String) ? "Internal Mac Battery" : type
        }

        if isCharging == true {
            if let minutes = details[kIOPSTimeToFullChargeKey as String] as? Int, minutes >= 0 {
                timeRemaining = Self.formatted(minutes: minutes) + " to full charge"
            }
        } else if let minutes = details[kIOPSTimeToEmptyKey as String] as? Int, minutes >= 0 {
            timeRemaining = Self.formatted(minutes: minutes) + " remaining"
        }
        if timeRemaining == nil {
            timeRemaining = "Calculating…"
        }

        logger.info("Refreshed system battery status values")
    }
    #endif

    private static func formatted(minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 {
            return "\(hours) hours, \(remainder) minutes"
        }
        return "\(remainder) minutes"
    }
}

struct BatteryStatusDevToolView: View {
    @State private var viewModel = BatteryStatusViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Inspect macOS battery power sources, current charge level, and charging rates.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let reason = viewModel.unavailableReason {
                    Label(reason, systemImage: "battery.0")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .liquidGlass(style: .standard, cornerRadius: 12)
                } else {
                    VStack(alignment: .center, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary, lineWidth: 3)
                                .frame(width: 140, height: 70)

                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill((viewModel.level ?? 0) > 20 ? Color.green : Color.red)
                                    .frame(width: CGFloat(viewModel.level ?? 0) * 1.2, height: 56)
                                Spacer(minLength: 0)
                            }
                            .frame(width: 120, height: 56)
                            .clipped()

                            Text(viewModel.level.map { "\(Int($0))%" } ?? "—")
                                .font(.system(.title3, design: .monospaced))
                                .bold()
                                .foregroundColor(.primary)
                        }

                        HStack {
                            Image(systemName: viewModel.isCharging == true ? "bolt.fill" : "bolt.slash.fill")
                            Text(viewModel.isCharging == true ? "Charging Mode Enabled" : "Discharging on Battery Power")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .liquidGlass(style: .standard, cornerRadius: 12)

                    Divider()

                    LabeledContent("Time Remaining", value: viewModel.timeRemaining ?? "—")
                    LabeledContent("Source Type", value: viewModel.sourceType ?? "—")
                    LabeledContent("Capacity", value: viewModel.capacityText ?? "—")
                }

                Button("Refresh Status") {
                    viewModel.refreshStatus()
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle("Battery Status Monitor")
        .onAppear {
            viewModel.refreshStatus()
        }
    }
}
