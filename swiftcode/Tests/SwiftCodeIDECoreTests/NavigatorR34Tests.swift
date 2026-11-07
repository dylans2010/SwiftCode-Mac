import Foundation
import Testing
import SwiftCodeBuild
import SwiftCodeDebug
@testable import SwiftCodeIDECore

@MainActor
@Suite struct StaleIssuesAndProcessRowTests {
    func d(_ msg: String, _ file: String?) -> Diagnostic {
        Diagnostic(severity: .warning, message: msg, location: file.map { .init(file: $0, line: 1) })
    }

    @Test func nextBuildReplacesIssuesOfFilesItCompiled() {
        var m = IssueNavigatorModel()
        let a = d("a", "/p/A.swift"), b = d("b", "/p/B.swift"), n = d("n", nil)
        m.finishBuild([a, b, n], full: false, compiledFiles: ["A.swift", "B.swift"])
        m.startBuild()
        #expect(m.entries(fresh: []).map(\.isStale) == [true, true, true])
        #expect(m.capsuleCounts(fresh: []).warnings == 3)
        m.finishBuild([], full: false, compiledFiles: ["A.swift"])
        #expect(!m.isBuilding)
        #expect(m.stale == [b])
        m.finishBuild([], full: false, compiledFiles: ["B.swift"])
        #expect(m.stale.isEmpty)
        m.finishBuild([a], full: false, compiledFiles: [])
        m.finishBuild([], full: false, compiledFiles: nil)
        #expect(m.stale.isEmpty)
    }

    @Test func compiledFilesFromTheLog() {
        let swiftpm = ["Building for debugging...", "[3/7] Compiling Demo main.swift other.swift", "[5/7] Linking Demo", "Build complete!"]
        #expect(IssueNavigatorModel.compiledFiles(inLog: swiftpm, isPackage: true) == ["main.swift", "other.swift"])
        let xcb = ["SwiftCompile normal arm64 /p/App/View.swift (in target 'App' from project 'App')",
                   "CompileC /p/b/x.o /p/App/x.c normal arm64 c com.apple.compilers.llvm.clang.1_0.compiler (in target 'App' from project 'App')"]
        #expect(IssueNavigatorModel.compiledFiles(inLog: xcb, isPackage: false) == ["View.swift", "x.c"])
        #expect(IssueNavigatorModel.compiledFiles(inLog: ["Build complete!"], isPackage: true) == nil)
    }
}
