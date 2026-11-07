import Foundation

extension ProjectOptions {
    public init(form: TemplateOptionsForm) {
        self.init()
        productName = form.value(TemplateOptionID.productName)
        organizationIdentifier = form.value(TemplateOptionID.organizationIdentifier)
        team = form.value(TemplateOptionID.team).isEmpty ? "None" : form.value(TemplateOptionID.team)
        interface = Interface(rawValue: form.value(TemplateOptionID.interface)) ?? .swiftUI
        let t = form.value(TemplateOptionID.testingSystem)
        testing = Testing(rawValue: t) ?? (t == "None" ? .none : t.hasPrefix("XCTest") ? .xctest : .swiftTesting)
        setStorage(Storage(rawValue: form.value(TemplateOptionID.storage)) ?? .none)
        hostInCloudKit = form.bool(TemplateOptionID.hostInCloudKit)
        let d = form.value("deploymentTarget")
        deploymentTarget = d.isEmpty ? nil : d
    }
}

extension TemplateOptionsForm {
    public mutating func apply(_ o: ProjectOptions) {
        set(TemplateOptionID.productName, o.productName)
        set(TemplateOptionID.organizationIdentifier, o.organizationIdentifier)
        if field(TemplateOptionID.interface) != nil { set(TemplateOptionID.interface, o.interface.rawValue) }
        if let f = field(TemplateOptionID.testingSystem) {
            let plain: String = switch o.testing {
            case .none: "None"
            case .xctest: "XCTest"
            case .swiftTesting: "Swift Testing"
            }
            set(f.id, plain)
        }
        if field(TemplateOptionID.storage) != nil { set(TemplateOptionID.storage, o.storage.rawValue) }
        if field(TemplateOptionID.hostInCloudKit) != nil { set(TemplateOptionID.hostInCloudKit, o.hostInCloudKit ? "YES" : "NO") }
        if let d = o.deploymentTarget { set("deploymentTarget", d) }
    }
}

extension NewProjectFlowModel {
    public mutating func apply(_ o: ProjectOptions) {
        var f = form
        f.apply(o)
        for (k, v) in f.values { setOption(k, v) }
    }
}
