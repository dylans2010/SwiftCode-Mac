public enum SpecType: UInt32, Hashable, Sendable {
    case unknown = 0
    case attribute = 1
    case connection = 2
    case expression = 3
    case mapper = 4
    case mapperArg = 5
    case prim = 6
    case pseudoRoot = 7
    case relationship = 8
    case relationshipTarget = 9
    case variant = 10
    case variantSet = 11
}

public struct Spec: Hashable, Sendable {
    public var type: SpecType
    public var fields: [String: Value]

    public init(type: SpecType, fields: [String: Value] = [:]) {
        self.type = type
        self.fields = fields
    }

    public subscript(field: String) -> Value? {
        get { fields[field] }
        set { fields[field] = newValue }
    }
}

public enum FieldKey {
    public static let primChildren = "primChildren"
    public static let properties = "properties"
    public static let variantSetChildren = "variantSetChildren"
    public static let variantChildren = "variantChildren"
    public static let targetChildren = "targetChildren"
    public static let connectionChildren = "connectionChildren"

    public static let specifier = "specifier"
    public static let typeName = "typeName"
    public static let active = "active"
    public static let kind = "kind"
    public static let instanceable = "instanceable"
    public static let hidden = "hidden"
    public static let references = "references"
    public static let payload = "payload"
    public static let inheritPaths = "inheritPaths"
    public static let specializes = "specializes"
    public static let variantSelection = "variantSelection"
    public static let variantSetNames = "variantSetNames"
    public static let apiSchemas = "apiSchemas"
    public static let primOrder = "primOrder"
    public static let propertyOrder = "propertyOrder"
    public static let customData = "customData"
    public static let assetInfo = "assetInfo"
    public static let documentation = "documentation"
    public static let comment = "comment"
    public static let displayName = "displayName"
    public static let displayGroup = "displayGroup"
    public static let permission = "permission"

    public static let defaultValue = "default"
    public static let timeSamples = "timeSamples"
    public static let variability = "variability"
    public static let custom = "custom"
    public static let targetPaths = "targetPaths"
    public static let connectionPaths = "connectionPaths"
    public static let allowedTokens = "allowedTokens"
    public static let interpolation = "interpolation"
    public static let elementSize = "elementSize"
    public static let colorSpace = "colorSpace"

    public static let defaultPrim = "defaultPrim"
    public static let upAxis = "upAxis"
    public static let metersPerUnit = "metersPerUnit"
    public static let subLayers = "subLayers"
    public static let subLayerOffsets = "subLayerOffsets"
    public static let startTimeCode = "startTimeCode"
    public static let endTimeCode = "endTimeCode"
    public static let timeCodesPerSecond = "timeCodesPerSecond"
    public static let framesPerSecond = "framesPerSecond"
    public static let customLayerData = "customLayerData"
    public static let owner = "owner"

    public static let childrenFields: Set<String> = [
        primChildren, properties, variantSetChildren, variantChildren, targetChildren, connectionChildren,
    ]
}
