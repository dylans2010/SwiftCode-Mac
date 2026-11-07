import Foundation
import Observation
import SwiftUI
import YcodeCompletion
import YcodeIDECore
import YcodeIDEShell

@MainActor
@Observable
final class ShellPreferences {
    static let shared = ShellPreferences()
    private(set) var revision = 0
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: Preferences.didChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ShellPreferences.shared.changed() }
        }
    }

    private func changed() {
        revision &+= 1
        ShellApp.model.workspace?.preferencesChanged()
        Self.persist()
    }

    func touch() {
        revision &+= 1
        Self.persist()
    }

    static func persist() { UserDefaults.standard.synchronize() }

    static var completionWhileTyping: Bool {
        UserDefaults.standard.object(forKey: completionKey) as? Bool ?? false
    }
    static let completionKey = "SwiftCode.linuxCompletionWhileTyping"

    static var fontSize: Double { Preferences.shared.sourceFontSize ?? Preferences.shared.theme.fontSize }
}

enum ShellSettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, accounts, codingAssistant, behaviors, navigation, notifications, editing, shortcuts, sourceControl, components, locations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .accounts: AccountsPage.title
        case .codingAssistant: "Coding Assistant"
        case .behaviors: "Behaviors"
        case .navigation: "Navigation"
        case .notifications: "Notifications"
        case .editing: "Editing"
        case .shortcuts: "Shortcuts"
        case .sourceControl: "Source Control"
        case .components: "Components"
        case .locations: "Locations"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "circle.lefthalf.filled"
        case .accounts: "person.crop.circle"
        case .codingAssistant: "sparkles"
        case .behaviors: "rectangle.on.rectangle"
        case .navigation: "arrow.triangle.turn.up.right.diamond"
        case .notifications: "bell"
        case .editing: "square.and.pencil"
        case .shortcuts: "keyboard"
        case .sourceControl: "arrow.triangle.branch"
        case .components: "square.stack.3d.up"
        case .locations: "externaldrive"
        }
    }
}

@MainActor
@Observable
final class ShellSettingsModel {
    static let shared = ShellSettingsModel()

    private(set) var pane: ShellSettingsPane = .general
    private(set) var back: [ShellSettingsPane] = []
    private(set) var forward: [ShellSettingsPane] = []
    var editingPage: EditingSettingsPane.Page = .main
    var behaviorEvent: Preferences.Event?
    var isAccountsSheetShown = false

    func select(_ p: ShellSettingsPane) {
        guard p != pane else { return }
        back.append(pane)
        forward = []
        pane = p
    }

    func goBack() {
        guard let p = back.popLast() else { return }
        forward.append(pane)
        pane = p
    }

    func goForward() {
        guard let p = forward.popLast() else { return }
        back.append(pane)
        pane = p
    }
}

struct ShellSettingsView: View {
    @Bindable var model = ShellSettingsModel.shared
    @Environment(\.colorScheme) private var scheme

    static let size = SettingsLayout.windowSize
    static let sidebarWidth = SettingsLayout.sidebarWidth

