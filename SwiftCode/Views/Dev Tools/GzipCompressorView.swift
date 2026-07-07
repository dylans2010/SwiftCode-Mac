import SwiftUI
import Compression

struct GzipCompressorView: View {
    @State private var input = ""
    @State private var outputBase64 = ""
    @State private var isCompressing = true

    var body: some View {
        VStack(spacing: 20) {
            Picker("Mode", selection: $isCompressing) {
                Text("Compress").tag(true)
                Text("Decompress").tag(false)
            }
            .pickerStyle(.segmented)
            .padding()

            HSplitView {
                VStack(alignment: .leading) {
                    Text(isCompressing ? "Text Input" : "Base64 Input")
                    TextEditor(text: $input)
                        .border(Color.secondary.opacity(0.2))
                }
                VStack(alignment: .leading) {
                    Text(isCompressing ? "Base64 Output" : "Text Output")
                    TextEditor(text: .constant(outputBase64))
                        .border(Color.secondary.opacity(0.2))
                }
            }
            .padding()

            Button(isCompressing ? "Compress" : "Decompress") { process() }
                .buttonStyle(.borderedProminent)

            Spacer()
        }
        .navigationTitle("Gzip Compressor")
    }

    func process() {
        if isCompressing {
            let sourceData = Data(input.utf8)
            let bufferSize = sourceData.count + 1024
            var destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            let count = sourceData.withUnsafeBytes { (sourcePointer: UnsafeRawBufferPointer) -> Int in
                compression_encode_buffer(destinationBuffer, bufferSize, sourcePointer.bindMemory(to: UInt8.self).baseAddress!, sourceData.count, nil, COMPRESSION_ZLIB)
            }
            if count > 0 {
                let compressedData = Data(bytes: destinationBuffer, count: count)
                outputBase64 = compressedData.base64EncodedString()
            }
            destinationBuffer.deallocate()
        } else {
            guard let sourceData = Data(base64Encoded: input) else { return }
            let bufferSize = sourceData.count * 10
            var destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            let count = sourceData.withUnsafeBytes { (sourcePointer: UnsafeRawBufferPointer) -> Int in
                compression_decode_buffer(destinationBuffer, bufferSize, sourcePointer.bindMemory(to: UInt8.self).baseAddress!, sourceData.count, nil, COMPRESSION_ZLIB)
            }
            if count > 0 {
                let decompressedData = Data(bytes: destinationBuffer, count: count)
                outputBase64 = String(data: decompressedData, encoding: .utf8) ?? "Failed to decode"
            }
            destinationBuffer.deallocate()
        }
    }
}
