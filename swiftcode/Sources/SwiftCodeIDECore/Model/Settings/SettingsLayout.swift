import Foundation

public enum SettingsLayout {
    public static let windowSize = CGSize(width: 710, height: 452)
    public static let titleAreaHeight: CGFloat = 52
    public static let capsuleFrame = CGRect(x: 187.5, y: 8.5, width: 73.5, height: 34.5)
    public static let titleX: CGFloat = 273.5
    public static let titleCenterY: CGFloat = 26
    public static let titleFontSize: CGFloat = 17

    public static let sidebarWidth: CGFloat = 179.5
    public static let dividerWidth: CGFloat = 0.5
    public static var detailX: CGFloat { sidebarWidth + dividerWidth }
    public static let sidebarRowHeight: CGFloat = 32
    public static let sidebarTop: CGFloat = 52
    public static let selectionInset: CGFloat = 10
    public static let selectionRadius: CGFloat = 7
    public static let symbolCenterX: CGFloat = 29
    public static let symbolPointSize: CGFloat = 14
    public static let sidebarLabelX: CGFloat = 47

    public static let cardInset: CGFloat = 20
    public static var cardWidth: CGFloat { windowSize.width - detailX - 2 * cardInset }
    public static let cardRadius: CGFloat = 12
    public static let rowHeight: CGFloat = 37.5
    public static let separatorHeight: CGFloat = 1
    public static let separatorInset: CGFloat = 10
    public static let labelInset: CGFloat = 10
    public static let controlInset: CGFloat = 10
    public static let popUpCircleInset: CGFloat = 13.5
    public static let popUpCircle: CGFloat = 20
    public static let popUpTextGap: CGFloat = 13
    public static let helpFontSize: CGFloat = 11
    public static let helpLinePitch: CGFloat = 14
    public static let helpBaselineGap: CGFloat = 19
    public static var helpWidth: CGFloat { cardWidth - labelInset - 64 }
    public static let headerToCard: CGFloat = 22.5
    public static let cardToHeader: CGFloat = 33
    public static let firstHeaderCapTop: CGFloat = 76
    public static let fontSize: CGFloat = 13
}

public enum SettingsPaletteHex {
    public typealias Pair = (light: UInt32, dark: UInt32)
    public static let sidebar: Pair = (0xEDEDED, 0x2B2B2B)
    public static let divider: Pair = (0xD4D4D4, 0x111111)
    public static let detail: Pair = (0xFFFFFF, 0x1E1E1E)
    public static let card: Pair = (0xF7F7F7, 0x2A2A2A)
    public static let separator: Pair = (0xEBEBEB, 0x3A3A3A)
    public static let selection: Pair = (0x0070F5, 0x0A62D9)
    public static let symbol: Pair = (0x0575FA, 0x3D8EF7)
    public static let title: Pair = (0x4D4D4D, 0xC4C4C4)
    public static let label: Pair = (0x262626, 0xE3E3E3)
    public static let header: Pair = (0x272727, 0xE8E8E8)
    public static let help: Pair = (0x7C7C7C, 0x969696)
    public static let capsuleFill: Pair = (0xFAFAFA, 0x353535)
    public static let capsuleRim: Pair = (0xE2E2E2, 0x4A4A4A)
    public static let capsuleDivider: Pair = (0xC8C8C8, 0x555555)
    public static let chevron: Pair = (0x4D4D4D, 0xD8D8D8)
    public static let chevronDisabled: Pair = (0xAEAEAE, 0x6E6E6E)
    public static let popUpCircle: Pair = (0xE5E5E5, 0x434343)
    public static let popUpChevron: Pair = (0x232323, 0xE6E6E6)
    public static let switchOff: Pair = (0xDDDDDD, 0x4C4C4C)
}
