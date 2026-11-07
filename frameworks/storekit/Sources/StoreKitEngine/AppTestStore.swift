import Foundation
import StoreKitConfiguration

struct PersistentState: Codable, Hashable {
    var nextID: UInt64 = 0
    var records: [TransactionRecord] = []
    var chains: [SubscriptionChain] = []
}

public final class AppTestStore: @unchecked Sendable {
    public let bundleID: String
    private weak var device: StoreDevice?
    private let clock: any StoreClock
    private let calendar: Calendar
    private let quirks: EngineQuirks
    private let directory: URL?

    private let lock = NSRecursiveLock()
    private var configuration: StoreConfiguration?
    private var catalogCache: Catalog?
    private var overrides = SettingsOverrides()
    private var state = PersistentState()
    private var observers: [UUID: @Sendable (StoreEvent) -> Void] = [:]
    private var pendingEvents: [StoreEvent] = []
    private var dirty = false

    init(bundleID: String, device: StoreDevice) {
        self.bundleID = bundleID
        self.device = device
        clock = device.clock
        calendar = device.calendar
        quirks = device.quirks
        directory = device.appDirectory(bundleID)
        load()
    }

    private func perform<T, E: Error>(_ body: () throws(E) -> T) throws(E) -> T {
        lock.lock()
        defer {
            let events = pendingEvents
            pendingEvents = []
            if dirty { save(); dirty = false }
            let targets = Array(observers.values)
            lock.unlock()
            for e in events { for o in targets { o(e) } }
        }
        catchUp()
        return try body()
    }

    private func emit(_ event: StoreEvent) { pendingEvents.append(event) }

    private func emit(_ record: TransactionRecord) { pendingEvents.append(.transaction(record)) }

    @discardableResult
    public func addObserver(_ observer: @escaping @Sendable (StoreEvent) -> Void) -> UUID {
        lock.withLock {
            let id = UUID()
            observers[id] = observer
            return id
        }
    }

    public func removeObserver(_ token: UUID) { lock.withLock { observers[token] = nil } }

    private var configurationURL: URL? { directory?.appendingPathComponent("Configuration.storekit") }
    private var stateURL: URL? { directory?.appendingPathComponent("store.json") }
    private var overridesURL: URL? { directory?.appendingPathComponent("overrides.json") }

    private func load() {
        guard let directory else { return }
        _ = directory
        if let url = configurationURL, let data = try? Data(contentsOf: url), let c = try? StoreConfiguration(data: data) {
            configuration = c
            catalogCache = Catalog(c)
        }
        let decoder = JSONDecoder()
        if let url = stateURL, let data = try? Data(contentsOf: url), let s = try? decoder.decode(PersistentState.self, from: data) {
            state = s
        }
        if let url = overridesURL, let data = try? Data(contentsOf: url), let o = try? decoder.decode(SettingsOverrides.self, from: data) {
            overrides = o
        }
    }

    private func save() {
        guard let directory else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        if let url = configurationURL {
            if let configuration { try? configuration.data().write(to: url, options: .atomic) }
            else if fm.fileExists(atPath: url.path) { try? fm.removeItem(at: url) }
        }
        if let url = stateURL, let data = try? encoder.encode(state) { try? data.write(to: url, options: .atomic) }
        if let url = overridesURL, let data = try? encoder.encode(overrides) { try? data.write(to: url, options: .atomic) }
    }

    private var now: StoreMilliseconds { clock.now().storeMilliseconds }

    public func installConfiguration(_ configuration: StoreConfiguration, appName: String? = nil) {
        perform {
            var copy = configuration
            if let appName { copy.appName = appName }
            self.configuration = copy
            catalogCache = Catalog(copy)
            dirty = true
            emit(.configurationChanged)
        }
    }

    public func removeConfiguration() {
        perform {
            configuration = nil
            catalogCache = nil
            dirty = true
            emit(.configurationChanged)
        }
    }

    public var installedConfiguration: StoreConfiguration? { lock.withLock { configuration } }

    public var catalog: Catalog? { lock.withLock { catalogCache } }

    public func uninstall() {
        perform {
            configuration = nil
            catalogCache = nil
            state = PersistentState()
            dirty = true
            emit(.configurationChanged)
        }
    }

    public var settings: EffectiveSettings { lock.withLock { effectiveSettings } }

    private var effectiveSettings: EffectiveSettings {
        let file = configuration?.settings
        var errors: [StoreAPI: SimulatedFailure] = [:]
        for (k, v) in overrides.simulatedErrors { if let api = StoreAPI(rawValue: k) { errors[api] = v } }
        return EffectiveSettings(
            storefront: Storefront.named(overrides.storefront ?? file?.storefront ?? "USA"),
            locale: overrides.locale ?? file?.locale ?? "en_US",
            timeRate: overrides.timeRate ?? file?.timeRate.flatMap(TimeRate.init(rawValue:)) ?? .realTime,
            askToBuyEnabled: overrides.askToBuyEnabled ?? file?.askToBuyEnabled ?? false,
            interruptedPurchasesEnabled: overrides.interruptedPurchasesEnabled ?? file?.billingIssuesEnabled ?? false,
            billingRetryOnRenewalEnabled: overrides.billingRetryOnRenewalEnabled ?? file?.renewalBillingIssuesEnabled ?? false,
            billingGracePeriodEnabled: overrides.billingGracePeriodEnabled ?? file?.billingGracePeriodEnabled ?? false,
            disableDialogs: overrides.disableDialogs ?? file?.disableDialogs ?? false,
            failTransactionsEnabled: overrides.failTransactionsEnabled ?? file?.failTransactionsEnabled ?? false,
            simulatedErrors: errors)
    }

