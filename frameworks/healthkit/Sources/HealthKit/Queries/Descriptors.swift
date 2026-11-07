import Foundation

public protocol HKAsyncQuery: Sendable {
    associatedtype Output
    func result(for healthStore: HKHealthStore) async throws -> Output
}

public protocol HKAsyncSequenceQuery: Sendable {
    associatedtype Results: AsyncSequence
    func results(for healthStore: HKHealthStore) -> Results
}

public struct HKSamplePredicate<Sample: HKSample>: @unchecked Sendable {
    public let sampleType: HKSampleType
    public let nsPredicate: NSPredicate?

    init(sampleType: HKSampleType, predicate: NSPredicate?) {
        self.sampleType = sampleType
        self.nsPredicate = predicate
    }

    var descriptor: HKQueryDescriptor { HKQueryDescriptor(sampleType: sampleType, predicate: nsPredicate) }
}

extension HKSamplePredicate where Sample == HKSample {
    public static func sample(type: HKSampleType, predicate: NSPredicate? = nil) -> HKSamplePredicate<HKSample> {
        .init(sampleType: type, predicate: predicate)
    }
}
extension HKSamplePredicate where Sample == HKQuantitySample {
    public static func quantitySample(type: HKQuantityType, predicate: NSPredicate? = nil) -> HKSamplePredicate<HKQuantitySample> {
        .init(sampleType: type, predicate: predicate)
    }
}
extension HKSamplePredicate where Sample == HKCategorySample {
    public static func categorySample(type: HKCategoryType, predicate: NSPredicate? = nil) -> HKSamplePredicate<HKCategorySample> {
        .init(sampleType: type, predicate: predicate)
    }
}
extension HKSamplePredicate where Sample == HKCorrelation {
    public static func correlation(type: HKCorrelationType, predicate: NSPredicate? = nil) -> HKSamplePredicate<HKCorrelation> {
        .init(sampleType: type, predicate: predicate)
    }
}
extension HKSamplePredicate where Sample == HKWorkout {
    public static func workout(_ predicate: NSPredicate? = nil) -> HKSamplePredicate<HKWorkout> {
        .init(sampleType: HKObjectType.workoutType(), predicate: predicate)
    }
}

private func once<T: Sendable>(_ store: HKHealthStore,
                               _ make: (@escaping @Sendable (Result<T, any Error>) -> Void) -> HKQuery) async throws -> T {
    try await withCheckedThrowingContinuation { (k: CheckedContinuation<T, any Error>) in
        store.execute(make { k.resume(with: $0) })
    }
}

public struct HKSampleQueryDescriptor<Sample: HKSample>: HKAsyncQuery, @unchecked Sendable {
    public var predicates: [HKSamplePredicate<Sample>]
    public var sortDescriptors: [SortDescriptor<Sample>]
    public var limit: Int?

    public init(predicates: [HKSamplePredicate<Sample>], sortDescriptors: [SortDescriptor<Sample>], limit: Int? = nil) {
        self.predicates = predicates
        self.sortDescriptors = sortDescriptors
        self.limit = limit
    }

    public func result(for healthStore: HKHealthStore) async throws -> [Sample] {
        let descriptors = predicates.map(\.descriptor)
        let all: [HKSample] = try await once(healthStore) { done in
            HKSampleQuery(queryDescriptors: descriptors, limit: HKObjectQueryNoLimit) { _, s, e in
                done(e.map { .failure($0) } ?? .success(s ?? []))
            }
        }
        var out = all.compactMap { $0 as? Sample }
        if !sortDescriptors.isEmpty { out.sort(using: sortDescriptors) }
        if let limit, limit > 0, out.count > limit { out = Array(out.prefix(limit)) }
        return out
    }
}

public struct HKAnchoredObjectQueryDescriptor<Sample: HKSample>: HKAsyncQuery, HKAsyncSequenceQuery, @unchecked Sendable {
    public struct Result: @unchecked Sendable {
        public let addedSamples: [Sample]
        public let deletedObjects: [HKDeletedObject]
        public let newAnchor: HKQueryAnchor
    }

    public var predicates: [HKSamplePredicate<Sample>]
    public var anchor: HKQueryAnchor?
    public var limit: Int?

    public init(predicates: [HKSamplePredicate<Sample>], anchor: HKQueryAnchor?, limit: Int? = nil) {
        self.predicates = predicates
        self.anchor = anchor
        self.limit = limit
    }

    private func query(_ handler: @escaping HKAnchoredObjectQuery.Handler) -> HKAnchoredObjectQuery {
        HKAnchoredObjectQuery(queryDescriptors: predicates.map(\.descriptor), anchor: anchor,
                              limit: limit ?? HKObjectQueryNoLimit, resultsHandler: handler)
    }

    private static func make(_ a: [HKSample]?, _ d: [HKDeletedObject]?, _ anchor: HKQueryAnchor?) -> Result {
        Result(addedSamples: (a ?? []).compactMap { $0 as? Sample }, deletedObjects: d ?? [],
               newAnchor: anchor ?? HKQueryAnchor(value: 0))
    }

