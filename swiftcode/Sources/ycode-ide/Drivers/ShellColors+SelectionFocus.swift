import SwiftUI

extension ShellColors {
    func onSelection(_ focused: Bool) -> ShellColors {
        var c = self
        c.onAccent = focused
        return c
    }
}