    public var overrideSettings: SettingsOverrides {
        get { lock.withLock { overrides } }
        set {
            perform {
                let oldStorefront = effectiveSettings.storefront
                overrides = newValue
                dirty = true
                let sf = effectiveSettings.storefront
                if sf != oldStorefront { emit(.storefrontChanged(sf)) }
            }
        }
    }

    public func updateSettings(_ change: (inout SettingsOverrides) -> Void) {
        var o = overrideSettings
        change(&o)
        overrideSettings = o
    }

    public func resetToDefaultState() { overrideSettings = SettingsOverrides() }

    public func setSimulatedError(_ failure: SimulatedFailure?, for api: StoreAPI) {
        updateSettings { $0.simulatedErrors[api.rawValue] = failure }
    }

    public func simulatedError(for api: StoreAPI) -> SimulatedFailure? { settings.simulatedErrors[api] }

    public func advance() { perform {} }

    public func nextEventDate() -> Date? {
        lock.withLock { state.chains.compactMap(dueDate).min().map(Date.init(storeMilliseconds:)) }
    }

    private func periodEnd(_ d: SubscriptionDuration, count: Int = 1, from start: StoreMilliseconds) -> StoreMilliseconds {
        effectiveSettings.timeRate.end(of: d, count: count, from: start, calendar: calendar)
    }

    private func dueDate(_ c: SubscriptionChain) -> StoreMilliseconds? {
        switch c.state {
        case .subscribed: return c.expiresDate
        case .inGracePeriod: return c.gracePeriodExpiresDate
        case .inBillingRetryPeriod: return c.billingRetryEndDate
        case .expired, .revoked: return nil
        }
    }

    private func catchUp() {
        let limit = now
        var steps = 0
        while steps < 1_000_000 {
            var best: (index: Int, due: StoreMilliseconds)?
            for (i, c) in state.chains.enumerated() {
                guard let due = dueDate(c), due <= limit else { continue }
                if best == nil || due < best!.due { best = (i, due) }
            }
            guard let (i, due) = best else { return }
            process(chainAt: i, at: due)
            steps += 1
        }
    }

    private func process(chainAt i: Int, at t: StoreMilliseconds) {
        var c = state.chains[i]
        defer { state.chains[i] = c; dirty = true }
        switch c.state {
        case .subscribed:
            guard c.autoRenewEnabled else {
                c.state = .expired
                if c.expirationIntent == nil { c.expirationIntent = 1 }
                return
            }
            guard let next = catalogCache?.product(c.autoRenewProductID), next.subscription != nil else {
                c.state = .expired
                c.autoRenewEnabled = false
                c.expirationIntent = 4
                return
            }
            let s = effectiveSettings
            if s.billingRetryOnRenewalEnabled {
                c.hasBillingIssue = true
                if s.billingGracePeriodEnabled {
                    let r = renew(&c, product: next, at: t)
                    c.state = .inGracePeriod
                    c.gracePeriodExpiresDate = r.expiresDate
                    c.billingRetryEndDate = periodEnd(next.subscription!.period, from: r.expiresDate ?? t)
                } else {
                    c.state = .inBillingRetryPeriod
                    c.billingRetryEndDate = periodEnd(next.subscription!.period, from: t)
                }
                return
            }
            renew(&c, product: next, at: t)
        case .inGracePeriod:
            c.state = .inBillingRetryPeriod
            c.gracePeriodExpiresDate = nil
        case .inBillingRetryPeriod:
            c.state = .expired
            c.autoRenewEnabled = false
            c.expirationIntent = 2
            c.hasBillingIssue = false
            c.billingRetryEndDate = nil
        case .expired, .revoked:
            break
        }
    }

