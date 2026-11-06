import Foundation
import CoreGraphics
import AppKit
import ImageIO

struct IconSpec {
    let name: String
    let sourcePath: String
    let cropRect: CGRect
}

let specs: [IconSpec] = [
    IconSpec(
        name: "Light",
        sourcePath: "/Users/dylan/.gemini/antigravity-ide/brain/23dd43fd-ef9c-40aa-89a6-6f824bdf1c40/icon_light_mode_1788751657841.jpg",
        cropRect: CGRect(x: 128, y: 127, width: 766, height: 767)
    ),
    IconSpec(
        name: "Dark",
        sourcePath: "/Users/dylan/.gemini/antigravity-ide/brain/23dd43fd-ef9c-40aa-89a6-6f824bdf1c40/icon_dark_mode_1788751677454.jpg",
        cropRect: CGRect(x: 185, y: 185, width: 650, height: 648)
    ),
    IconSpec(
        name: "Glass",
        sourcePath: "/Users/dylan/.gemini/antigravity-ide/brain/23dd43fd-ef9c-40aa-89a6-6f824bdf1c40/icon_glass_mode_1788751741542.jpg",
        cropRect: CGRect(x: 114, y: 115, width: 792, height: 792)
    ),
    IconSpec(
        name: "Tinted",
        sourcePath: "/Users/dylan/.gemini/antigravity-ide/brain/23dd43fd-ef9c-40aa-89a6-6f824bdf1c40/icon_tinted_mode_1788751949881.jpg",
        cropRect: CGRect(x: 185, y: 185, width: 651, height: 652)
    )
]

/// Creates a macOS squircle icon (1024x1024 canvas, 824x824 squircle centered with standard drop shadow)
func createMacSquircleIcon(from cgImage: CGImage, cropRect: CGRect) -> CGImage? {
    // In CoreGraphics flipped coordinates, calculate crop
    let cgCropRect = CGRect(x: cropRect.origin.x, y: CGFloat(cgImage.height) - cropRect.origin.y - cropRect.size.height, width: cropRect.size.width, height: cropRect.size.height)
    guard let cropped = cgImage.cropping(to: cgCropRect) else { return nil }
    
    let canvasSize: CGFloat = 1024
    let squircleSize: CGFloat = 824
    let origin: CGFloat = (canvasSize - squircleSize) / 2.0 // 100.0
    let cornerRadius: CGFloat = squircleSize * 0.224 // 184.576
    
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil,
        width: Int(canvasSize),
        height: Int(canvasSize),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    
    // Squircle rect in CoreGraphics (y=0 at bottom)
    // Elevation shadow: offset downwards by ~12px
    let squircleRect = CGRect(x: origin, y: origin + 12.0, width: squircleSize, height: squircleSize)
    let squirclePath = CGPath(
        roundedRect: squircleRect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
    
    // Draw macOS Dock primary shadow
    context.saveGState()
    let shadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.32)
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: shadowColor)
    context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1.0))
    context.addPath(squirclePath)
    context.fillPath()
    context.restoreGState()
    
    // Secondary contact shadow
    context.saveGState()
    let ambientShadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.18)
    context.setShadow(offset: CGSize(width: 0, height: -4), blur: 8, color: ambientShadowColor)
    context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1.0))
    context.addPath(squirclePath)
    context.fillPath()
    context.restoreGState()
    
    // Clip to squircle path and draw the cropped tile
    context.saveGState()
    context.addPath(squirclePath)
    context.clip()
    context.draw(cropped, in: squircleRect)
    
    // Subtle interior edge highlight (glass bevel)
    context.setLineWidth(2.5)
    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22))
    context.addPath(squirclePath)
    context.strokePath()
    context.restoreGState()
    
    return context.makeImage()
}

/// Creates a full-bleed universal icon (1024x1024 edge-to-edge)
func createFullBleedIcon(from cgImage: CGImage, cropRect: CGRect) -> CGImage? {
    let cgCropRect = CGRect(x: cropRect.origin.x, y: CGFloat(cgImage.height) - cropRect.origin.y - cropRect.size.height, width: cropRect.size.width, height: cropRect.size.height)
    guard let cropped = cgImage.cropping(to: cgCropRect) else { return nil }
    
    let canvasSize: CGFloat = 1024
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil,
        width: Int(canvasSize),
        height: Int(canvasSize),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    
    let targetRect = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
    context.draw(cropped, in: targetRect)
    
    return context.makeImage()
}

