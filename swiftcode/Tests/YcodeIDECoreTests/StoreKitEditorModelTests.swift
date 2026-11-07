import Foundation
import StoreKitConfiguration
import Testing
@testable import YcodeIDECore

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/StoreKit")

@MainActor
private func makeModel() -> StoreKitEditorModel {
    StoreKitEditorModel(simulationCacheDirectory: tempDir())
}

private func tempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@MainActor
struct StoreKitEditorModelTests {
    @Test("A real .storekit file parses, edits, encodes and parses again")
    func roundTripParseEditEncodeParse() throws {
        let model = try StoreKitEditorModel(url: fixtures.appendingPathComponent("Basic.storekit"), simulationCacheDirectory: tempDir())
        #expect(model.configuration.identifier == "A1B2C3D4")
        #expect(model.allProducts.count == 5)
        #expect(model.isValid)
        #expect(model.healthScore == 100)

        let coins = model.allProducts.first { $0.product.productID == "com.example.coins100" }!
        var edited = coins.product
        edited.referenceName = "200 Coins"
        model.setProduct(edited, at: coins.location)
        let added = model.addProduct(kind: .consumable)
        #expect(model.product(at: added)?.displayPrice == "0.99")
        let groupIndex = model.addGroup(name: "Extra")
        let sub = try #require(model.addSubscription(to: groupIndex))
        #expect(model.product(at: sub)?.subscriptionGroupID == model.configuration.subscriptionGroups?[groupIndex].id)

        let dir = tempDir()
        let out = dir.appendingPathComponent("Out.storekit")
        try model.save(to: out)
        let reparsed = try StoreConfiguration(contentsOf: out)
        #expect(reparsed.products?.first { $0.productID == "com.example.coins100" }?.referenceName == "200 Coins")
        #expect(reparsed.products?.count == 3)
        #expect(reparsed.subscriptionGroups?.count == 2)
        #expect(reparsed.subscriptionGroups?.last?.subscriptions?.first?.type == .recurringSubscription)
        #expect(reparsed.extra["customVendorKey"] == .string("kept"))
    }

    @Test("Writing an unmodified file reproduces its bytes")
    func unmodifiedWriteIsByteStable() throws {
        let url = fixtures.appendingPathComponent("Basic.storekit")
        let original = try Data(contentsOf: url)
        let model = try StoreKitEditorModel(url: url)
        #expect(model.data() == original)
    }

    @Test("Unknown keys survive a parse → edit → encode → parse cycle")
    func unknownKeysSurviveRoundTrip() throws {
        let model = try StoreKitEditorModel(url: fixtures.appendingPathComponent("Basic.storekit"), simulationCacheDirectory: tempDir())
        model.addProduct()
        let dir = tempDir()
        let out = dir.appendingPathComponent("Out.storekit")
        try model.save(to: out)
        let reparsed = try StoreConfiguration(contentsOf: out)
        #expect(reparsed.extra["customVendorKey"] == .string("kept"))
    }

    @Test("The fixture is a valid configuration")
    func fixtureIsValid() throws {
        let model = try StoreKitEditorModel(url: fixtures.appendingPathComponent("Basic.storekit"), simulationCacheDirectory: tempDir())
        #expect(model.validationIssues().isEmpty)
        #expect(model.errors.isEmpty)
    }

    @Test("Adding, removing and duplicating products")
    func addRemoveDuplicateProduct() throws {
        let model = makeModel()
        #expect(model.allProducts.isEmpty)
        let loc = model.addProduct(kind: .nonConsumable)
        #expect(model.allProducts.count == 1)
        let copy = try #require(model.duplicateProduct(at: loc))
        #expect(model.allProducts.count == 2)
        #expect(model.product(at: copy)?.productID != model.product(at: loc)?.productID)
        #expect(model.product(at: copy)?.internalID != model.product(at: loc)?.internalID)
        model.removeProduct(at: copy)
        #expect(model.allProducts.count == 1)
        model.removeProduct(at: loc)
        #expect(model.allProducts.isEmpty)
    }