    @discardableResult
    private func renew(_ c: inout SubscriptionChain, product: CatalogProduct, at t: StoreMilliseconds) -> TransactionRecord {
        let sub = product.subscription!
        if product.id != c.productID { c.continuingOffer = nil }
        var applied: AppliedOffer?
        var duration = sub.period
        var count = 1
        if let pending = c.pendingOffer {
            applied = pending.offer
            duration = pending.billedPeriod
            if pending.offer.paymentMode == .payAsYouGo {
                c.continuingOffer = pending.remainingPeriods > 1
                    ? ContinuingOffer(offer: pending.offer, billedPeriod: pending.billedPeriod, remainingPeriods: pending.remainingPeriods - 1)
                    : nil
            } else {
                count = pending.remainingPeriods
                c.continuingOffer = nil
            }
            c.pendingOffer = nil
        } else if var cont = c.continuingOffer, cont.remainingPeriods > 0 {
            applied = cont.offer
            duration = cont.billedPeriod
            cont.remainingPeriods -= 1
            c.continuingOffer = cont.remainingPeriods > 0 ? cont : nil
        }
        let end = periodEnd(duration, count: count, from: t)
        var r = makeRecord(
            product: product, reason: .renewal, originalID: c.originalID, originalPurchaseDate: c.originalPurchaseDate,
            purchaseDate: t, expiresDate: end, quantity: 1, priceMilli: applied?.priceMilli ?? product.priceMilli,
            offer: applied, token: tokenOfChain(c))
        if let other = state.chains.first(where: {
            $0.originalID != c.originalID && $0.groupID == c.groupID && $0.isEntitled
                && (catalogCache?.product($0.productID)?.subscription?.level ?? Int.max) < sub.level
        }) {
            _ = other
            r.isUpgraded = true
            c.isUpgradedAway = true
            c.autoRenewEnabled = false
            c.state = .expired
        }
        state.records.append(r)
        c.productID = product.id
        c.currentTransactionID = r.id
        c.expiresDate = end
        emit(r)
        return r
    }

    private func tokenOfChain(_ c: SubscriptionChain) -> UUID? {
        state.records.first { $0.id == c.originalID }?.appAccountToken
    }

    private func makeRecord(
        product: CatalogProduct, reason: TransactionReason, originalID: UInt64?, originalPurchaseDate: StoreMilliseconds?,
        purchaseDate: StoreMilliseconds, expiresDate: StoreMilliseconds?, quantity: Int, priceMilli: Int,
        offer: AppliedOffer?, token: UUID?, reuseID: UInt64? = nil
    ) -> TransactionRecord {
        let id: UInt64
        if let reuseID { id = reuseID } else { id = state.nextID; state.nextID += 1 }
        let s = effectiveSettings
        dirty = true
        return TransactionRecord(
            id: id, originalID: originalID ?? id, productID: product.id, productType: product.type,
            subscriptionGroupID: product.subscription?.groupID, state: .purchased, reason: reason, isFinished: false,
            purchaseDate: purchaseDate, originalPurchaseDate: originalPurchaseDate ?? purchaseDate, expiresDate: expiresDate,
            quantity: quantity, priceMilli: priceMilli, currency: s.storefront.currency, storefront: s.storefront.countryCode,
            storefrontID: s.storefront.id, appAccountToken: token, offer: offer, isPendingAskToBuy: false,
            isAskToBuyDeclined: false, revocationDate: nil, revocationReason: nil, revocationType: nil,
            revocationPercentage: nil, hasPurchaseIssue: false, isUpgraded: false, pendingRequest: nil)
    }

    public func products(for ids: [String]) throws(StoreFailure) -> [CatalogProduct] {
        try perform { () throws(StoreFailure) -> [CatalogProduct] in
            if let f = effectiveSettings.simulatedErrors[.loadProducts] {
                throw StoreFailure(.systemError(.unknown), simulated: f)
            }
            guard let catalog = catalogCache else { return [] }
            var seen: Set<String> = []
            return ids.compactMap { id in
                guard seen.insert(id).inserted else { return nil }
                return catalog.product(id)
            }
        }
    }

    public func isEligibleForIntroOffer(groupID: String) -> Bool { perform { introEligible(groupID) } }

    private func introEligible(_ groupID: String) -> Bool {
        !state.records.contains {
            $0.subscriptionGroupID == groupID && $0.state != .deferred && !$0.isAskToBuyDeclined
        }
    }

    public func purchase(productID: String, options: PurchaseOptions = PurchaseOptions()) throws(StoreFailure) -> PurchaseOutcome {
        try perform { () throws(StoreFailure) -> PurchaseOutcome in try purchaseLocked(productID, options, offDevice: false) }
    }

    public func buyProduct(productID: String, options: PurchaseOptions = PurchaseOptions()) throws(TestSessionError) -> TransactionRecord {
        try perform { () throws(TestSessionError) -> TransactionRecord in
            guard catalogCache?.product(productID) != nil else {
                throw TestSessionError(.invalidProductIdentifier, "No product \(productID) in the configuration.")
            }
            do {
                let outcome = try purchaseLocked(productID, options, offDevice: true)
                guard let r = outcome.transaction else { throw TestSessionError(.invalidAction, "The purchase did not complete.") }
                emit(r)
                return r
            } catch let e as StoreFailure {
                throw TestSessionError(.invalidAction, "The purchase failed (\(e.kind)).")
            } catch let e as TestSessionError {
                throw e
            } catch {
                throw TestSessionError(.invalidAction, "\(error)")
            }
        }
    }

    static func cantCompleteAlert(_ reason: PurchaseFailureReason) -> StoreAlert {
        let text: String
        switch reason {
        case .invalidQuantity: text = "You can't buy more than 10 of this item at one time."
        case .productUnavailable: text = "This item is not available."
        case .purchaseNotAllowed: text = "Purchases are not allowed."
        case .ineligibleForOffer: text = "You are not eligible for this offer."
        default: text = "The purchase could not be completed."
        }
        return StoreAlert(title: "Can't Complete This Purchase", message: text)
    }

    static let unableToPurchaseAlert = StoreAlert(title: "Unable to Purchase", message: "Contact the developer for more information.")

