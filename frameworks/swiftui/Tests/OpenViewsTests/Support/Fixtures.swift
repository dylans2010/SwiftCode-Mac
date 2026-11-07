import Foundation
#if OPENVIEWS_RENAMED
@testable import OpenViewsCore
@testable import OpenViews
#else
@testable import SwiftUICore
@testable import SwiftUI
#endif

enum Fixture {
    static let longText = "xxxx xxxx xxxx xxxx xxxx xxxx xxxx xxxx xxx"

    static func th(_ v: Double) -> CGFloat { (v * 3).rounded() / 3 }

    static let bodyWidths: [String: CGFloat] = [
        "Hello": 39,
        "World": 45,
        longText: 339,
        "A": th(11.33), "B": 11,
        "Left": th(29.67), "Right": 40,
        "Hi": 16,
        "Short": th(41.67), "Longer text": th(86.33),
        "Top": th(28.33), "Bottom": 56,
        "One": th(31.67), "Two": th(31.33),
        "Longer": th(53.33), "Wide cell": th(69.67),
        "X": th(11.33), "Fixed": th(40.67),
        "short": th(39.67),
        "short words here": th(128.67),
        "Tap": th(27.67),
        "SwiftCode": th(47.33),
        "Title": 33,
        "On": th(22.33),
        "S": th(10.67),
        "D": 12,
        "G": th(12.33),
        "Placeholder": 90,
        "Password": th(73.33),
        "Jan 1, 1970": th(98.67),
    ]

    static let measurer = TypesetTextMeasurer(fonts: ReferenceFontProvider())

    static let symbols = OpenSymbolProvider(missingSymbolsLayOutEmpty: true)

    static var engine: LayoutEngine { LayoutEngine(textMeasurer: measurer, symbols: symbols) }
}