    @Test("Groups and subscriptions link by numeric group id")
    func addGroupAndSubscription() throws {
        let model = makeModel()
        let g = model.addGroup(name: "Pro")
        let first = try #require(model.addSubscription(to: g))
        let second = try #require(model.addSubscription(to: g))
        #expect(model.product(at: first)?.groupNumber == 1)
        #expect(model.product(at: second)?.groupNumber == 2)
        #expect(model.product(at: second)?.subscriptionGroupID == model.configuration.subscriptionGroups?[g].id)
        #expect(model.nextGroupID() == "2")
        model.removeGroup(at: g)
        #expect(model.configuration.subscriptionGroups?.isEmpty == true)
    }

    @Test("Offers and localizations can be added")
    func addOffersAndLocalization() throws {
        let model = try StoreKitEditorModel(url: fixtures.appendingPathComponent("Basic.storekit"), simulationCacheDirectory: tempDir())
        let monthly = model.allProducts.first { $0.product.productID == "com.example.pro_monthly" }!
        model.addOffer(to: monthly.location, kind: .promotional)
        #expect(model.product(at: monthly.location)?.adHocOffers?.count == 2)
        model.addLocalization(locale: "fr_FR", to: monthly.location)
        #expect(model.product(at: monthly.location)?.localizations?.contains { $0.locale == "fr_FR" } == true)
        #expect(model.localizationRows.count == 7)
    }

    @Test("Undo and redo restore configurations")
    func undoRedo() throws {
        let model = makeModel()
        model.addProduct()
        #expect(model.allProducts.count == 1)
        #expect(model.canUndo)
        model.undo()
        #expect(model.allProducts.isEmpty)
        #expect(model.canRedo)
        model.redo()
        #expect(model.allProducts.count == 1)
    }

    @Test("A duplicate product id is found and the fix renames it")
    func duplicateProductIDValidationAndFix() throws {
        let model = try StoreKitEditorModel(url: fixtures.appendingPathComponent("Basic.storekit"), simulationCacheDirectory: tempDir())
        let loc = model.addProduct()
        var copy = try #require(model.product(at: loc))
        copy.productID = "com.example.coins100"
        model.setProduct(copy, at: loc)
        let issues = model.validationIssues()
        #expect(issues.contains { $0.rule == "product.id.duplicate" })
        #expect(model.healthScore < 100)
        let issue = try #require(issues.first { $0.rule == "product.id.duplicate" })
        #expect(issue.fix == .fixDuplicateIdentifier)
        #expect(model.applyFix(.fixDuplicateIdentifier, at: issue.path))
        #expect(!model.validationIssues().contains { $0.rule == "product.id.duplicate" })
    }

    @Test("The health score follows Legacy's weights")
    func healthScore() throws {
        let model = makeModel()
        #expect(model.healthScore == 100)
        let loc = model.addProduct()
        var product = try #require(model.product(at: loc))
        product.localizations = [Localization(locale: "en_US", displayName: "", description: "x")]
        model.setProduct(product, at: loc)
        #expect(model.healthScore == 92)
    }

    @Test("A missing display name is generated by its fix")
    func missingLocalizationFix() throws {
        let model = makeModel()
        let loc = model.addProduct()
        var product = try #require(model.product(at: loc))
        product.localizations = [Localization(locale: "en_US", displayName: "", description: "x")]
        model.setProduct(product, at: loc)
        let issue = try #require(model.validationIssues().first { $0.rule == "localization.displayName.missing" })
        #expect(issue.fix == .generateMissingLocalization)
        #expect(model.applyFix(.generateMissingLocalization, at: issue.path))
        #expect(model.product(at: loc)?.localizations?.first?.displayName == "New Product")
    }

    @Test("Every starter template is a valid configuration")
    func templatesAreValid() throws {
        for name in StoreKitEditorModel.templateNames {
            let model = makeModel()
            model.applyTemplate(named: name)
            #expect(model.errors.isEmpty, "template \(name) has errors: \(model.errors.map(\.message))")
            #expect(!model.allProducts.isEmpty, "template \(name) has no products")
        }
    }

    @Test("The default workspace is valid")
    func defaultWorkspaceIsValid() throws {
        let model = makeModel()
        model.loadDefaultWorkspace()
        #expect(model.errors.isEmpty)
        #expect(model.allProducts.count == 3)
        #expect(model.configuration.subscriptionGroups?.count == 1)
    }

