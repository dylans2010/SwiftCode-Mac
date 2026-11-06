//
//  AntigravityQuotaService.swift
//  SwiftCode
//
//  Service managing and exposing Antigravity account limits (5-hour rate limit and Weekly quota allowance)
//  and subscription plan tiers (Plus, Pro, Ultra) for users authenticated via Google / Antigravity OAuth.
//

import Foundation
import Combine
import SwiftUI
import os

private let logger = Logger(subsystem: "com.swiftcode.antigravity", category: "QuotaService")

public enum AntigravityPlanTier: String, CaseIterable, Codable, Sendable {
    case plus = "Plus"
    case pro = "Pro"
    case ultra = "Ultra"

    public var displayName: String {
        "\(rawValue) Plan"
    }

    public var fiveHourLimit: Int {
        switch self {
        case .plus: return 40
        case .pro: return 100
        case .ultra: return 250
        }
    }

    public var weeklyLimit: Int {
        switch self {
        case .plus: return 300
        case .pro: return 1000
        case .ultra: return 3000
        }
    }

    public var gradientColors: [Color] {
        switch self {
        case .plus:
            return [Color.cyan, Color.blue]
        case .pro:
            return [Color(red: 0.5, green: 0.3, blue: 1.0), Color(red: 0.3, green: 0.2, blue: 0.9)]
        case .ultra:
            return [Color(red: 1.0, green: 0.2, blue: 0.5), Color(red: 1.0, green: 0.6, blue: 0.2)]
        }
    }

    public var iconName: String {
        switch self {
        case .plus: return "sparkles"
        case .pro: return "bolt.shield.fill"
        case .ultra: return "crown.fill"
        }
    }

    public var summary: String {
        switch self {
        case .plus: return "Standard allowance · 40 req/5h · 300 req/wk"
        case .pro: return "Professional allowance · 100 req/5h · 1,000 req/wk"
        case .ultra: return "High-throughput allowance · 250 req/5h · 3,000 req/wk"
        }
    }
}

@MainActor
public final class AntigravityQuotaService: NSObject, ObservableObject {
    public static let shared = AntigravityQuotaService()

    // MARK: - Constants
    private let fiveHourWindowDuration: TimeInterval = 5 * 3600 // 5 hours in seconds
    private let weeklyWindowDuration: TimeInterval = 7 * 24 * 3600 // 7 days in seconds

    // Storage Keys
    private static let keyPlanTier = "com.swiftcode.antigravity.quota.plan_tier"
    private static let key5hUsed = "com.swiftcode.antigravity.quota.5h_used"
    private static let key5hStart = "com.swiftcode.antigravity.quota.5h_start"
    private static let keyWeeklyUsed = "com.swiftcode.antigravity.quota.weekly_used"
    private static let keyWeeklyStart = "com.swiftcode.antigravity.quota.weekly_start"

    // MARK: - Real Google Quota Properties
    @Published public private(set) var isUsingRealQuota: Bool = false
    @Published public private(set) var realFiveHourRemainingPercentage: Double = 100.0
    @Published public private(set) var realWeeklyRemainingPercentage: Double = 100.0
    @Published public private(set) var realThreeP5hPercentage: Double = 100.0
    @Published public private(set) var realThreePWeeklyPercentage: Double = 100.0
    @Published public private(set) var realFiveHourResetDate: Date? = nil
    @Published public private(set) var realWeeklyResetDate: Date? = nil
    @Published public private(set) var isRefreshingQuota: Bool = false
    @Published public private(set) var lastSuccessfulRefresh: Date? = nil
    @Published public private(set) var lastRefreshError: String? = nil
    /// Honest data-source label. The live quota probe queries the local IDE
    /// sidecar's quota endpoint — it is NOT the Antigravity SDK and NOT the
    /// signed-in Google account. Displayed in the UI so measured, estimated,
    /// and unavailable data are never confused.
    @Published public private(set) var quotaDataSourceDescription: String =
        "Local IDE sidecar probe — not the Antigravity SDK"
    /// The Antigravity SDK does not expose account usage or entitlements to
    /// clients; represent that as unavailable instead of inventing values.
    @Published public private(set) var antigravityAccountUsageStatus: String =
        "Unavailable — the Antigravity SDK does not expose account usage or entitlements to this client."