    private func purchaseLocked(_ productID: String, _ options: PurchaseOptions, offDevice: Bool) throws(StoreFailure) -> PurchaseOutcome {
        guard let catalog = catalogCache, let p = catalog.product(productID) else { throw StoreFailure(.unknown) }
        let s = effectiveSettings
        if !offDevice, let f = s.simulatedErrors[.purchase] {
            if case .purchase(let reason) = f, [.productUnavailable, .purchaseNotAllowed, .ineligibleForOffer, .invalidQuantity].contains(reason) {
                throw StoreFailure(.unknown, alert: Self.cantCompleteAlert(reason), simulated: f)
            }
            throw StoreFailure(.unknown, simulated: f)
        }
        guard (1...10).contains(options.quantity) else {
            throw StoreFailure(.unknown, alert: Self.cantCompleteAlert(.invalidQuantity))
        }
        if let signed = options.signedPromotionalOffer {
            let context = PromotionalOfferContext(bundleID: bundleID, productID: productID, appAccountToken: options.appAccountToken)
            let ok = p.subscription?.promotionalOffers.contains { $0.identifier == signed.offerID } == true
                && (device?.promotionalOfferVerifier(signed, context) ?? false)
            guard ok else { throw StoreFailure(.unknown, alert: Self.unableToPurchaseAlert) }
        }
        let backdated = options.purchaseDate != nil
        switch p.type {
        case .consumable:
            if let r = state.records.last(where: {
                $0.productID == p.id && !$0.isFinished && $0.state == .purchased && !$0.isRevoked
            }) {
                return .success(r, isRedelivery: true)
            }
        case .nonConsumable:
            if let r = state.records.last(where: {
                $0.productID == p.id && ($0.state == .purchased || $0.state == .restored) && !$0.isRevoked
            }) {
                return .success(r, isRedelivery: true)
            }
        case .autoRenewable:
            if !backdated, let i = state.chains.firstIndex(where: { $0.groupID == p.subscription!.groupID && $0.isActive }) {
                return try changeActiveSubscription(chainAt: i, to: p, options: options)
            }
        case .nonRenewable:
            break
        }
        if s.askToBuyEnabled && !offDevice {
            var r = makeRecord(
                product: p, reason: .purchase, originalID: nil, originalPurchaseDate: nil, purchaseDate: now,
                expiresDate: nil, quantity: options.quantity, priceMilli: p.priceMilli, offer: nil,
                token: options.appAccountToken)
            r.state = .deferred
            r.isPendingAskToBuy = true
            r.pendingRequest = options
            state.records.append(r)
            return .pending(r)
        }
        if s.failTransactionsEnabled && !offDevice { throw StoreFailure(.unknown) }
        var r = try create(p, options: options, reuseID: nil)
        if s.interruptedPurchasesEnabled && !offDevice {
            r.state = .failed
            r.hasPurchaseIssue = true
            replace(r)
            emit(r)
            throw StoreFailure(.unknown, record: r)
        }
        return .success(r, isRedelivery: false)
    }

    private func replace(_ r: TransactionRecord) {
        if let i = state.records.firstIndex(where: { $0.id == r.id }) { state.records[i] = r } else { state.records.append(r) }
        dirty = true
    }

    private func codeEligible(_ offer: CatalogOffer, groupID: String) -> Bool {
        let chains = state.chains.filter { $0.groupID == groupID }
        if chains.contains(where: \.isActive) { return offer.eligibility.contains("existing") }
        if introEligible(groupID) { return offer.eligibility.contains("new") }
        return offer.eligibility.contains("expired")
    }

    private func applied(_ o: CatalogOffer) -> AppliedOffer {
        AppliedOffer(type: o.type, identifier: o.identifier, paymentMode: o.paymentMode, period: o.totalDuration, priceMilli: milliUnits(o.price))
    }

    private func planOffer(for p: CatalogProduct, options: PurchaseOptions) throws(StoreFailure) -> CatalogOffer? {
        let sub = p.subscription!
        let eligible = introEligible(sub.groupID)
        let intro = eligible ? sub.introductoryOffer : nil
        if let code = options.codeOfferReferenceName,
           let offer = sub.codeOffers.first(where: { $0.identifier == code }), codeEligible(offer, groupID: sub.groupID) {
            return offer
        }
        if let id = options.signedPromotionalOffer?.offerID ?? options.promotionalOfferID {
            if let intro { return intro }
            guard let promo = sub.promotionalOffers.first(where: { $0.identifier == id }) else {
                throw StoreFailure(.unknown, alert: Self.unableToPurchaseAlert)
            }
            return promo
        }
        return intro
    }

