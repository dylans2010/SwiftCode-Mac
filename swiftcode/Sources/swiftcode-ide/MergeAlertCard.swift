import Foundation
import SwiftUI
import SwiftCodeIDECore
import SwiftCodeIDEShell

struct MergeAlertCard: View {
    var scm: SourceControlShellModel
    var alert: MergeAlertState
    var isReady: Bool
    var isLeaving: Bool
    @Environment(\.colorScheme) private var scheme

    typealias M = MergeSheetMetrics

    var body: some View {
        let p = MergeSheetPalette.forDark(scheme == .dark)
        let w = CGFloat(M.alertWidth), h = CGFloat(M.alertHeight + (alert.hasChooser ? M.alertChooserHeight : 0))
        let textX = CGFloat(M.alertTextX), textWidth = w - textX - 20
        let mergeX = w - CGFloat(M.alertButtonTrailing + M.alertMergeWidth)
        let cancelX = mergeX - CGFloat(M.alertButtonSpacing + M.alertCancelWidth)
        let buttonY = h - CGFloat(M.alertButtonBottom + M.alertButtonHeight)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: CGFloat(M.cornerRadius), style: .continuous)
                .fill(Color(mergeHex: p.sheet))
                .shadow(color: Color.black.opacity(scheme == .dark ? 0.5 : 0.25), radius: 14, x: 0, y: 6)
            SwiftCodeMark(size: CGFloat(M.alertIcon))
                .offset(x: CGFloat(M.alertIconOrigin.x), y: CGFloat(M.alertIconOrigin.y))
            Text(verbatim: alert.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(mergeHex: p.label))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: textWidth, alignment: .topLeading)
                .offset(x: textX, y: CGFloat(M.alertTitleTop) - 4)
                .shellTarget("merge alert title")
            Text(verbatim: alert.message)
                .font(.system(size: 11))
                .foregroundStyle(Color(mergeHex: scheme == .dark ? p.label : 0x000000))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: textWidth, alignment: .topLeading)
                .offset(x: textX, y: CGFloat(M.alertMessageTop) - 2)
                .shellTarget("merge alert message")
            if let choices = alert.choices, !choices.isEmpty {
                Menu {
                    ForEach(choices, id: \.self) { b in
                        Button(b) { scm.chooseMergeBranch(b) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: alert.branch).font(.system(size: 12)).foregroundStyle(Color(mergeHex: p.label)).lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color(mergeHex: p.secondaryLabel))
                    }
                    .padding(.horizontal, 8)
                    .frame(width: textWidth, height: 22)
                    .background { RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(mergeHex: p.button)) }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .offset(x: textX, y: CGFloat(M.alertMessageTop) + 30)
                .shellTarget("merge alert branch")
            }
            Button { if !isLeaving { scm.cancelMergeAlert() } } label: {
                MergeButtonLabel(title: MergeSheetText.cancel, isDefault: false, palette: p,
                                 width: CGFloat(M.alertCancelWidth), height: CGFloat(M.alertButtonHeight))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .offset(x: cancelX, y: buttonY)
            .shellTarget("merge alert cancel")
            Button { if !isLeaving { scm.confirmMergeAlert() } } label: {
                MergeButtonLabel(title: MergeSheetText.merge, isDefault: isReady, palette: p,
                                 width: CGFloat(M.alertMergeWidth), height: CGFloat(M.alertButtonHeight))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .offset(x: mergeX, y: buttonY)
            .shellTarget("merge alert merge")
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .contentShape(Rectangle())
        .shellTarget("merge alert")
    }
}
