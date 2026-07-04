func get() throws -> String? { return "a" }
func test() {
    let a: String = (try? get()) ?? ""
    print(a)
}
test()
