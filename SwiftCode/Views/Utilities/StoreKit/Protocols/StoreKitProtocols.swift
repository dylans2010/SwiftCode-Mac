import Foundation

// MARK: - Manager Architectures

public final class StoreKitDocumentManager: Sendable {
    public static let shared = StoreKitDocumentManager()
    private init() {}
    public func activeDocument() -> StoreKitConfig { StoreKitWorkspaceManager.shared.activeConfig }
}

public final class StoreKitProductManager: Sendable {
    public static let shared = StoreKitProductManager()
    private init() {}
    public func fetchProducts() -> [SKProduct] { StoreKitWorkspaceManager.shared.activeConfig.products }
}

public final class StoreKitSubscriptionManager: Sendable {
    public static let shared = StoreKitSubscriptionManager()
    private init() {}
    public func fetchGroups() -> [SKSubscriptionGroup] { StoreKitWorkspaceManager.shared.activeConfig.subscriptionGroups }
}

public final class StoreKitOfferManager: Sendable {
    public static let shared = StoreKitOfferManager()
    private init() {}
}

public final class StoreKitSimulatorManager: Sendable {
    public static let shared = StoreKitSimulatorManager()
    private init() {}
}

public final class StoreKitValidationManager: Sendable {
    public static let shared = StoreKitValidationManager()
    private init() {}
}

public final class StoreKitTemplateManager: Sendable {
    public static let shared = StoreKitTemplateManager()
    private init() {}
}

public final class StoreKitImportManager: Sendable {
    public static let shared = StoreKitImportManager()
    private init() {}
}

public final class StoreKitExportManager: Sendable {
    public static let shared = StoreKitExportManager()
    private init() {}
}

public final class StoreKitLocalizationManager: Sendable {
    public static let shared = StoreKitLocalizationManager()
    private init() {}
}

public final class StoreKitStorefrontManager: Sendable {
    public static let shared = StoreKitStorefrontManager()
    private init() {}
}

public final class StoreKitAssetManager: Sendable {
    public static let shared = StoreKitAssetManager()
    private init() {}
}

public final class StoreKitLogManager: Sendable {
    public static let shared = StoreKitLogManager()
    private init() {}
}

public final class StoreKitSearchManager: Sendable {
    public static let shared = StoreKitSearchManager()
    private init() {}
}


// MARK: - Services Architectures

public final class StoreKitParserService: Sendable {
    public static let shared = StoreKitParserService()
    private init() {}
}

public final class StoreKitEncoderService: Sendable {
    public static let shared = StoreKitEncoderService()
    private init() {}
}

public final class StoreKitDecoderService: Sendable {
    public static let shared = StoreKitDecoderService()
    private init() {}
}

public final class StoreKitDocumentService: Sendable {
    public static let shared = StoreKitDocumentService()
    private init() {}
}

public final class StoreKitLoggingService: Sendable {
    public static let shared = StoreKitLoggingService()
    private init() {}
}

public final class StoreKitImportExportService: Sendable {
    public static let shared = StoreKitImportExportService()
    private init() {}
}

public final class StoreKitGenerationService: Sendable {
    public static let shared = StoreKitGenerationService()
    private init() {}
}