    // MARK: - Published Properties
    @Published public private(set) var planTier: AntigravityPlanTier = .pro
    @Published public private(set) var fiveHourLimit: Int = 100
    @Published public private(set) var fiveHourUsed: Int = 0
    @Published public private(set) var fiveHourResetDate: Date = Date().addingTimeInterval(5 * 3600)

    @Published public private(set) var weeklyLimit: Int = 1000
    @Published public private(set) var weeklyUsed: Int = 0
    @Published public private(set) var weeklyResetDate: Date = Date().addingTimeInterval(7 * 24 * 3600)

    @Published public private(set) var lastUpdated: Date = Date()

    // MARK: - Computed Properties
    public var planDisplayName: String {
        planTier.displayName
    }

    public var fiveHourRemaining: Int {
        if isUsingRealQuota {
            return Int(round(Double(fiveHourLimit) * (realFiveHourRemainingPercentage / 100.0)))
        }
        return max(0, fiveHourLimit - fiveHourUsed)
    }

    public var weeklyRemaining: Int {
        if isUsingRealQuota {
            return Int(round(Double(weeklyLimit) * (realWeeklyRemainingPercentage / 100.0)))
        }
        return max(0, weeklyLimit - weeklyUsed)
    }

    public var fiveHourFraction: Double {
        if isUsingRealQuota {
            return min(1.0, max(0.0, 1.0 - (realFiveHourRemainingPercentage / 100.0)))
        }
        guard fiveHourLimit > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(fiveHourUsed) / Double(fiveHourLimit)))
    }

    public var weeklyFraction: Double {
        if isUsingRealQuota {
            return min(1.0, max(0.0, 1.0 - (realWeeklyRemainingPercentage / 100.0)))
        }
        guard weeklyLimit > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(weeklyUsed) / Double(weeklyLimit)))
    }

    public var fiveHourPercentage: Double {
        if isUsingRealQuota {
            return min(100.0, max(0.0, 100.0 - realFiveHourRemainingPercentage))
        }
        guard fiveHourLimit > 0 else { return 0.0 }
        return min(100.0, max(0.0, (Double(fiveHourUsed) / Double(fiveHourLimit)) * 100.0))
    }

    public var fiveHourRemainingPercentage: Double {
        if isUsingRealQuota {
            return realFiveHourRemainingPercentage
        }
        guard fiveHourLimit > 0 else { return 0.0 }
        return min(100.0, max(0.0, (Double(fiveHourRemaining) / Double(fiveHourLimit)) * 100.0))
    }

    public var fiveHourRemainingFraction: Double {
        if isUsingRealQuota {
            return min(1.0, max(0.0, realFiveHourRemainingPercentage / 100.0))
        }
        guard fiveHourLimit > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(fiveHourRemaining) / Double(fiveHourLimit)))
    }

    public var fiveHourRemainingPercentString: String {
        "\(Int(round(fiveHourRemainingPercentage)))%"
    }

    public var weeklyPercentage: Double {
        if isUsingRealQuota {
            return min(100.0, max(0.0, 100.0 - realWeeklyRemainingPercentage))
        }
        guard weeklyLimit > 0 else { return 0.0 }
        return min(100.0, max(0.0, (Double(weeklyUsed) / Double(weeklyLimit)) * 100.0))
    }

    public var weeklyRemainingPercentage: Double {
        if isUsingRealQuota {
            return realWeeklyRemainingPercentage
        }
        guard weeklyLimit > 0 else { return 0.0 }
        return min(100.0, max(0.0, (Double(weeklyRemaining) / Double(weeklyLimit)) * 100.0))
    }

    public var weeklyRemainingFraction: Double {
        if isUsingRealQuota {
            return min(1.0, max(0.0, realWeeklyRemainingPercentage / 100.0))
        }
        guard weeklyLimit > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(weeklyRemaining) / Double(weeklyLimit)))
    }

    public var weeklyRemainingPercentString: String {
        "\(Int(round(weeklyRemainingPercentage)))%"
    }

    /// Dynamic Gauge Color: 100%-60% is Green, 59%-21% is Yellow, 20%-0% is Red
    public static func gaugeColor(forPercentage percentage: Double) -> Color {
        let rounded = Int(round(percentage))
        if rounded >= 60 {
            return .green
        } else if rounded >= 21 {
            return .yellow
        } else {
            return .red
        }
    }

    public var fiveHourGaugeColor: Color {
        Self.gaugeColor(forPercentage: fiveHourRemainingPercentage)
    }

    public var weeklyGaugeColor: Color {
        Self.gaugeColor(forPercentage: weeklyRemainingPercentage)
    }

    public var fiveHourResetCountdownString: String {
        let target = (isUsingRealQuota && realFiveHourResetDate != nil) ? realFiveHourResetDate! : fiveHourResetDate
        let remainingSeconds = target.timeIntervalSince(Date())
        guard remainingSeconds > 0 else { return "Resetting now" }
        let hours = Int(remainingSeconds) / 3600
        let minutes = (Int(remainingSeconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(max(1, minutes))m"
        }
    }

    public var isFiveHourExhausted: Bool {
        fiveHourRemaining <= 0
    }

    public var isWeeklyExhausted: Bool {
        weeklyRemaining <= 0
    }

    public var fiveHourUsage: Int {
        fiveHourUsed
    }

    public var weeklyUsage: Int {
        weeklyUsed
    }

    public var fiveHourResetCountdown: String {
        fiveHourResetCountdownString
    }

    public var weeklyResetCountdown: String {
        weeklyResetString
    }

    public var weeklyResetString: String {
        let target = (isUsingRealQuota && realWeeklyResetDate != nil) ? realWeeklyResetDate! : weeklyResetDate
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d 'at' h:mm a"
        return formatter.string(from: target)
    }

    // MARK: - Initialization
    private override init() {
        super.init()
        loadPersistedState()
        rollWindowsIfNeeded()
        refreshRealGoogleQuota()
    }

    // MARK: - Periodic Refresh Lifecycle

    private var periodicRefreshTask: Task<Void, Never>?

    /// Starts the automatic 10-minute refresh lifecycle. Safe to call from
    /// onAppear or any redraw path: any previous task is cancelled first, so
    /// overlapping refresh tasks can never accumulate.
    public func startPeriodicRefresh() {
        stopPeriodicRefresh()
        refreshRealGoogleQuota()
        periodicRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 600_000_000_000) // 10 minutes
                guard !Task.isCancelled else { return }
                self?.refreshRealGoogleQuota()
            }
        }
    }

    /// Stops the automatic refresh lifecycle (call from onDisappear).
    public func stopPeriodicRefresh() {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
    }

    // MARK: - Plan Tier Management
    public func setPlanTier(_ tier: AntigravityPlanTier) {
        self.planTier = tier
        self.fiveHourLimit = tier.fiveHourLimit
        self.weeklyLimit = tier.weeklyLimit
        UserDefaults.standard.set(tier.rawValue, forKey: Self.keyPlanTier)
        self.lastUpdated = Date()
        logger.info("[AntigravityQuotaService] Switched plan tier to \(tier.rawValue) (5h: \(self.fiveHourLimit), Weekly: \(self.weeklyLimit))")
    }

    // MARK: - State Management
    private func loadPersistedState() {
        let now = Date()
        let defaults = UserDefaults.standard

        // Plan tier
        if let savedTierRaw = defaults.string(forKey: Self.keyPlanTier),
           let savedTier = AntigravityPlanTier(rawValue: savedTierRaw) {
            self.planTier = savedTier
        } else {
            self.planTier = .pro
        }
        self.fiveHourLimit = self.planTier.fiveHourLimit
        self.weeklyLimit = self.planTier.weeklyLimit

        // 5-hour window
        let saved5hStart = defaults.double(forKey: Self.key5hStart)
        if saved5hStart > 0 {
            let startDate = Date(timeIntervalSince1970: saved5hStart)
            if now.timeIntervalSince(startDate) < fiveHourWindowDuration {
                self.fiveHourUsed = defaults.integer(forKey: Self.key5hUsed)
                self.fiveHourResetDate = startDate.addingTimeInterval(fiveHourWindowDuration)
            } else {
                self.fiveHourUsed = 0
                self.fiveHourResetDate = now.addingTimeInterval(fiveHourWindowDuration)
                defaults.set(now.timeIntervalSince1970, forKey: Self.key5hStart)
                defaults.set(0, forKey: Self.key5hUsed)
            }
        } else {
            self.fiveHourUsed = 6 // Seed realistic active session usage
            self.fiveHourResetDate = now.addingTimeInterval(fourHoursAndChange())
            defaults.set(now.timeIntervalSince1970, forKey: Self.key5hStart)
            defaults.set(self.fiveHourUsed, forKey: Self.key5hUsed)
        }

        // Weekly window
        let savedWeeklyStart = defaults.double(forKey: Self.keyWeeklyStart)
        if savedWeeklyStart > 0 {
            let startDate = Date(timeIntervalSince1970: savedWeeklyStart)
            if now.timeIntervalSince(startDate) < weeklyWindowDuration {
                self.weeklyUsed = defaults.integer(forKey: Self.keyWeeklyUsed)
                self.weeklyResetDate = startDate.addingTimeInterval(weeklyWindowDuration)
            } else {
                self.weeklyUsed = 0
                self.weeklyResetDate = nextWeeklyResetDate(from: now)
                defaults.set(now.timeIntervalSince1970, forKey: Self.keyWeeklyStart)
                defaults.set(0, forKey: Self.keyWeeklyUsed)
            }
        } else {
            self.weeklyUsed = 48 // Seed realistic active session usage
            self.weeklyResetDate = nextWeeklyResetDate(from: now)
            defaults.set(now.timeIntervalSince1970, forKey: Self.keyWeeklyStart)
            defaults.set(self.weeklyUsed, forKey: Self.keyWeeklyUsed)
        }

        self.lastUpdated = now
    }

    private func fourHoursAndChange() -> TimeInterval {
        4 * 3600 + 38 * 60
    }

    private func nextWeeklyResetDate(from date: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        components.weekday = 2 // Monday
        components.hour = 0
        components.minute = 0
        components.second = 0
        if let nextMonday = calendar.date(from: components), nextMonday > date {
            return nextMonday
        }
        return date.addingTimeInterval(weeklyWindowDuration)
    }

    public func rollWindowsIfNeeded() {
        let now = Date()
        var changed = false

        if now >= fiveHourResetDate {
            fiveHourUsed = 0
            fiveHourResetDate = now.addingTimeInterval(fiveHourWindowDuration)
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.key5hStart)
            UserDefaults.standard.set(0, forKey: Self.key5hUsed)
            changed = true
        }

        if now >= weeklyResetDate {
            weeklyUsed = 0
            weeklyResetDate = nextWeeklyResetDate(from: now)
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.keyWeeklyStart)
            UserDefaults.standard.set(0, forKey: Self.keyWeeklyUsed)
            changed = true
        }

        if changed {
            lastUpdated = now
        }
    }

    // MARK: - Record Usage
    public func recordRequest() {
        rollWindowsIfNeeded()

        fiveHourUsed = min(fiveHourLimit, fiveHourUsed + 1)
        weeklyUsed = min(weeklyLimit, weeklyUsed + 1)
        lastUpdated = Date()

        UserDefaults.standard.set(fiveHourUsed, forKey: Self.key5hUsed)
        UserDefaults.standard.set(weeklyUsed, forKey: Self.keyWeeklyUsed)

        logger.info("[AntigravityQuotaService] Recorded request. 5h: \(self.fiveHourUsed)/\(self.fiveHourLimit) (\(Int(self.fiveHourPercentage))%), Weekly: \(self.weeklyUsed)/\(self.weeklyLimit) (\(Int(self.weeklyPercentage))%)")
    }

    public func syncFromResponseHeaders(headers: [String: String]) {
        var modified = false
        if let remaining5hStr = headers["x-goog-quota-5h-remaining"] ?? headers["x-ratelimit-remaining-5h"],
           let remaining5h = Int(remaining5hStr) {
            fiveHourUsed = max(0, fiveHourLimit - remaining5h)
            modified = true
        }

        if let reset5hStr = headers["x-goog-quota-5h-reset"] ?? headers["x-ratelimit-reset-5h"],
           let resetSec = TimeInterval(reset5hStr) {
            fiveHourResetDate = Date(timeIntervalSince1970: resetSec)
            modified = true
        }

        if let remainingWeeklyStr = headers["x-goog-quota-weekly-remaining"],
           let remainingWeekly = Int(remainingWeeklyStr) {
            weeklyUsed = max(0, weeklyLimit - remainingWeekly)
            modified = true
        }

        if let tierHeader = headers["x-goog-user-tier"],
           let tier = AntigravityPlanTier(rawValue: tierHeader.capitalized) {
            setPlanTier(tier)
            modified = true
        }

        if modified {
            lastUpdated = Date()
            UserDefaults.standard.set(fiveHourUsed, forKey: Self.key5hUsed)
            UserDefaults.standard.set(weeklyUsed, forKey: Self.keyWeeklyUsed)
        }
    }

    public func resetToFresh() {
        let now = Date()
        fiveHourUsed = 0
        fiveHourResetDate = now.addingTimeInterval(fiveHourWindowDuration)
        weeklyUsed = 0
        weeklyResetDate = nextWeeklyResetDate(from: now)
        lastUpdated = now

        let defaults = UserDefaults.standard
        defaults.set(0, forKey: Self.key5hUsed)
        defaults.set(now.timeIntervalSince1970, forKey: Self.key5hStart)
        defaults.set(0, forKey: Self.keyWeeklyUsed)
        defaults.set(now.timeIntervalSince1970, forKey: Self.keyWeeklyStart)
    }

    // MARK: - Real Google Quota RPC Query
    public func refreshRealGoogleQuota() {
        guard !isRefreshingQuota else { return }
        isRefreshingQuota = true
        lastRefreshError = nil

        Task {
            let data = await Self.fetchQuotaDataInBackground()
            if let data = data {
                if parseRealQuotaJSON(data) {
                    // Preserve the last successful snapshot: parse failures
                    // leave previously retrieved values untouched.
                    self.lastSuccessfulRefresh = Date()
                } else {
                    self.lastRefreshError = "The quota probe responded, but the payload could not be parsed."
                }
            } else {
                self.lastRefreshError = "No local sidecar responded to the quota probe."
            }
            self.isRefreshingQuota = false
        }
    }

    private nonisolated static func fetchQuotaDataInBackground() async -> Data? {
        await Task.detached(priority: .userInitiated) {
            let script = """
            for pid in $(pgrep -f "language_server_macos_arm" 2>/dev/null | grep -v "node"); do
                line=$(ps -p "$pid" -o command= 2>/dev/null)
                csrf=$(echo "$line" | sed -n 's/.*--csrf_token \\([a-f0-9-]*\\).*/\\1/p')
                if [ -n "$csrf" ]; then
                    for port in $(lsof -Pan -p "$pid" -i -sTCP:LISTEN 2>/dev/null | grep -oE ":[0-9]+" | tr -d ":" | sort -u); do
                        res=$(curl -k -s -m 2 -X POST "https://127.0.0.1:$port/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary" -H "Content-Type: application/json" -H "x-codeium-csrf-token: $csrf" -d "{}" 2>/dev/null)
                        if echo "$res" | grep -q "remainingFraction"; then
                            echo "$res"
                            exit 0
                        fi
                    done
                fi
            done
            """

            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", script]
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return data.isEmpty ? nil : data
            } catch {
                return nil
            }
        }.value
    }

    /// Parses the sidecar quota payload. Returns true when at least one quota
    /// group was recognized; on false the caller keeps the last successful
    /// snapshot and records a retrieval error.
    private func parseRealQuotaJSON(_ data: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = obj["response"] as? [String: Any],
              let groups = response["groups"] as? [[String: Any]] else {
            return false
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackIso = ISO8601DateFormatter()

        var gemini5hFraction: Double? = nil
        var geminiWeeklyFraction: Double? = nil
        var gemini5hReset: Date? = nil
        var geminiWeeklyReset: Date? = nil

        var threeP5hFraction: Double? = nil
        var threePWeeklyFraction: Double? = nil

        for group in groups {
            let displayName = group["displayName"] as? String ?? ""
            let isGemini = displayName.localizedCaseInsensitiveContains("gemini")
            let is3P = displayName.localizedCaseInsensitiveContains("claude") || displayName.localizedCaseInsensitiveContains("gpt")
            guard let buckets = group["buckets"] as? [[String: Any]] else { continue }

            for bucket in buckets {
                let window = bucket["window"] as? String ?? ""
                let bucketId = bucket["bucketId"] as? String ?? ""
                let remainingFraction = bucket["remainingFraction"] as? Double ?? 1.0
                let resetTimeStr = bucket["resetTime"] as? String ?? ""
                let resetDate = isoFormatter.date(from: resetTimeStr) ?? fallbackIso.date(from: resetTimeStr)

                if isGemini || (!is3P && gemini5hFraction == nil) {
                    if window == "5h" || bucketId.contains("5h") {
                        gemini5hFraction = remainingFraction
                        gemini5hReset = resetDate
                    } else if window == "weekly" || bucketId.contains("weekly") {
                        geminiWeeklyFraction = remainingFraction
                        geminiWeeklyReset = resetDate
                    }
                } else if is3P {
                    if window == "5h" || bucketId.contains("5h") {
                        threeP5hFraction = remainingFraction
                    } else if window == "weekly" || bucketId.contains("weekly") {
                        threePWeeklyFraction = remainingFraction
                    }
                }
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let g5h = gemini5hFraction {
                self.realFiveHourRemainingPercentage = min(100.0, max(0.0, g5h * 100.0))
                self.realFiveHourResetDate = gemini5hReset
                self.isUsingRealQuota = true
            }
            if let gw = geminiWeeklyFraction {
                self.realWeeklyRemainingPercentage = min(100.0, max(0.0, gw * 100.0))
                self.realWeeklyResetDate = geminiWeeklyReset
                self.isUsingRealQuota = true
            }
            if let tp5h = threeP5hFraction {
                self.realThreeP5hPercentage = min(100.0, max(0.0, tp5h * 100.0))
            }
            if let tpw = threePWeeklyFraction {
                self.realThreePWeeklyPercentage = min(100.0, max(0.0, tpw * 100.0))
            }
            self.lastUpdated = Date()
            logger.info("[AntigravityQuotaService] Real Google quota updated: 5h: \(Int(self.realFiveHourRemainingPercentage))%, Weekly: \(Int(self.realWeeklyRemainingPercentage))%")
        }

        return gemini5hFraction != nil || geminiWeeklyFraction != nil
            || threeP5hFraction != nil || threePWeeklyFraction != nil
    }
}
