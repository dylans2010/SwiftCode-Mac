import Foundation
import SwiftUI
import SwiftCodeIDECore
import SwiftCodeIDEShell
#if os(Linux) && canImport(OVDBus)
import OVDBus
#endif

struct BuildBezelOverlay: View {
    var notifier: ShellBuildNotifier
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let n = notifier.bezel {
                BuildBezelView(notice: n)
                    .opacity(notifier.isFading ? 0 : 1)
                    .animation(reduceMotion ? nil : .easeOut(duration: BezelTimeline.fadeDuration), value: notifier.isFading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onAppear { sync() }
        .onChange(of: scenePhase) { _, _ in sync() }
        .onChange(of: reduceMotion) { _, _ in sync() }
        .onChange(of: notifier.log.count) { _, n in BezelShots.take(n, notifier) }
    }

    private func sync() {
        notifier.isWindowActive = scenePhase == .active
        notifier.reduceMotion = reduceMotion
        if notifier.announce == nil {
            notifier.announce = { AccessibilityNotification.Announcement($0).post() }
        }
        if notifier.postSystemNotification == nil { notifier.postSystemNotification = DesktopNotifications.post }
    }
}

struct BuildBezelView: View {
    var notice: BuildNotice

    #if os(Linux)
    static let titleWeight: Font.Weight = .bold
    #else
    static let titleWeight: Font.Weight = .semibold
    #endif

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.sRGB, red: 0.08, green: 0.08, blue: 0.08).opacity(0.86))
            VStack(spacing: 0) {
                glyph
                    .frame(width: 112, height: 96)
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.top, 40)
                Spacer(minLength: 0)
                Text(notice.title)
                    .font(.system(size: 17, weight: Self.titleWeight))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 28)
            }
        }
        .frame(width: 200, height: 200)
        .accessibilityHidden(true)
        .accessibilityIdentifier("build bezel")
    }

    private var glyph: some View {
        Image(systemName: notice.symbolName)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}

enum DesktopNotifications {
    static let service = "org.freedesktop.Notifications"

    @MainActor
    static func post(_ n: BuildNotice, workspace: String) {
        #if os(Linux) && canImport(OVDBus)
        guard let bus = try? DBusConnection.session(timeout: 1) else { return }
        bus.startDispatch()
        let hasOwner = DBusMessage.methodCall(destination: DBusConnection.busName, path: DBusConnection.busPath,
                                              interface: DBusConnection.busName, member: "NameHasOwner", body: [.string(service)])
        let notify = DBusMessage.methodCall(destination: service, path: "/org/freedesktop/Notifications", interface: service,
                                            member: "Notify",
                                            body: [.string("SwiftCode"), .uint32(0), .string(""), .string(n.title), .string(workspace),
                                                   .strings([]), .emptyProperties, .int32(-1)])
        do {
            try bus.call(hasOwner) { reply in
                guard reply.type == .methodReturn, reply.body.first?.boolValue == true else { return bus.close() }
                do { try bus.call(notify) { _ in bus.close() } } catch { bus.close() }
            }
        } catch {
            bus.close()
        }
        #endif
    }
}

@MainActor
enum BezelShots {
    static func take(_ count: Int, _ notifier: ShellBuildNotifier) {
        #if os(Linux)
        guard let prefix = ProcessInfo.processInfo.environment["SWIFTCODE_IDE_BEZEL_SHOT"],
              let last = notifier.log.last, last.hasPrefix("bezel ") else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            let r = OpenViewsAutomation.screenshot(to: "\(prefix)-\(count).png")
            FileHandle.standardOutput.write(Data("bezel shot \(count) \(last): \(r)\n".utf8))
        }
        #endif
    }
}