    public func result(for healthStore: HKHealthStore) async throws -> Result {
        try await once(healthStore) { done in
            query { _, a, d, n, e in done(e.map { .failure($0) } ?? .success(Self.make(a, d, n))) }
        }
    }

    public func results(for healthStore: HKHealthStore) -> AsyncThrowingStream<Result, any Error> {
        AsyncThrowingStream { continuation in
            let q = query { _, a, d, n, e in
                if let e { continuation.finish(throwing: e) } else { continuation.yield(Self.make(a, d, n)) }
            }
            q.updateHandler = { _, a, d, n, e in
                if let e { continuation.finish(throwing: e) } else { continuation.yield(Self.make(a, d, n)) }
            }
            continuation.onTermination = { _ in healthStore.stop(q) }
            healthStore.execute(q)
        }
    }
}

public struct HKStatisticsQueryDescriptor: HKAsyncQuery, @unchecked Sendable {
    public var predicate: HKSamplePredicate<HKQuantitySample>
    public var options: HKStatisticsOptions

    public init(predicate: HKSamplePredicate<HKQuantitySample>, options: HKStatisticsOptions) {
        self.predicate = predicate
        self.options = options
    }

    public func result(for healthStore: HKHealthStore) async throws -> HKStatistics? {
        let type = predicate.sampleType as! HKQuantityType
        let p = predicate.nsPredicate, o = options
        return try await once(healthStore) { done in
            HKStatisticsQuery(quantityType: type, quantitySamplePredicate: p, options: o) { _, s, e in
                if let e, (e as NSError).code == HKError.Code.errorNoData.rawValue { return done(.success(nil)) }
                done(e.map { .failure($0) } ?? .success(s))
            }
        }
    }
}

public struct HKStatisticsCollectionQueryDescriptor: HKAsyncQuery, HKAsyncSequenceQuery, @unchecked Sendable {
    public struct Result: @unchecked Sendable {
        public let statisticsCollection: HKStatisticsCollection
        public let updatedStatistics: [HKStatistics]?
    }

    public var predicate: HKSamplePredicate<HKQuantitySample>
    public var options: HKStatisticsOptions
    public var anchorDate: Date
    public var intervalComponents: DateComponents
    public var swiftcodeCalendar: Calendar = .current

    public init(predicate: HKSamplePredicate<HKQuantitySample>, options: HKStatisticsOptions, anchorDate: Date,
                intervalComponents: DateComponents) {
        self.predicate = predicate
        self.options = options
        self.anchorDate = anchorDate
        self.intervalComponents = intervalComponents
    }

    private func query() -> HKStatisticsCollectionQuery {
        let q = HKStatisticsCollectionQuery(quantityType: predicate.sampleType as! HKQuantityType,
                                            quantitySamplePredicate: predicate.nsPredicate, options: options,
                                            anchorDate: anchorDate, intervalComponents: intervalComponents)
        q.swiftcodeCalendar = swiftcodeCalendar
        return q
    }

    public func result(for healthStore: HKHealthStore) async throws -> HKStatisticsCollection {
        let q = query()
        return try await withCheckedThrowingContinuation { (k: CheckedContinuation<HKStatisticsCollection, any Error>) in
            q.initialResultsHandler = { _, c, e in
                if let c { k.resume(returning: c) } else { k.resume(throwing: e ?? HKError(.unknownError)) }
            }
            healthStore.execute(q)
        }
    }

    public func results(for healthStore: HKHealthStore) -> AsyncThrowingStream<Result, any Error> {
        AsyncThrowingStream { continuation in
            let q = query()
            q.initialResultsHandler = { _, c, e in
                if let c { continuation.yield(Result(statisticsCollection: c, updatedStatistics: nil)) }
                else { continuation.finish(throwing: e ?? HKError(.unknownError)) }
            }
            q.statisticsUpdateHandler = { _, s, c, e in
                if let c { continuation.yield(Result(statisticsCollection: c, updatedStatistics: s.map { [$0] })) }
                else if let e { continuation.finish(throwing: e) }
            }
            continuation.onTermination = { _ in healthStore.stop(q) }
            healthStore.execute(q)
        }
    }
}

public struct HKSourceQueryDescriptor<Sample: HKSample>: HKAsyncQuery, @unchecked Sendable {
    public var predicate: HKSamplePredicate<Sample>

    public init(predicate: HKSamplePredicate<Sample>) { self.predicate = predicate }

    public func result(for healthStore: HKHealthStore) async throws -> [HKSource] {
        let type = predicate.sampleType, p = predicate.nsPredicate
        let set: Set<HKSource> = try await once(healthStore) { done in
            HKSourceQuery(sampleType: type, samplePredicate: p) { _, s, e in
                done(e.map { .failure($0) } ?? .success(s ?? []))
            }
        }
        return set.sorted { $0.bundleIdentifier < $1.bundleIdentifier }
    }
}