    var body: some View {
        let p = SettingsPalette(scheme)
        HStack(spacing: 0) {
            sidebar(p)
                .frame(width: SettingsLayout.sidebarWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(p.sidebar)
            Rectangle().fill(p.divider).frame(width: SettingsLayout.dividerWidth)
            VStack(spacing: 0) {
                titleRow(p)
                pane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(p.detail)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .shellTarget("settings")
    }

    static let titleHeight = SettingsLayout.titleAreaHeight

    func sidebar(_ p: SettingsPalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ShellSettingsPane.allCases) { pane in
                let on = pane == model.pane
                Button { model.select(pane) } label: {
                    ZStack(alignment: .leading) {
                        if on {
                            RoundedRectangle(cornerRadius: SettingsLayout.selectionRadius, style: .continuous)
                                .fill(p.selection)
                                .padding(.horizontal, SettingsLayout.selectionInset)
                        }
                        SettingsSidebarSymbol(pane: pane, color: on ? Color.white : p.symbol)
                            .frame(width: 2 * SettingsLayout.symbolCenterX, alignment: .center)
                        Text(verbatim: pane.title)
                            .font(SettingsFonts.label)
                            .foregroundStyle(on ? Color.white : p.label)
                            .lineLimit(1)
                            .padding(.leading, SettingsLayout.sidebarLabelX)
                            .padding(.trailing, SettingsLayout.selectionInset + 4)
                    }
                    .frame(width: SettingsLayout.sidebarWidth, height: SettingsLayout.sidebarRowHeight, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pane.title)
                .shellTarget("settings pane \(pane.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .padding(.top, SettingsLayout.sidebarTop)
    }

    func titleRow(_ p: SettingsPalette) -> some View {
        let cap = SettingsLayout.capsuleFrame
        return HStack(spacing: 0) {
            SettingsNavigationCapsule(model: model)
                .frame(width: cap.width, height: cap.height)
                .padding(.leading, cap.minX - SettingsLayout.detailX)
            Text(verbatim: model.pane.title)
                .font(SettingsFonts.title)
                .foregroundStyle(p.title)
                .lineLimit(1)
                .padding(.leading, SettingsLayout.titleX - cap.maxX)
                .shellTarget("settings title")
            Spacer(minLength: 0)
        }
        .padding(.top, cap.minY)
        .frame(height: Self.titleHeight, alignment: .top)
    }

    @ViewBuilder var pane: some View {
        switch model.pane {
        case .general: GeneralSettingsPane()
        case .appearance: AppearanceSettingsPane()
        case .accounts: AccountsSettingsPane(model: model)
        case .codingAssistant: CodingAssistantSettingsPane()
        case .behaviors: BehaviorsSettingsPane(model: model)
        case .navigation: NavigationSettingsPane()
        case .notifications: NotificationsSettingsPane()
        case .editing: EditingSettingsPane(model: model)
        case .shortcuts: ShortcutsSettingsPane()
        case .sourceControl: SourceControlSettingsPane()
        case .components: ComponentsSettingsPane()
        case .locations: LocationsSettingsPane()
        }
    }
}

struct SettingsSidebarSymbol: View {
    var pane: ShellSettingsPane
    var color: Color

    var body: some View {
        let line = StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
        switch pane {
        case .appearance:
            ZStack {
                Circle().stroke(color, style: line)
                SettingsHalfDisc().fill(color)
            }
            .frame(width: 15, height: 15)
        case .navigation:
            ZStack {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous).stroke(color, style: line)
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(45))
                SettingsTurnArrow().stroke(color, style: line).frame(width: 7, height: 7)
            }
            .frame(width: 17, height: 17)
        case .shortcuts:
            ZStack {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous).stroke(color, style: line)
                SettingsKeyboardKeys().fill(color)
            }
            .frame(width: 19, height: 13)
        case .locations:
            ZStack(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(color, style: line)
                Circle().fill(color).frame(width: 2.5, height: 2.5).padding(.trailing, 3.5)
            }
            .frame(width: 18, height: 11)
        default:
            Image(systemName: pane.symbol)
                .font(.system(size: SettingsLayout.symbolPointSize))
                .foregroundStyle(color)
        }
    }
}

struct SettingsHalfDisc: Shape {
    nonisolated func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addArc(center: CGPoint(x: r.midX, y: r.midY), radius: r.width / 2, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
        p.closeSubpath()
        return p
    }
}

struct SettingsTurnArrow: Shape {
    nonisolated func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.move(to: CGPoint(x: r.maxX - 2.5, y: r.midY - 2.5))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX - 2.5, y: r.midY + 2.5))
        return p
    }
}

struct SettingsKeyboardKeys: Shape {
    nonisolated func path(in r: CGRect) -> Path {
        var p = Path()
        let key: CGFloat = 1.8
        for row in 0..<2 {
            for i in 0..<5 {
                p.addRect(CGRect(x: r.minX + 3 + CGFloat(i) * 3, y: r.minY + 2.6 + CGFloat(row) * 3, width: key, height: key))
            }
        }
        p.addRect(CGRect(x: r.minX + 5.5, y: r.maxY - 3.6, width: r.width - 11, height: 1.5))
        return p
    }
}

struct SettingsNavigationCapsule: View {
    var model: ShellSettingsModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = SettingsPalette(scheme)
        HStack(spacing: 0) {
            half(left: true, enabled: !model.back.isEmpty, p) { model.goBack() }
            Rectangle().fill(p.capsuleDivider).frame(width: 1, height: 20)
            half(left: false, enabled: !model.forward.isEmpty, p) { model.goForward() }
        }
        .background {
            Capsule(style: .continuous)
                .fill(p.capsuleFill)
                .overlay { Capsule(style: .continuous).stroke(p.capsuleRim, lineWidth: 0.5) }
                .shadow(color: Color.black.opacity(0.12), radius: 3, y: 1)
        }
    }

    func half(left: Bool, enabled: Bool, _ p: SettingsPalette, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SettingsChevron(left: left)
                .stroke(enabled ? p.chevron : p.chevronDisabled, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 8, height: 14.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(left ? "Back" : "Forward")
        .accessibilityLabel(left ? "Back" : "Forward")
        .shellTarget(left ? "settings back" : "settings forward")
    }
}

struct SettingsChevron: Shape {
    var left: Bool

    nonisolated func path(in r: CGRect) -> Path {
        var p = Path()
        if left {
            p.move(to: CGPoint(x: r.maxX - 1, y: r.minY + 1))
            p.addLine(to: CGPoint(x: r.minX + 1, y: r.midY))
            p.addLine(to: CGPoint(x: r.maxX - 1, y: r.maxY - 1))
        } else {
            p.move(to: CGPoint(x: r.minX + 1, y: r.minY + 1))
            p.addLine(to: CGPoint(x: r.maxX - 1, y: r.midY))
            p.addLine(to: CGPoint(x: r.minX + 1, y: r.maxY - 1))
        }
        return p
    }
}

@MainActor
func setting<T>(_ key: ReferenceWritableKeyPath<Preferences, T>) -> Binding<T> {
    Binding(get: { Preferences.shared[keyPath: key] }, set: { Preferences.shared[keyPath: key] = $0 })
}

extension View {
    func shellAppearance() -> some View { modifier(ShellAppearanceModifier()) }
}

struct ShellAppearanceModifier: ViewModifier {
    func body(content: Content) -> some View {
        let _ = ShellPreferences.shared.revision
        let a = Preferences.shared.appearance
        content.preferredColorScheme(a == .system ? nil : (a == .dark ? .dark : .light))
    }
}