    private func create(_ p: CatalogProduct, options: PurchaseOptions, reuseID: UInt64?) throws(StoreFailure) -> TransactionRecord {
        let start = options.purchaseDate?.storeMilliseconds ?? now
        guard let sub = p.subscription else {
            let r = makeRecord(
                product: p, reason: .purchase, originalID: nil, originalPurchaseDate: nil, purchaseDate: start,
                expiresDate: nil, quantity: options.quantity, priceMilli: p.priceMilli, offer: nil,
                token: options.appAccountToken, reuseID: reuseID)
            replace(r)
            return r
        }
        let offer = try planOffer(for: p, options: options)
        var continuing: ContinuingOffer?
        var end: StoreMilliseconds
        if let offer {
            if offer.paymentMode == .payAsYouGo {
                end = periodEnd(offer.period, from: start)
                if offer.periodCount > 1 {
                    continuing = ContinuingOffer(offer: applied(offer), billedPeriod: offer.period, remainingPeriods: offer.periodCount - 1)
                }
            } else {
                end = periodEnd(offer.period, count: offer.periodCount, from: start)
            }
        } else {
            end = periodEnd(sub.period, from: start)
        }
        let r = makeRecord(
            product: p, reason: .purchase, originalID: nil, originalPurchaseDate: nil, purchaseDate: start,
            expiresDate: end, quantity: options.quantity, priceMilli: offer.map { milliUnits($0.price) } ?? p.priceMilli,
            offer: offer.map(applied), token: options.appAccountToken, reuseID: reuseID)
        replace(r)
        let cancel = options.purchaseDate != nil && options.renewalBehavior == .cancelImmediately
        state.chains.append(SubscriptionChain(
            originalID: r.id, groupID: sub.groupID, productID: p.id, autoRenewProductID: p.id,
            autoRenewEnabled: !cancel, expirationIntent: cancel ? 1 : nil, state: .subscribed, currentTransactionID: r.id,
            originalPurchaseDate: start, expiresDate: end, recentStartDate: start, gracePeriodExpiresDate: nil,
            billingRetryEndDate: nil, hasBillingIssue: false, continuingOffer: continuing, pendingOffer: nil,
            isUpgradedAway: false))
        if options.purchaseDate != nil { catchUp() }
        return state.records.first { $0.id == r.id } ?? r
    }

    private func changeActiveSubscription(chainAt i: Int, to p: CatalogProduct, options: PurchaseOptions) throws(StoreFailure)
        -> PurchaseOutcome
    {
        var c = state.chains[i]
        guard let current = state.records.first(where: { $0.id == c.currentTransactionID }) else {
            throw StoreFailure(.unknown)
        }
        let sub = p.subscription!
        if p.id == c.productID {
            if let code = options.codeOfferReferenceName,
               let offer = sub.codeOffers.first(where: { $0.identifier == code }), codeEligible(offer, groupID: sub.groupID) {
                c.pendingOffer = ContinuingOffer(offer: applied(offer), billedPeriod: offer.period, remainingPeriods: offer.periodCount)
            }
            c.autoRenewProductID = p.id
            state.chains[i] = c
            dirty = true
            return .success(current, isRedelivery: true)
        }
        let currentProduct = catalogCache?.product(c.productID)
        let currentLevel = currentProduct?.subscription?.level ?? Int.max
        let samePeriod = currentProduct?.subscription?.period == sub.period
        if sub.level < currentLevel || (sub.level == currentLevel && samePeriod) {
            var old = current
            old.isUpgraded = true
            replace(old)
            emit(old)
            let t = now
            let end = periodEnd(sub.period, from: t)
            let r = makeRecord(
                product: p, reason: .purchase, originalID: c.originalID, originalPurchaseDate: c.originalPurchaseDate,
                purchaseDate: t, expiresDate: end, quantity: options.quantity, priceMilli: p.priceMilli, offer: nil,
                token: options.appAccountToken ?? current.appAccountToken)
            state.records.append(r)
            c.productID = p.id
            c.autoRenewProductID = p.id
            c.currentTransactionID = r.id
            c.expiresDate = end
            c.continuingOffer = nil
            c.pendingOffer = nil
            c.state = .subscribed
            c.hasBillingIssue = false
            c.gracePeriodExpiresDate = nil
            c.billingRetryEndDate = nil
            state.chains[i] = c
            return .success(r, isRedelivery: false)
        }
        c.autoRenewProductID = p.id
        state.chains[i] = c
        dirty = true
        return .success(current, isRedelivery: true)
    }

    public func finish(transactionID: UInt64) {
        perform {
            guard let i = state.records.firstIndex(where: { $0.id == transactionID }) else { return }
            state.records[i].isFinished = true
            dirty = true
        }
    }

    public func allTransactions() -> [TransactionRecord] { perform { state.records.sorted { $0.id < $1.id } } }

    private func isListed(_ r: TransactionRecord) -> Bool {
        if r.state == .deferred { return false }
        if r.isAskToBuyDeclined && !quirks.declinedAskToBuyIsDelivered { return false }
        return true
    }

    public func transactionHistory() -> [TransactionRecord] {
        perform {
            state.records.filter { isListed($0) && !($0.productType == .consumable && $0.isFinished) }.sorted { $0.id > $1.id }
        }
    }

    public func unfinishedTransactions() -> [TransactionRecord] {
        perform { state.records.filter { isListed($0) && !$0.isFinished }.sorted { $0.id > $1.id } }
    }

    public func latestTransaction(for productID: String) -> TransactionRecord? {
        perform { state.records.filter { $0.productID == productID && isListed($0) }.max { $0.id < $1.id } }
    }

