func get() async throws -> String? { return "a" }
func test() async {
    let a: String = (try? await get()) ?? ""
    print(a)
}
Task { await test() }