    @Test("A synchronized file is read-only")
    func synchronizedFileIsReadOnly() throws {
        let model = try StoreKitEditorModel(url: fixtures.appendingPathComponent("Synchronized.storekit"), simulationCacheDirectory: tempDir())
        #expect(model.configuration.isSynchronized)
        #expect(model.isReadOnly)
        model.addProduct()
        #expect(model.allProducts.count == 1)
        #expect(model.problem != nil)
    }

    @Test("Legacy-schema files import with a report")
    func legacyImport() throws {
        let data = try Data(contentsOf: fixtures.appendingPathComponent("LegacySchema.storekit"))
        let (config, report) = try StoreKitLegacyImport.importConfiguration(data: data)
        #expect(config.products?.first?.productID == "com.example.legacy_coins")
        #expect(config.products?.first?.displayPrice == "0.99")
        #expect(config.products?.first?.internalID != nil)
        let group = try #require(config.subscriptionGroups?.first)
        #expect(group.id?.allSatisfy { $0.isNumber } == true)
        let sub = try #require(group.subscriptions?.first)
        #expect(sub.type == .recurringSubscription)
        #expect(sub.subscriptionGroupID == group.id)
        #expect(sub.groupNumber == 1)
        #expect(sub.introductoryOffer?.paymentMode == .free)
        #expect(sub.codeOffers?.first?.referenceName == "LEGACY10")
        #expect(sub.codeOffers?.first?.eligibility == ["new"])
        #expect(report.droppedAnything)
        #expect(report.notes.contains { $0.contains("expiration date") })
        #expect(report.notes.contains { $0.contains("time rate") })
        let issues = config.validate()
        #expect(issues.count == 2)
        #expect(issues.contains { $0.rule == "identifier.format" })
        #expect(issues.contains { $0.rule == "settings.gracePeriod" })
    }

    @Test("Comparing configurations finds added, removed and changed products")
    func difference() throws {
        let model = try StoreKitEditorModel(url: fixtures.appendingPathComponent("Basic.storekit"), simulationCacheDirectory: tempDir())
        var other = model.configuration
        other.products?.removeAll { $0.productID == "com.example.coins100" }
        other.products?[0].displayPrice = "1.99"
        let diff = model.difference(from: other)
        #expect(diff.addedProductIDs == ["com.example.coins100"])
        #expect(diff.changedProductIDs.contains("com.example.lifetime"))
        #expect(diff.priceChanges.first?.productID == "com.example.lifetime")
    }

    @Test("Snapshots save and restore")
    func snapshotRestore() throws {
        let model = try StoreKitEditorModel(url: fixtures.appendingPathComponent("Basic.storekit"), simulationCacheDirectory: tempDir())
        model.snapshot(reason: "Before edit")
        #expect(model.snapshots.count == 1)
        model.addProduct()
        #expect(model.allProducts.count == 6)
        model.restore(model.snapshots[0])
        #expect(model.allProducts.count == 5)
    }

    @Test("Smart filters match by price and type")
    func smartFilter() throws {
        let filter = StoreKitSmartFilter(name: "Expensive", minPrice: Decimal(10), productType: "NonConsumable")
        let model = try StoreKitEditorModel(url: fixtures.appendingPathComponent("Basic.storekit"), simulationCacheDirectory: tempDir())
        let lifetime = model.allProducts.first { $0.product.productID == "com.example.lifetime" }!.product
        let coins = model.allProducts.first { $0.product.productID == "com.example.coins100" }!.product
        #expect(filter.matches(lifetime))
        #expect(!filter.matches(coins))
    }

