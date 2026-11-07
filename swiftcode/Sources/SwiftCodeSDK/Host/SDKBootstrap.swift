import Foundation

@MainActor
public enum SDKBootstrap {
    private static var bootstrapped = false

    public static func bootstrapIfNeeded() async {
        guard !bootstrapped else { return }
        SDKViewOpenerBuiltIns.registerBuiltInOpeners()
        SDKAssistUIOpener.registerAssistViewOpener()
        await SDKExtensionRegistry.shared.scan()
        bootstrapped = true
    }
}
