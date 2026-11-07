import SwiftUI

#if PHONE
let hsSide = "phone"
#else
let hsSide = "watch"
#endif

@main
struct HealthSimApp: App {
    init() { HSStart(CommandLine.arguments, hsSide) }
    var body: some Scene {
        WindowGroup { Text("HealthSim \(hsSide)") }
    }
}