    @Test("Raw JSON text round-trips through the model")
    func rawJSONText() throws {
        let model = try StoreKitEditorModel(url: fixtures.appendingPathComponent("Basic.storekit"), simulationCacheDirectory: tempDir())
        let text = model.jsonText()
        #expect(text.contains("\"identifier\" : \"A1B2C3D4\""))
        try model.setJSONText(text)
        #expect(model.configuration.identifier == "A1B2C3D4")
        #expect(throws: ConfigurationReadError.self) {
            try model.setJSONText("{ not json")
        }
    }

    @Test("Internal ids keep increasing")
    func nextInternalID() throws {
        let model = try StoreKitEditorModel(url: fixtures.appendingPathComponent("Basic.storekit"), simulationCacheDirectory: tempDir())
        #expect(model.nextInternalID() == "15")
    }

    @Test("Buying a consumable records a transaction and an entitlement")
    func simulationPurchase() throws {
        let model = makeModel()
        let loc = model.addProduct(kind: .consumable)
        let product = try #require(model.product(at: loc))
        model.simulation.executePurchase(product: product)
        #expect(model.simulation.transactions.count == 1)
        #expect(model.simulation.transactions[0].purchaseState == "purchased")
        #expect(model.simulation.entitlements.count == 1)
        #expect(model.simulation.entitlements[0].isActive)
        #expect(model.simulation.entitlements[0].expirationDate == nil)
    }

    @Test("Buying a subscription sets an expiry from its renewal period")
    func simulationSubscriptionExpiry() throws {
        let model = makeModel()
        let g = model.addGroup()
        let loc = try #require(model.addSubscription(to: g, period: "P1M"))
        let product = try #require(model.product(at: loc))
        model.simulation.executePurchase(product: product)
        let expiry = try #require(model.simulation.entitlements[0].expirationDate)
        let days = expiry.timeIntervalSinceNow / 86400
        #expect(days > 29 && days <= 30)
    }

    @Test("Ask to Buy leaves the transaction pending until approved")
    func simulationAskToBuy() throws {
        let model = makeModel()
        model.simulation.isAskToBuyEnabled = true
        let loc = model.addProduct()
        let product = try #require(model.product(at: loc))
        model.simulation.executePurchase(product: product)
        #expect(model.simulation.transactions[0].purchaseState == "pending")
        #expect(model.simulation.entitlements.isEmpty)
        model.simulation.approvePendingTransaction(id: model.simulation.transactions[0].id)
        #expect(model.simulation.transactions[0].purchaseState == "purchased")
        #expect(model.simulation.entitlements.count == 1)
    }

    @Test("Offline mode blocks purchases")
    func simulationOfflineBlocks() throws {
        let model = makeModel()
        model.simulation.isOfflineMode = true
        let loc = model.addProduct()
        model.simulation.executePurchase(product: try #require(model.product(at: loc)))
        #expect(model.simulation.transactions.isEmpty)
    }

    @Test("A refund revokes the entitlement")
    func simulationRefundRevokesEntitlement() throws {
        let model = makeModel()
        let loc = model.addProduct()
        let product = try #require(model.product(at: loc))
        model.simulation.executePurchase(product: product)
        model.simulation.triggerRefund(productID: product.productID!)
        #expect(model.simulation.transactions[0].purchaseState == "refunded")
        #expect(model.simulation.entitlements[0].isActive == false)
    }

    @Test("Renewal reactivates and expiration deactivates")
    func simulationRenewalAndExpiry() throws {
        let model = makeModel()
        let g = model.addGroup()
        let loc = try #require(model.addSubscription(to: g))
        let product = try #require(model.product(at: loc))
        model.simulation.executePurchase(product: product)
        model.simulation.simulateExpiration(productID: product.productID!)
        #expect(model.simulation.entitlements[0].isActive == false)
        #expect(model.simulation.transactions[0].subscriptionCycleState == "Expired")
        model.simulation.simulateRenewal(productID: product.productID!)
        #expect(model.simulation.entitlements[0].isActive)
        #expect(model.simulation.transactions[0].subscriptionCycleState == "Renewal")
    }

    @Test("The simulator's profiles apply their flags")
    func simulationProfiles() throws {
        let model = makeModel()
        #expect(model.simulation.availableProfiles.count == 4)
        let offline = model.simulation.availableProfiles.first { $0.name == "Offline Airplane Mode" }!
        model.simulation.applyProfile(offline)
        #expect(model.simulation.isOfflineMode)
        let child = model.simulation.availableProfiles.first { $0.name == "Child Sandbox Account" }!
        model.simulation.applyProfile(child)
        #expect(model.simulation.isAskToBuyEnabled)
        #expect(!model.simulation.isOfflineMode)
    }
}
