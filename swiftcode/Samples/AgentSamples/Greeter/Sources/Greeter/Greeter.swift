public struct Greeter {
    public var salutation: String

    public init(salutation: String = "Hello") {
        self.salutation = salutation
    }

    public func greeting(for name: String) -> String {
        "\(salutation), \(name)!"
    }
}