func savePNG(image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    let destDir = url.deletingLastPathComponent().path
    try? FileManager.default.createDirectory(atPath: destDir, withIntermediateDirectories: true)
    
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        print("Failed to create destination for \(path)")
        return
    }
    CGImageDestinationAddImage(dest, image, nil)
    if CGImageDestinationFinalize(dest) {
        print("Saved: \(url.lastPathComponent)")
    } else {
        print("Failed to finalize: \(path)")
    }
}

func resize(image: CGImage, to size: Int) -> CGImage? {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return context.makeImage()
}

let macSizes: [(point: Int, scale: Int, pixel: Int)] = [
    (16, 1, 16),
    (16, 2, 32),
    (32, 1, 32),
    (32, 2, 64),
    (128, 1, 128),
    (128, 2, 256),
    (256, 1, 256),
    (256, 2, 512),
    (512, 1, 512),
    (512, 2, 1024)
]

let baseAssetsDir = "/Users/dylan/Library/Mobile Documents/com~apple~CloudDocs/Xcode Projects/SwiftCode-Mac/SwiftCode/Assets.xcassets"

for spec in specs {
    print("\nProcessing \(spec.name)...")
    let url = URL(fileURLWithPath: spec.sourcePath)
    guard let nsImg = NSImage(contentsOf: url),
          let cg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("Failed to load \(spec.sourcePath)")
        continue
    }
    
    guard let macMaster = createMacSquircleIcon(from: cg, cropRect: spec.cropRect),
          let universalMaster = createFullBleedIcon(from: cg, cropRect: spec.cropRect) else {
        print("Failed to render master for \(spec.name)")
        continue
    }
    
    // 1. Save variant appiconset (e.g. AppIcon-Light, AppIcon-Dark, AppIcon-Glass, AppIcon-Tinted)
    let setDir = "\(baseAssetsDir)/AppIcon-\(spec.name).appiconset"
    
    // Save universal 1024
    savePNG(image: universalMaster, to: "\(setDir)/AppIcon-1024.png")
    
    // Save macOS sized icons
    for entry in macSizes {
        if let scaled = resize(image: macMaster, to: entry.pixel) {
            let filename = "icon_\(entry.point)x\(entry.point)@\(entry.scale)x.png"
            savePNG(image: scaled, to: "\(setDir)/\(filename)")
        }
    }
    
    // Also save preview imageset for in-app UI and dynamic icon switching
    let previewSetDir = "\(baseAssetsDir)/AppIcon-Preview-\(spec.name).imageset"
    try? FileManager.default.createDirectory(atPath: previewSetDir, withIntermediateDirectories: true)
    if let previewImg = resize(image: macMaster, to: 512) {
        savePNG(image: previewImg, to: "\(previewSetDir)/preview.png")
        let previewContents = """
        {
          "images" : [
            {
              "filename" : "preview.png",
              "idiom" : "universal"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
        try? previewContents.write(toFile: "\(previewSetDir)/Contents.json", atomically: true, encoding: .utf8)
    }

    // Also save in primary AppIcon.appiconset
    if spec.name == "Light" {
        let primarySetDir = "\(baseAssetsDir)/AppIcon.appiconset"
        savePNG(image: universalMaster, to: "\(primarySetDir)/AppIcon-Light-1024.png")
        for entry in macSizes {
            if let scaled = resize(image: macMaster, to: entry.pixel) {
                let filename = "icon_\(entry.point)x\(entry.point)@\(entry.scale)x.png"
                savePNG(image: scaled, to: "\(primarySetDir)/\(filename)")
            }
        }
    } else if spec.name == "Dark" {
        let primarySetDir = "\(baseAssetsDir)/AppIcon.appiconset"
        savePNG(image: universalMaster, to: "\(primarySetDir)/AppIcon-Dark-1024.png")
    } else if spec.name == "Tinted" {
        let primarySetDir = "\(baseAssetsDir)/AppIcon.appiconset"
        savePNG(image: universalMaster, to: "\(primarySetDir)/AppIcon-Tinted-1024.png")
    }
}

print("\nDone generating all icon variants and preview imagesets!")