    public func transaction(_ id: UInt64) -> TransactionRecord? { perform { state.records.first { $0.id == id } } }

    private func isEntitling(_ r: TransactionRecord) -> Bool {
        !r.isRevoked && !r.isUpgraded && (r.state == .purchased || r.state == .restored || (r.state == .failed && r.hasPurchaseIssue))
    }

    public func currentEntitlements() -> [TransactionRecord] {
        perform {
            var out: [TransactionRecord] = []
            var products: Set<String> = []
            for r in state.records.sorted(by: { $0.id > $1.id })
            where (r.productType == .nonConsumable || r.productType == .nonRenewable) && isEntitling(r) {
                if products.insert(r.productID).inserted { out.append(r) }
            }
            for c in state.chains where c.isEntitled {
                if let r = state.records.first(where: { $0.id == c.currentTransactionID }), isEntitling(r) { out.append(r) }
            }
            return out.sorted { $0.id > $1.id }
        }
    }

    public func subscriptionStatuses(groupID: String) -> [SubscriptionStatusSnapshot] {
        perform {
            if effectiveSettings.simulatedErrors[.subscriptionStatus] != nil { return [] }
            return state.chains.filter { $0.groupID == groupID }.sorted { $0.originalID > $1.originalID }.compactMap(status)
        }
    }

    public func subscriptionStatus(forTransaction id: UInt64) -> SubscriptionStatusSnapshot? {
        perform {
            guard let r = state.records.first(where: { $0.id == id }),
                  let c = state.chains.first(where: { $0.originalID == r.originalID }) else { return nil }
            return status(c)
        }
    }

    private func status(_ c: SubscriptionChain) -> SubscriptionStatusSnapshot? {
        guard let r = state.records.first(where: { $0.id == c.currentTransactionID }) else { return nil }
        return SubscriptionStatusSnapshot(state: c.state, transaction: r, renewal: renewalSnapshot(c))
    }

    private func renewalSnapshot(_ c: SubscriptionChain) -> RenewalSnapshot {
        let next = c.pendingOffer ?? c.continuingOffer
        let nextProduct = catalogCache?.product(c.autoRenewProductID)
        let renewing = c.autoRenewEnabled && c.state != .expired && c.state != .revoked
        return RenewalSnapshot(
            originalTransactionID: c.originalID, productID: c.productID, autoRenewProductID: c.autoRenewProductID,
            autoRenewStatus: renewing ? 1 : 0, renewalDate: c.state == .revoked ? nil : c.expiresDate,
            renewalPriceMilli: next?.offer.priceMilli ?? nextProduct?.priceMilli,
            renewalBillingPlanType: renewing ? "BILLED_UPFRONT" : nil, recentSubscriptionStartDate: c.recentStartDate,
            isInBillingRetryPeriod: c.state == .inBillingRetryPeriod || c.state == .inGracePeriod,
            gracePeriodExpiresDate: c.state == .inGracePeriod ? c.gracePeriodExpiresDate : nil,
            expirationIntent: renewing ? nil : c.expirationIntent, pendingOffer: c.pendingOffer?.offer,
            currency: effectiveSettings.storefront.currency, eligibleWinBackOfferIDs: [])
    }

    public func checkAppTransaction() throws(StoreFailure) {
        try perform { () throws(StoreFailure) in
            guard configuration != nil else { throw StoreFailure(.systemError(.noAccount)) }
            if let f = effectiveSettings.simulatedErrors[.appTransaction] { throw StoreFailure(.systemError(.unknown), simulated: f) }
        }
    }

    public func sync() throws(StoreFailure) {
        try perform { () throws(StoreFailure) in
            if let f = effectiveSettings.simulatedErrors[.appStoreSync] { throw StoreFailure(.systemError(.unknown), simulated: f) }
        }
    }

    public func checkSimulatedError(for api: StoreAPI) throws(StoreFailure) {
        try perform { () throws(StoreFailure) in
            guard let f = effectiveSettings.simulatedErrors[api] else { return }
            switch f {
            case .generic(.userCancelled): throw StoreFailure(.userCancelled, simulated: f)
            case .generic(.networkError(let code)): throw StoreFailure(.networkError(code: code), simulated: f)
            case .generic(.notEntitled): throw StoreFailure(.notEntitled, simulated: f)
            case .generic(.unsupported): throw StoreFailure(.unsupported, simulated: f)
            case .generic(.notAvailableInStorefront): throw StoreFailure(.notAvailableInStorefront, simulated: f)
            case .generic(.systemError): throw StoreFailure(.systemError(.unknown), simulated: f)
            default: throw StoreFailure(.unknown, simulated: f)
            }
        }
    }

