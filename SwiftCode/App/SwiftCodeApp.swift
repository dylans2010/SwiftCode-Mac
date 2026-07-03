import SwiftUI

@main
struct SwiftCodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var themeVM = ThemeViewModel()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(themeVM)
        }
        .commands {
            AppCommands()
        }
    }
}
