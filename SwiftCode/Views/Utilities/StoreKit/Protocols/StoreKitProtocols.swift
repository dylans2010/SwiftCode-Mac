import Foundation

// MARK: - Manager Architectures

@MainActor
public final class StoreKitDocumentManager {
    public static let shared = StoreKitDocumentManager()
    private init() {}
    public func activeDocument() -> StoreKitConfig { StoreKitWorkspaceManager.shared.activeConfig }
}

@MainActor
public final class StoreKitProductManager {
    public static let shared = StoreKitProductManager()
    private init() {}
    public func fetchProducts() -> [SKProduct] { StoreKitWorkspaceManager.shared.activeConfig.products }
}

@MainActor
public final class StoreKitSubscriptionManager {
    public static let shared = StoreKitSubscriptionManager()
    private init() {}
    public func fetchGroups() -> [SKSubscriptionGroup] { StoreKitWorkspaceManager.shared.activeConfig.subscriptionGroups }
}

@MainActor
public final class StoreKitOfferManager {
    public static let shared = StoreKitOfferManager()
    private init() {}
}

@MainActor
public final class StoreKitSimulatorManager {
    public static let shared = StoreKitSimulatorManager()
    private init() {}
}

@MainActor
public final class StoreKitValidationManager {
    public static let shared = StoreKitValidationManager()
    private init() {}
}

@MainActor
public final class StoreKitTemplateManager {
    public static let shared = StoreKitTemplateManager()
    private init() {}
}

@MainActor
public final class StoreKitImportManager {
    public static let shared = StoreKitImportManager()
    private init() {}
}

@MainActor
public final class StoreKitExportManager {
    public static let shared = StoreKitExportManager()
    private init() {}
}

@MainActor
public final class StoreKitLocalizationManager {
    public static let shared = StoreKitLocalizationManager()
    private init() {}
}

@MainActor
public final class StoreKitStorefrontManager {
    public static let shared = StoreKitStorefrontManager()
    private init() {}
}

@MainActor
public final class StoreKitAssetManager {
    public static let shared = StoreKitAssetManager()
    private init() {}
}

@MainActor
public final class StoreKitLogManager {
    public static let shared = StoreKitLogManager()
    private init() {}
}

@MainActor
public final class StoreKitSearchManager {
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
