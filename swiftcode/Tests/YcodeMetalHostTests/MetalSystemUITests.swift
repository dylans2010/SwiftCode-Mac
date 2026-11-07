import Testing
@testable import YcodeMetalHost

@Suite struct MetalSystemUITests {
    @Test func renderServerAndSpringBoardByLabel() {
        #expect(MetalSystemUI.isSystemUI(label: "com.apple.backboardd", executablePath: nil))
        #expect(MetalSystemUI.isSystemUI(label: "com.apple.SpringBoard", executablePath: ""))
    }

    @Test func byExecutablePathWhenTheLabelIsMissing() {
        #expect(MetalSystemUI.isSystemUI(label: "", executablePath: "/usr/libexec/backboardd"))
        #expect(MetalSystemUI.isSystemUI(label: nil, executablePath: "/System/Library/CoreServices/SpringBoard.app/SpringBoard"))
        #expect(MetalSystemUI.isSystemUI(label: nil, executablePath: "/rt/RuntimeRoot/usr/libexec/backboardd"))
    }

    @Test func appsAndExtensionsAreNot() {
        #expect(!MetalSystemUI.isSystemUI(label: "com.apple.MercuryPoster.55F66599-1BF4-918D-8214-D63264716981",
                                          executablePath: "/System/Library/PrivateFrameworks/X.framework/PlugIns/MercuryPosterExtension.appex/MercuryPosterExtension"))
        #expect(!MetalSystemUI.isSystemUI(label: "UIKitApplication:com.apple.Preferences[a1b2]",
                                          executablePath: "/Applications/Preferences.app/Preferences"))
        #expect(!MetalSystemUI.isSystemUI(label: "com.example.backboardd", executablePath: "/usr/local/bin/backboardd"))
        #expect(!MetalSystemUI.isSystemUI(label: nil, executablePath: "/Applications/SpringBoard.app/SpringBoard"))
        #expect(!MetalSystemUI.isSystemUI(label: nil, executablePath: nil))
    }
}
