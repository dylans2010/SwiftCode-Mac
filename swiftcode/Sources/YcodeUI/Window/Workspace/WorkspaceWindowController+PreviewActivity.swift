import AppKit
import YcodeBuild
import YcodeIDECore

struct PreviewActivityState {
    var text: String
    var savedStatus: String
    var savedBusy: Bool
    var generation: Int
}

extension WorkspaceWindowController {
    public static func previewFamily(platform: String?, destination: Destination?, simulators: [Destination]) -> String? {
        guard let platform, platform != "macOS" else { return nil }
        let sims = DestinationMenuModel.orderedSimulators(simulators.filter { $0.kind == .simulator && $0.platform == platform })
        let chosen = destination.flatMap { d in d.kind == .simulator && d.platform == platform ? d : nil } ?? sims.first
        return chosen.flatMap { family(ofDeviceNamed: $0.name) } ?? platform
    }

    static func family(ofDeviceNamed name: String) -> String? {
        let model: Set<String> = ["Pro", "Max", "Air", "mini", "SE", "Ultra", "Series", "Plus", "e"]
        var words: [Substring] = []
        for w in name.split(separator: " ") {
            if w.contains(where: \.isNumber) || model.contains(String(w)) || w.hasPrefix("(") { break }
            words.append(w)
        }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    public var previewActivityText: String? {
        guard session.model.kind != .package else { return nil }
        let simulators = session.model.destinationGroups.flatMap(\.destinations)
        return Self.previewFamily(platform: productPlatform.platform, destination: session.destination, simulators: simulators)
            .map { "Preparing \($0) Simulator" }
    }

    func beginPreviewActivity() -> Int? {
        guard let text = previewActivityText, !session.isBusy else { return nil }
        previewActivityGeneration += 1
        let g = previewActivityGeneration
        if var s = previewActivityState {
            s.text = text
            s.generation = g
            previewActivityState = s
        } else {
            previewActivityState = PreviewActivityState(text: text, savedStatus: activityView.status, savedBusy: activityView.isBusy, generation: g)
        }
        activityView.status = text
        activityView.isBusy = true
        return g
    }

    func endPreviewActivity(_ token: Int?) {
        guard let token, let s = previewActivityState, s.generation == token else { return }
        previewActivityState = nil
        guard activityView.status == s.text else { return }
        activityView.status = s.savedStatus
        activityView.isBusy = s.savedBusy || session.isBusy
    }
}
