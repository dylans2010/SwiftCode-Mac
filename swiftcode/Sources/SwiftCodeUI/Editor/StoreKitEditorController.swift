import AppKit
import StoreKitConfiguration
import SwiftCodeIDECore

final class StoreKitOutlineNode: NSObject {
    enum Kind { case section(StoreKitEditorSection); case product(StoreKitProductLocation); case group(Int) }
    let kind: Kind
    let title: String
    init(kind: Kind, title: String) {
        self.kind = kind
        self.title = title
    }
}

@MainActor
public final class StoreKitEditorController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate {
    public let url: URL
    public let model: StoreKitEditorModel
    private let outline = NSOutlineView()
    private let detailStack = NSStackView()
    private var productIDField = NSTextField()
    private var referenceNameField = NSTextField()
    private var priceField = NSTextField()
    private var typePopup = NSPopUpButton()
    private var familySharingCheck = NSButton(checkboxWithTitle: "Family Shareable", target: nil, action: nil)
    private var groupNameField = NSTextField()
    private var detailTitle = NSTextField(labelWithString: "No selection")

    public init(url: URL) throws {
        self.url = url
        model = try StoreKitEditorModel(url: url)
        super.init(nibName: nil, bundle: nil)
    }

    public init(model: StoreKitEditorModel, url: URL) {
        self.url = url
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 560))

        let column = NSTableColumn(identifier: .init("item"))
        column.title = "StoreKit"
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.dataSource = self
        outline.delegate = self
        outline.usesAlternatingRowBackgroundColors = true
        outline.rowSizeStyle = .small
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true

        detailStack.orientation = .vertical
        detailStack.alignment = .leading
        detailStack.spacing = 8
        detailStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        detailTitle.font = .boldSystemFont(ofSize: 13)
        detailStack.addArrangedSubview(detailTitle)
        for (label, field) in [("Product ID", productIDField), ("Reference Name", referenceNameField),
                               ("Display Price", priceField), ("Group Name", groupNameField)] {
            let row = NSStackView(views: [NSTextField(labelWithString: label), field])
            row.spacing = 8
            field.delegate = self
            field.font = .systemFont(ofSize: 12)
            field.widthAnchor.constraint(equalToConstant: 260).isActive = true
            detailStack.addArrangedSubview(row)
        }
        typePopup.addItems(withTitles: ["Consumable", "NonConsumable", "NonRenewingSubscription", "RecurringSubscription"])
        typePopup.target = self
        typePopup.action = #selector(typeChosen)
        let typeRow = NSStackView(views: [NSTextField(labelWithString: "Type"), typePopup])
        typeRow.spacing = 8
        detailStack.addArrangedSubview(typeRow)
        familySharingCheck.target = self
        familySharingCheck.action = #selector(familySharingToggled)
        detailStack.addArrangedSubview(familySharingCheck)
        let detailScroll = NSScrollView()
        detailScroll.documentView = detailStack
        detailScroll.hasVerticalScroller = true

        let split = NSSplitView()
        split.isVertical = true
        split.addArrangedSubview(scroll)
        split.addArrangedSubview(detailScroll)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 1)

        let addProduct = NSButton(title: "Add Product", target: self, action: #selector(addProductClicked))
        let addGroup = NSButton(title: "Add Group", target: self, action: #selector(addGroupClicked))
        let undoButton = NSButton(title: "Undo", target: self, action: #selector(undoClicked))
        let redoButton = NSButton(title: "Redo", target: self, action: #selector(redoClicked))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        for b in [addProduct, addGroup, undoButton, redoButton, saveButton] { b.bezelStyle = .rounded }
        let buttons = NSStackView(views: [addProduct, addGroup, undoButton, redoButton, saveButton])
        buttons.spacing = 8
        buttons.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)

        for v in [split, buttons] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: root.topAnchor),
            split.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -6),
            buttons.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6),
            buttons.heightAnchor.constraint(equalToConstant: 28),
        ])
        view = root
        reload()
    }

    func reload() {
        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
        refreshDetail()
    }

    func commit() {
        do { try model.save() } catch { presentError(error) }
    }

    private var sections: [StoreKitEditorSection] {
        [.products, .groups, .validation, .settings]
    }

    private func children(of node: StoreKitOutlineNode?) -> [StoreKitOutlineNode] {
        guard let node else {
            return sections.map { StoreKitOutlineNode(kind: .section($0), title: $0.rawValue) }
        }
        switch node.kind {
        case .section(.products):
            return model.allProducts.map { (loc, p) in
                StoreKitOutlineNode(kind: .product(loc), title: p.referenceName ?? p.productID ?? "Product")
            }
        case .section(.groups):
            return (model.configuration.subscriptionGroups ?? []).enumerated().map { (i, g) in
                StoreKitOutlineNode(kind: .group(i), title: g.name ?? g.id ?? "Group")
            }
        case .section(.validation):
            return model.validationIssues().map { issue in
                StoreKitOutlineNode(kind: .section(.validation), title: "\(issue.severity.rawValue): \(issue.message)")
            }
        default:
            return []
        }
    }

    public func outlineView(_ o: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        children(of: item as? StoreKitOutlineNode).count
    }

    public func outlineView(_ o: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        children(of: item as? StoreKitOutlineNode)[index]
    }

    public func outlineView(_ o: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? StoreKitOutlineNode else { return false }
        if case .section(.products) = node.kind { return !model.allProducts.isEmpty }
        if case .section(.groups) = node.kind { return !(model.configuration.subscriptionGroups ?? []).isEmpty }
        if case .section(.validation) = node.kind { return !model.validationIssues().isEmpty }
        return false
    }

    public func outlineView(_ o: NSOutlineView, viewFor c: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? StoreKitOutlineNode else { return nil }
        let f = NSTextField(labelWithString: node.title)
        f.font = .systemFont(ofSize: 12)
        return f
    }

    public func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let node = outline.item(atRow: outline.selectedRow) as? StoreKitOutlineNode else { return }
        switch node.kind {
        case .product(let loc):
            model.selectedProductID = model.product(at: loc)?.productID
            model.selectedGroupID = nil
        case .group(let i):
            model.selectedGroupID = model.configuration.subscriptionGroups?[i].id
            model.selectedProductID = nil
        default:
            break
        }
        refreshDetail()
    }

    private var selectedLocation: StoreKitProductLocation? {
        guard let id = model.selectedProductID else { return nil }
        return model.allProducts.first { $0.product.productID == id }?.location
    }

    private func refreshDetail() {
        if let loc = selectedLocation, let p = model.product(at: loc) {
            detailTitle.stringValue = p.referenceName ?? p.productID ?? "Product"
            productIDField.stringValue = p.productID ?? ""
            referenceNameField.stringValue = p.referenceName ?? ""
            priceField.stringValue = p.displayPrice ?? ""
            typePopup.selectItem(withTitle: p.type?.rawValue ?? "NonConsumable")
            familySharingCheck.state = (p.familyShareable ?? false) ? .on : .off
            groupNameField.stringValue = ""
        } else if let groupID = model.selectedGroupID,
                  let group = (model.configuration.subscriptionGroups ?? []).first(where: { $0.id == groupID }) {
            detailTitle.stringValue = group.name ?? "Group"
            productIDField.stringValue = group.id ?? ""
            referenceNameField.stringValue = ""
            priceField.stringValue = ""
            groupNameField.stringValue = group.name ?? ""
        } else {
            detailTitle.stringValue = "No selection"
            productIDField.stringValue = ""
            referenceNameField.stringValue = ""
            priceField.stringValue = ""
            groupNameField.stringValue = ""
        }
    }

    private func commitDetailFields() {
        guard let loc = selectedLocation, var product = model.product(at: loc) else {
            if let groupID = model.selectedGroupID,
               let index = (model.configuration.subscriptionGroups ?? []).firstIndex(where: { $0.id == groupID }) {
                model.mutate { c in
                    if var groups = c.subscriptionGroups, groups.indices.contains(index) {
                        groups[index].name = groupNameField.stringValue
                        c.subscriptionGroups = groups
                    }
                }
            }
            return
        }
        product.productID = productIDField.stringValue.isEmpty ? product.productID : productIDField.stringValue
        product.referenceName = referenceNameField.stringValue
        product.displayPrice = priceField.stringValue.isEmpty ? product.displayPrice : priceField.stringValue
        model.setProduct(product, at: loc)
        commit()
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        commitDetailFields()
        reload()
    }

    @objc private func typeChosen() {
        guard let loc = selectedLocation, var product = model.product(at: loc),
              let title = typePopup.titleOfSelectedItem else { return }
        product.type = ProductKind(rawValue: title)
        model.setProduct(product, at: loc)
        commit()
        reload()
    }

    @objc private func familySharingToggled() {
        guard let loc = selectedLocation, var product = model.product(at: loc) else { return }
        product.familyShareable = familySharingCheck.state == .on
        model.setProduct(product, at: loc)
        commit()
    }

    @objc private func addProductClicked() { _ = addProduct() }

    @discardableResult
    public func addProduct(kind: ProductKind = .nonConsumable) -> StoreKitProductLocation {
        let loc = model.addProduct(kind: kind)
        commit()
        reload()
        return loc
    }

    @objc private func addGroupClicked() { _ = addGroup() }

    @discardableResult
    public func addGroup() -> Int {
        let index = model.addGroup()
        commit()
        reload()
        return index
    }

    @objc private func undoClicked() { model.undo(); reload() }
    @objc private func redoClicked() { model.redo(); reload() }

    @objc private func saveClicked() { commit() }

    public var validationSummary: String {
        let issues = model.validationIssues()
        let errors = issues.filter { $0.severity == .error }.count
        let warnings = issues.filter { $0.severity == .warning }.count
        return "Health \(model.healthScore) — \(errors) errors, \(warnings) warnings"
    }
}
