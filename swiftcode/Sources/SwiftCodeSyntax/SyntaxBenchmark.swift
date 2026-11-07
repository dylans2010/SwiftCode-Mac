public enum SyntaxBenchmark {
    public static func swiftSource(lines count: Int) -> String {
        var lines: [String] = ["import Foundation", "/* A block comment", "   over two lines */"]
        var i = 0
        while lines.count < count {
            lines += ["/// Doc for item \(i)", "struct Item\(i) {", "    var name = \"item \(i)\" // trailing", "    let value: Int = \(i * 7)",
                      "    func describe() -> String { \"\\(name)=\\(value)\" }", "}", ""]
            i += 1
        }
        return lines.prefix(count).joined(separator: "\n") + "\n"
    }
}
