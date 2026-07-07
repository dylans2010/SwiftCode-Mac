import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeGeneratorView: View {
    @State private var input = "https://swiftcode.app"
    @State private var qrImage: NSImage?

    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        VStack(spacing: 30) {
            VStack(alignment: .leading) {
                Text("QR Code Data")
                    .font(.headline)
                TextField("Enter URL or text", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: input) { generateQRCode() }
            }
            .padding([.top, .horizontal])

            Spacer()

            VStack {
                if let image = qrImage {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                            .frame(width: 200, height: 200)
                            .shadow(radius: 5)

                        Image(systemName: "qrcode")
                            .resizable()
                            .padding(20)
                            .frame(width: 180, height: 180)
                            .foregroundColor(.secondary)
                    }
                }

                Text("Preview for:")
                    .font(.caption)
                    .padding(.top)
                Text(input)
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer()

            Button("Download QR Code") {
                saveImage()
            }
            .padding(.bottom)
            .disabled(qrImage == nil)
        }
        .navigationTitle("QR Code Generator")
        .onAppear { generateQRCode() }
    }

    func generateQRCode() {
        let data = Data(input.utf8)
        filter.setValue(data, forKey: "inputMessage")

        if let outputImage = filter.outputImage {
            if let cgimg = context.createCGImage(outputImage, from: outputImage.extent) {
                qrImage = NSImage(cgImage: cgimg, size: NSSize(width: 200, height: 200))
                return
            }
        }
        qrImage = nil
    }

    func saveImage() {
        guard let image = qrImage else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "qrcode.png"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                if let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: url)
                }
            }
        }
    }
}
