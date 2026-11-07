import AppKit
import YcodeIDECore

extension DevicesController {
    public static let cameraTitles = ["Off", "Host webcam", "Synthetic pattern"]
    public static let cameraNote = "Applies the next time the simulator boots."

    public static func cameraSetting(_ defaults: UserDefaults) -> (get: () -> String, set: (String) -> Void) {
        (get: { RemoteSimulatorSettings.load(defaults).camera },
         set: { mode in
             var s = RemoteSimulatorSettings.load(defaults)
             s.camera = mode
             s.cameraChosen = true
             s.save(defaults)
         })
    }

    public var cameraControlsShown: Bool { selected?.isSwiftCodeRemote == true && cameraSetting != nil }

    public var cameraTitle: String {
        let mode = cameraSetting?.get() ?? "off"
        return RemoteSimulatorSettings.cameraModes.firstIndex(of: mode).map { Self.cameraTitles[$0] } ?? "Off"
    }

    public func chooseCamera(_ title: String) {
        guard let i = Self.cameraTitles.firstIndex(of: title), let cameraSetting else { return }
        cameraSetting.set(RemoteSimulatorSettings.cameraModes[i])
        if isViewLoaded { updateInspector() }
    }

    @objc func cameraChosen(_ sender: NSPopUpButton) {
        if let title = sender.titleOfSelectedItem { chooseCamera(title) }
    }

    func cameraControls() -> NSView {
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.addItems(withTitles: Self.cameraTitles)
        popUp.selectItem(withTitle: cameraTitle)
        popUp.target = self
        popUp.action = #selector(cameraChosen(_:))
        popUp.isBordered = false
        popUp.setAccessibilityLabel("Camera")
        popUp.toolTip = RemoteSimulatorSettings.cameraHelp
        let card = InspectorCard(rows: [.init(symbol: "camera", title: "Camera", control: popUp)], identifier: "camera-card")
        let note = NSTextField(wrappingLabelWithString: Self.cameraNote)
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = InspectorCard.width - 20
        let stack = NSStackView(views: [card, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stack.identifier = .init("camera-controls")
        return stack
    }
}
