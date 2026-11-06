// Tests for LocalModelManager's model inventory (Legacy -> SwiftCodeAssistant port).
// Only the pure parts are pinned here: size formatting and extension-based
// type classification live in LocalModelInfo / scanModels. The scan itself
// reads ~/Documents/Models on the host and is not asserted here.
// Static only: not executed here (no Swift toolchain in this environment).

import Foundation
import Testing
@testable import SwiftCodeAssistant

@Suite("LocalModelManager")
struct LocalModelManagerTests {

    @Test("formattedSize renders MB and GB")
    func formattedSize() {
        var info = LocalModelInfo(id: "a", name: "m", fileName: "m.gguf",
                                  fileSize: 1_048_576, type: .gguf,
                                  url: URL(fileURLWithPath: "/tmp/m.gguf"))
        #expect(info.formattedSize == "1.0 MB")
        info.fileSize = 2_147_483_648
        #expect(info.formattedSize == "2.0 GB")
        info.fileSize = 512 * 1_024
        #expect(info.formattedSize == "0.5 MB")
    }

    @Test("ModelType icons are stable strings")
    func modelTypeIcons() {
        #expect(LocalModelInfo.ModelType.coreML.icon == "cpu.fill")
        #expect(LocalModelInfo.ModelType.gguf.icon == "gearshape.fill")
        #expect(LocalModelInfo.ModelType.onnx.icon == "bolt.fill")
        #expect(LocalModelInfo.ModelType.other.icon == "doc.fill")
    }
}
