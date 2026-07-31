import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
public final class PreviewState {
    public var isDarkMode: Bool = false
    public var dynamicTypeSize: DynamicTypeSize = .medium
    public var localization: String = "en"
    public var isPortrait: Bool = true
    public var scale: Double = 1.0
    public var currentDevice: String = "iPhone 16 Pro"
    public var customWidth: Double? = nil
    public var customHeight: Double? = nil
    public var safeAreaInsets: EdgeInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)

    public init() {}
}