    public func restoreCompletedTransactions() -> [TransactionRecord] {
        perform {
            guard let catalog = catalogCache else { return [] }
            var out: [TransactionRecord] = []
            var done: Set<String> = []
            for r in state.records.sorted(by: { $0.id > $1.id }) where r.productType == .nonConsumable && isEntitling(r) {
                guard done.insert(r.productID).inserted, let p = catalog.product(r.productID) else { continue }
                var n = makeRecord(
                    product: p, reason: .renewal, originalID: r.originalID, originalPurchaseDate: r.originalPurchaseDate,
                    purchaseDate: now, expiresDate: nil, quantity: r.quantity, priceMilli: r.priceMilli, offer: nil,
                    token: r.appAccountToken)
                n.state = .restored
                state.records.append(n)
                out.append(n)
            }
            for i in state.chains.indices where state.chains[i].isEntitled {
                let c = state.chains[i]
                guard let cur = state.records.first(where: { $0.id == c.currentTransactionID }),
                      let p = catalog.product(cur.productID) else { continue }
                var n = makeRecord(
                    product: p, reason: .renewal, originalID: c.originalID, originalPurchaseDate: c.originalPurchaseDate,
                    purchaseDate: cur.purchaseDate, expiresDate: cur.expiresDate, quantity: cur.quantity,
                    priceMilli: cur.priceMilli, offer: cur.offer, token: cur.appAccountToken)
                n.state = .restored
                state.records.append(n)
                state.chains[i].currentTransactionID = n.id
                out.append(n)
            }
            for r in out { emit(r) }
            return out
        }
    }

    private func recordIndex(_ id: UInt64) throws(TestSessionError) -> Int {
        guard let i = state.records.firstIndex(where: { $0.id == id }) else {
            throw TestSessionError(.noTransactionFound, "No transaction \(id).")
        }
        return i
    }

    private func chainIndex(containing id: UInt64) throws(TestSessionError) -> Int {
        let i = try recordIndex(id)
        let r = state.records[i]
        guard r.productType == .autoRenewable, let c = state.chains.firstIndex(where: { $0.originalID == r.originalID }) else {
            throw TestSessionError(.invalidProductType, "Transaction \(id) is not an auto-renewable subscription.")
        }
        return c
    }

    private func activeChainIndex(product id: String) throws(TestSessionError) -> Int {
        guard let p = catalogCache?.product(id) else { throw TestSessionError(.invalidProductIdentifier, "No product \(id).") }
        guard p.type == .autoRenewable else { throw TestSessionError(.invalidProductType, "\(id) is not an auto-renewable subscription.") }
        guard let i = state.chains.lastIndex(where: { $0.productID == id && $0.isActive }) else {
            throw TestSessionError(.noSubscriptionFound, "No active subscription of \(id).")
        }
        return i
    }

    public func clearTransactions() {
        perform {
            state.records = []
            state.chains = []
            dirty = true
        }
    }

    public func deleteTransaction(_ id: UInt64) throws(TestSessionError) {
        try perform { () throws(TestSessionError) in
            let i = try recordIndex(id)
            let r = state.records.remove(at: i)
            dirty = true
            guard let c = state.chains.firstIndex(where: { $0.originalID == r.originalID }) else { return }
            let rest = state.records.filter { $0.originalID == r.originalID && $0.productType == .autoRenewable }
            if rest.isEmpty {
                state.chains.remove(at: c)
            } else if state.chains[c].currentTransactionID == id, let last = rest.max(by: { $0.id < $1.id }) {
                state.chains[c].currentTransactionID = last.id
            }
        }
    }

    public func refundTransaction(_ id: UInt64, reason: Int = 0) throws(TestSessionError) {
        try perform { () throws(TestSessionError) in
            let i = try recordIndex(id)
            var r = state.records[i]
            guard !r.isRevoked, r.state != .deferred else { throw TestSessionError(.invalidAction, "Transaction \(id) cannot be refunded.") }
            r.revocationDate = now
            r.revocationReason = reason
            r.revocationType = "REFUND_FULL"
            r.revocationPercentage = 100_000
            state.records[i] = r
            if let c = state.chains.firstIndex(where: { $0.originalID == r.originalID }), state.chains[c].currentTransactionID == id {
                state.chains[c].state = .revoked
                state.chains[c].autoRenewEnabled = false
                state.chains[c].expirationIntent = 1
            }
            dirty = true
            emit(r)
        }
    }

    public func expireSubscription(productID: String) throws(TestSessionError) {
        try perform { () throws(TestSessionError) in
            let i = try activeChainIndex(product: productID)
            var c = state.chains[i]
            let t = now
            if let ri = state.records.firstIndex(where: { $0.id == c.currentTransactionID }) {
                var cur = state.records[ri]
                cur.expiresDate = t
                state.records[ri] = cur
                if quirks.expireLeavesFailedTransaction, let p = catalogCache?.product(c.autoRenewProductID) {
                    var failed = makeRecord(
                        product: p, reason: .renewal, originalID: c.originalID, originalPurchaseDate: c.originalPurchaseDate,
                        purchaseDate: cur.purchaseDate, expiresDate: t, quantity: 1, priceMilli: p.priceMilli, offer: nil,
                        token: cur.appAccountToken)
                    failed.state = .failed
                    failed.hasPurchaseIssue = true
                    state.records.append(failed)
                }
                emit(cur)
            }
            c.expiresDate = t
            c.state = .expired
            c.autoRenewEnabled = false
            c.expirationIntent = 2
            c.gracePeriodExpiresDate = nil
            c.billingRetryEndDate = nil
            c.hasBillingIssue = false
            state.chains[i] = c
            dirty = true
        }
    }

