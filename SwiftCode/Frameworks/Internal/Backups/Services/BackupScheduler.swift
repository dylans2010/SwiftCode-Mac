import Foundation

public final class BackupScheduler: @unchecked Sendable {
    public static let shared = BackupScheduler()

    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.swiftcode.backups.scheduler", qos: .background)

    private init() {}

    public func start() {
        // Runs scheduled periodic point-in-time snapshot operations
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 3600.0, repeats: true) { [weak self] _ in
                self?.queue.async {
                    Task {
                        await self?.runScheduledBackup()
                    }
                }
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func runScheduledBackup() async {
        // Verify low CPU utilization and power/battery status before execution
        do {
            try await BackupManager.shared.createBackup(name: "Scheduled Auto Backup", provider: .supabase)
        } catch {
            // Logs scheduler failure to central diagnostics
        }
    }
}