    public func forceRenewal(productID: String) throws(TestSessionError) {
        try perform { () throws(TestSessionError) in
            guard let p = catalogCache?.product(productID) else { throw TestSessionError(.invalidProductIdentifier, "No product \(productID).") }
            guard p.type == .autoRenewable else { throw TestSessionError(.invalidProductType, "\(productID) is not an auto-renewable subscription.") }
            guard let i = state.chains.lastIndex(where: { $0.productID == productID && $0.state != .revoked }) else {
                throw TestSessionError(.noSubscriptionFound, "No subscription of \(productID).")
            }
            var c = state.chains[i]
            let next = catalogCache?.product(c.autoRenewProductID) ?? p
            let wasActive = c.isEntitled
            c.state = .subscribed
            c.hasBillingIssue = false
            c.gracePeriodExpiresDate = nil
            c.billingRetryEndDate = nil
            if !wasActive { c.recentStartDate = now }
            renew(&c, product: next, at: now)
            state.chains[i] = c
        }
    }

    public func disableAutoRenew(transactionID: UInt64) throws(TestSessionError) {
        try perform { () throws(TestSessionError) in
            let i = try chainIndex(containing: transactionID)
            state.chains[i].autoRenewEnabled = false
            state.chains[i].expirationIntent = 1
            dirty = true
        }
    }

    public func enableAutoRenew(transactionID: UInt64) throws(TestSessionError) {
        try perform { () throws(TestSessionError) in
            let i = try chainIndex(containing: transactionID)
            var c = state.chains[i]
            guard c.state != .revoked else { throw TestSessionError(.invalidAction, "The subscription was refunded.") }
            c.autoRenewEnabled = true
            c.expirationIntent = nil
            if c.state == .expired, !c.isUpgradedAway, let next = catalogCache?.product(c.autoRenewProductID), next.subscription != nil {
                c.state = .subscribed
                renew(&c, product: next, at: c.expiresDate)
            }
            state.chains[i] = c
            dirty = true
            catchUp()
        }
    }

    public func approveAskToBuy(transactionID: UInt64) throws(TestSessionError) {
        try perform { () throws(TestSessionError) in
            let i = try recordIndex(transactionID)
            let r = state.records[i]
            guard r.isPendingAskToBuy else { throw TestSessionError(.invalidAction, "Transaction \(transactionID) is not waiting for approval.") }
            guard let p = catalogCache?.product(r.productID) else {
                throw TestSessionError(.invalidProductIdentifier, "No product \(r.productID).")
            }
            var options = r.pendingRequest ?? PurchaseOptions()
            options.purchaseDate = nil
            do {
                let made = try create(p, options: options, reuseID: r.id)
                emit(made)
            } catch {
                throw TestSessionError(.invalidAction, "The approved purchase failed.")
            }
        }
    }

    public func declineAskToBuy(transactionID: UInt64) throws(TestSessionError) {
        try perform { () throws(TestSessionError) in
            let i = try recordIndex(transactionID)
            var r = state.records[i]
            guard r.isPendingAskToBuy else { throw TestSessionError(.invalidAction, "Transaction \(transactionID) is not waiting for approval.") }
            r.state = .failed
            r.isPendingAskToBuy = false
            r.isAskToBuyDeclined = true
            r.pendingRequest = nil
            state.records[i] = r
            dirty = true
            if quirks.declinedAskToBuyIsDelivered { emit(r) }
        }
    }

    public func resolveIssue(transactionID: UInt64) throws(TestSessionError) {
        try perform { () throws(TestSessionError) in
            let i = try recordIndex(transactionID)
            var r = state.records[i]
            if r.hasPurchaseIssue && r.state == .failed {
                r.state = .purchased
                r.hasPurchaseIssue = false
                state.records[i] = r
                dirty = true
                emit(r)
                return
            }
            guard let ci = state.chains.firstIndex(where: { $0.originalID == r.originalID }), state.chains[ci].hasBillingIssue else {
                throw TestSessionError(.invalidAction, "Transaction \(transactionID) has no issue to resolve.")
            }
            var c = state.chains[ci]
            c.hasBillingIssue = false
            c.billingRetryEndDate = nil
            if c.state == .inGracePeriod {
                c.state = .subscribed
                c.gracePeriodExpiresDate = nil
            } else if c.state == .inBillingRetryPeriod, let next = catalogCache?.product(c.autoRenewProductID), next.subscription != nil {
                c.state = .subscribed
                c.recentStartDate = now
                renew(&c, product: next, at: now)
            }
            state.chains[ci] = c
            dirty = true
        }
    }

    public func requestPriceIncreaseConsent(transactionID: UInt64) throws(TestSessionError) {
        try perform { () throws(TestSessionError) in
            _ = try chainIndex(containing: transactionID)
            throw TestSessionError(.invalidAction, "No price increase is configured.")
        }
    }

    public func consentToPriceIncrease(transactionID: UInt64) throws(TestSessionError) {
        try requestPriceIncreaseConsent(transactionID: transactionID)
    }

    public func declinePriceIncrease(transactionID: UInt64) throws(TestSessionError) {
        try requestPriceIncreaseConsent(transactionID: transactionID)
    }
}
