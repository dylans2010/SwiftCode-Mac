import Foundation
import CoreGraphics
import AppKit
import ImageIO

// MARK: - Geometry & Helpers

let canvasSize: CGFloat = 1024
let squircleSize: CGFloat = 824
let origin: CGFloat = (canvasSize - squircleSize) / 2.0 // 100.0
let cornerRadius: CGFloat = squircleSize * 0.224 // 184.576
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func createBaseContext(size: CGFloat) -> CGContext? {
    guard let ctx = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    return ctx
}

func color(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1.0) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func hexColor(_ hex: UInt32, alpha: CGFloat = 1.0) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
}

func drawLinearGradient(
    in ctx: CGContext,
    rect: CGRect,
    colors: [CGColor],
    startPoint: CGPoint,
    endPoint: CGPoint
) {
    let locations: [CGFloat] = stride(from: 0.0, through: 1.0, by: 1.0 / CGFloat(max(1, colors.count - 1))).map { $0 }
    guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) else { return }
    ctx.saveGState()
    ctx.addRect(rect)
    ctx.clip()
    ctx.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func drawRadialGradient(
    in ctx: CGContext,
    center: CGPoint,
    startRadius: CGFloat,
    endRadius: CGFloat,
    colors: [CGColor]
) {
    let locations: [CGFloat] = stride(from: 0.0, through: 1.0, by: 1.0 / CGFloat(max(1, colors.count - 1))).map { $0 }
    guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) else { return }
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: startRadius, endCenter: center, endRadius: endRadius, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func drawSFSymbol(
    name: String,
    in ctx: CGContext,
    rect: CGRect,
    tintColor: CGColor,
    pointSize: CGFloat = 340,
    weight: NSFont.Weight = .semibold
) {
    guard let symbolImg = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    guard let configured = symbolImg.withSymbolConfiguration(config) else { return }
    
    // Render symbol to bitmap image with tint
    let symSize = configured.size
    let destRect = CGRect(
        x: rect.midX - symSize.width / 2,
        y: rect.midY - symSize.height / 2,
        width: symSize.width,
        height: symSize.height
    )
    
    ctx.saveGState()
    guard let mask = configured.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        ctx.restoreGState()
        return
    }
    ctx.clip(to: destRect, mask: mask)
    ctx.setFillColor(tintColor)
    ctx.fill(destRect)
    ctx.restoreGState()
}

func drawText(
    _ text: String,
    in ctx: CGContext,
    rect: CGRect,
    fontName: String = "Menlo-Bold",
    fontSize: CGFloat,
    color: CGColor,
    alignment: NSTextAlignment = .center
) {
    let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = alignment
    
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(cgColor: color) ?? .white,
        .paragraphStyle: paragraphStyle
    ]
    let str = NSAttributedString(string: text, attributes: attrs)
    let line = CTLineCreateWithAttributedString(str)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    
    ctx.saveGState()
    var x = rect.midX - bounds.width / 2 - bounds.origin.x
    if alignment == .left { x = rect.minX }
    let y = rect.midY - bounds.height / 2 - bounds.origin.y
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

// MARK: - Squircle Packaging

func renderMacSquircle(drawArtwork: (CGContext, CGRect) -> Void) -> CGImage? {
    guard let ctx = createBaseContext(size: canvasSize) else { return nil }
    
    let squircleRect = CGRect(x: origin, y: origin + 12.0, width: squircleSize, height: squircleSize)
    let squirclePath = CGPath(
        roundedRect: squircleRect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
    
    // 1. Primary Elevation Drop Shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(r: 0, g: 0, b: 0, a: 0.32))
    ctx.setFillColor(color(r: 0, g: 0, b: 0, a: 1.0))
    ctx.addPath(squirclePath)
    ctx.fillPath()
    ctx.restoreGState()
    
    // 2. Secondary Ambient Contact Shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 8, color: color(r: 0, g: 0, b: 0, a: 0.18))
    ctx.setFillColor(color(r: 0, g: 0, b: 0, a: 1.0))
    ctx.addPath(squirclePath)
    ctx.fillPath()
    ctx.restoreGState()
    
    // 3. Clip and Draw Artwork
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()
    drawArtwork(ctx, squircleRect)
    
    // 4. Subtle Inner Bevel Stroke
    ctx.setLineWidth(2.5)
    ctx.setStrokeColor(color(r: 1, g: 1, b: 1, a: 0.22))
    ctx.addPath(squirclePath)
    ctx.strokePath()
    ctx.restoreGState()
    
    return ctx.makeImage()
}

func renderUniversal(drawArtwork: (CGContext, CGRect) -> Void) -> CGImage? {
    guard let ctx = createBaseContext(size: canvasSize) else { return nil }
    let rect = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
    drawArtwork(ctx, rect)
    return ctx.makeImage()
}

// MARK: - Artwork Renderers for All 26 New Icons

// 5. System 7 (1991)
func drawRetroMac(ctx: CGContext, rect: CGRect) {
    // Vintage Macintosh Platinum beige chassis
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0xEAE5DC), hexColor(0xD2C8BC)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // CRT screen recessed bezel
    let screenBezel = rect.insetBy(dx: 110, dy: 140).offsetBy(dx: 0, dy: 30)
    let screenPath = CGPath(roundedRect: screenBezel, cornerWidth: 36, cornerHeight: 36, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 10, color: color(r: 0, g: 0, b: 0, a: 0.35))
    ctx.setFillColor(hexColor(0x3B3732))
    ctx.addPath(screenPath)
    ctx.fillPath()
    ctx.restoreGState()
    
    // CRT phosphor retro screen
    let innerScreen = screenBezel.insetBy(dx: 22, dy: 22)
    let innerPath = CGPath(roundedRect: innerScreen, cornerWidth: 20, cornerHeight: 20, transform: nil)
    ctx.saveGState()
    ctx.addPath(innerPath)
    ctx.clip()
    drawLinearGradient(
        in: ctx, rect: innerScreen,
        colors: [hexColor(0x9CA685), hexColor(0x828D6B)],
        startPoint: CGPoint(x: innerScreen.midX, y: innerScreen.maxY),
        endPoint: CGPoint(x: innerScreen.midX, y: innerScreen.minY)
    )
    
    // Draw Happy Mac Icon inside CRT
    let macRect = CGRect(x: innerScreen.midX - 140, y: innerScreen.midY - 140, width: 280, height: 280)
    drawSFSymbol(name: "desktopcomputer", in: ctx, rect: macRect, tintColor: hexColor(0x1B2117), pointSize: 220, weight: .bold)
    
    // Draw smiling face inside computer screen
    drawText("^_^", in: ctx, rect: CGRect(x: innerScreen.midX - 80, y: innerScreen.midY - 15, width: 160, height: 50), fontName: "Courier-Bold", fontSize: 44, color: hexColor(0x1B2117))
    ctx.restoreGState()
    
    // Floppy disk drive horizontal slot below screen
    let slotRect = CGRect(x: rect.midX - 180, y: rect.minY + 90, width: 360, height: 18)
    let slotPath = CGPath(roundedRect: slotRect, cornerWidth: 9, cornerHeight: 9, transform: nil)
    ctx.setFillColor(hexColor(0x282522))
    ctx.addPath(slotPath)
    ctx.fillPath()
    
    // Rainbow Apple badge square
    let badgeRect = CGRect(x: rect.minX + 90, y: rect.minY + 75, width: 44, height: 48)
    drawLinearGradient(
        in: ctx, rect: badgeRect,
        colors: [hexColor(0x61BB46), hexColor(0xFDB827), hexColor(0xF5821F), hexColor(0xE03A3E), hexColor(0x963D97), hexColor(0x009DDC)],
        startPoint: CGPoint(x: badgeRect.minX, y: badgeRect.maxY),
        endPoint: CGPoint(x: badgeRect.minX, y: badgeRect.minY)
    )
}

// 6. Aqua Cheetah (2001)
func drawAqua2001(ctx: CGContext, rect: CGRect) {
    // Brushed Aqua Pinstripes Background
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x6BA4D4), hexColor(0x285989)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // Fine pinstripes
    ctx.saveGState()
    ctx.setLineWidth(1.5)
    ctx.setStrokeColor(color(r: 1, g: 1, b: 1, a: 0.12))
    for x in stride(from: rect.minX, to: rect.maxX, by: 12) {
        ctx.move(to: CGPoint(x: x, y: rect.minY))
        ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
    }
    ctx.strokePath()
    ctx.restoreGState()
    
    // Glossy Aqua Gel Pill Button in Center
    let pillRect = rect.insetBy(dx: 90, dy: 110)
    let pillPath = CGPath(roundedRect: pillRect, cornerWidth: 150, cornerHeight: 150, transform: nil)
    
    // Gel drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: color(r: 0, g: 0.2, b: 0.5, a: 0.45))
    ctx.addPath(pillPath)
    ctx.setFillColor(hexColor(0x1870C5))
    ctx.fillPath()
    ctx.restoreGState()
    
    // Gel body gradient
    ctx.saveGState()
    ctx.addPath(pillPath)
    ctx.clip()
    drawLinearGradient(
        in: ctx, rect: pillRect,
        colors: [hexColor(0x7CE8FF), hexColor(0x1F8BE9), hexColor(0x064EAA)],
        startPoint: CGPoint(x: pillRect.midX, y: pillRect.maxY),
        endPoint: CGPoint(x: pillRect.midX, y: pillRect.minY)
    )
    
    // Curved white liquid gloss reflection at top
    let glossRect = CGRect(x: pillRect.minX + 24, y: pillRect.midY + 10, width: pillRect.width - 48, height: pillRect.height / 2 - 20)
    let glossPath = CGPath(ellipseIn: glossRect, transform: nil)
    ctx.saveGState()
    ctx.addPath(glossPath)
    ctx.clip()
    drawLinearGradient(
        in: ctx, rect: glossRect,
        colors: [color(r: 1, g: 1, b: 1, a: 0.85), color(r: 1, g: 1, b: 1, a: 0.0)],
        startPoint: CGPoint(x: glossRect.midX, y: glossRect.maxY),
        endPoint: CGPoint(x: glossRect.midX, y: glossRect.minY)
    )
    ctx.restoreGState()
    
    // Swift Bird emblem inside gel
    drawSFSymbol(name: "swift", in: ctx, rect: pillRect.offsetBy(dx: 0, dy: -20), tintColor: color(r: 1, g: 1, b: 1, a: 0.95), pointSize: 340, weight: .bold)
    ctx.restoreGState()
}

// 7. NeXTSTEP (1989)
func drawNeXTSTEP(ctx: CGContext, rect: CGRect) {
    // Matte dark magnesium tile
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x23252A), hexColor(0x131417)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // 3D NeXT-style tilted cubic square badge
    let cubeRect = rect.insetBy(dx: 130, dy: 130)
    let cubePath = CGPath(roundedRect: cubeRect, cornerWidth: 60, cornerHeight: 60, transform: nil)
    
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 30, color: color(r: 0, g: 0, b: 0, a: 0.7))
    ctx.setFillColor(hexColor(0x0C0D0F))
    ctx.addPath(cubePath)
    ctx.fillPath()
    ctx.restoreGState()
    
    // 2x2 Grid of classic NeXT letters: 'S' (Green), 'W' (Yellow), 'I' (Red), 'FT' (Cyan)
    ctx.saveGState()
    ctx.addPath(cubePath)
    ctx.clip()
    
    let midX = cubeRect.midX
    let midY = cubeRect.midY
    
    // Divider lines
    ctx.setLineWidth(6)
    ctx.setStrokeColor(hexColor(0x1C1E24))
    ctx.move(to: CGPoint(x: cubeRect.minX, y: midY))
    ctx.addLine(to: CGPoint(x: cubeRect.maxX, y: midY))
    ctx.move(to: CGPoint(x: midX, y: cubeRect.minY))
    ctx.addLine(to: CGPoint(x: midX, y: cubeRect.maxY))
    ctx.strokePath()
    
    // Letters
    let fontName = "Helvetica-Bold"
    drawText("S", in: ctx, rect: CGRect(x: cubeRect.minX, y: midY, width: cubeRect.width / 2, height: cubeRect.height / 2), fontName: fontName, fontSize: 130, color: hexColor(0x00D664))
    drawText("W", in: ctx, rect: CGRect(x: midX, y: midY, width: cubeRect.width / 2, height: cubeRect.height / 2), fontName: fontName, fontSize: 130, color: hexColor(0xFFCC00))
    drawText("I", in: ctx, rect: CGRect(x: cubeRect.minX, y: cubeRect.minY, width: cubeRect.width / 2, height: cubeRect.height / 2), fontName: fontName, fontSize: 130, color: hexColor(0xFF3B30))
    drawText("FT", in: ctx, rect: CGRect(x: midX, y: cubeRect.minY, width: cubeRect.width / 2, height: cubeRect.height / 2), fontName: fontName, fontSize: 105, color: hexColor(0x00B4D8))
    
    ctx.restoreGState()
}

// 8. Phosphor Green CRT (1982)
func drawPhosphorCRT(ctx: CGContext, rect: CGRect) {
    // Deep black CRT monitor
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x141814), hexColor(0x050805)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // Curved screen vignette
    drawRadialGradient(
        in: ctx, center: CGPoint(x: rect.midX, y: rect.midY),
        startRadius: 80, endRadius: 460,
        colors: [color(r: 0, g: 0.25, b: 0.08, a: 0.6), color(r: 0, g: 0.02, b: 0.01, a: 0.95)]
    )
    
    // Phosphor Green Scanlines
    ctx.saveGState()
    ctx.setLineWidth(2)
    ctx.setStrokeColor(color(r: 0.1, g: 1.0, b: 0.3, a: 0.12))
    for y in stride(from: rect.minY, to: rect.maxY, by: 6) {
        ctx.move(to: CGPoint(x: rect.minX, y: y))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
    }
    ctx.strokePath()
    ctx.restoreGState()
    
    // Glowing Terminal Text
    let neonGreen = hexColor(0x33FF66)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 18, color: neonGreen)
    drawText(">_ swift run", in: ctx, rect: CGRect(x: rect.minX + 90, y: rect.midY + 70, width: rect.width - 180, height: 60), fontName: "Menlo-Bold", fontSize: 56, color: neonGreen, alignment: .left)
    drawText("[OK] Build ready", in: ctx, rect: CGRect(x: rect.minX + 90, y: rect.midY - 10, width: rect.width - 180, height: 50), fontName: "Menlo-Bold", fontSize: 44, color: hexColor(0x22C55E), alignment: .left)
    drawText("$ █", in: ctx, rect: CGRect(x: rect.minX + 90, y: rect.midY - 80, width: rect.width - 180, height: 50), fontName: "Menlo-Bold", fontSize: 52, color: neonGreen, alignment: .left)
    ctx.restoreGState()
}

// 9. Amber VT220 Terminal
func drawAmberCRT(ctx: CGContext, rect: CGRect) {
    // Dark amber CRT monitor
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x201404), hexColor(0x0B0600)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // Curved screen vignette
    drawRadialGradient(
        in: ctx, center: CGPoint(x: rect.midX, y: rect.midY),
        startRadius: 80, endRadius: 460,
        colors: [color(r: 0.35, g: 0.20, b: 0.0, a: 0.6), color(r: 0.05, g: 0.02, b: 0.0, a: 0.95)]
    )
    
    // Amber Scanlines
    ctx.saveGState()
    ctx.setLineWidth(2)
    ctx.setStrokeColor(color(r: 1.0, g: 0.7, b: 0.0, a: 0.12))
    for y in stride(from: rect.minY, to: rect.maxY, by: 6) {
        ctx.move(to: CGPoint(x: rect.minX, y: y))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
    }
    ctx.strokePath()
    ctx.restoreGState()
    
    // Glowing Amber Monospace Text
    let amber = hexColor(0xFFB000)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 20, color: amber)
    drawText("$ swiftc -O2", in: ctx, rect: CGRect(x: rect.minX + 90, y: rect.midY + 70, width: rect.width - 180, height: 60), fontName: "Menlo-Bold", fontSize: 56, color: amber, alignment: .left)
    drawText("Linking: OK", in: ctx, rect: CGRect(x: rect.minX + 90, y: rect.midY - 10, width: rect.width - 180, height: 50), fontName: "Menlo-Bold", fontSize: 44, color: hexColor(0xFFA000), alignment: .left)
    drawText("./main █", in: ctx, rect: CGRect(x: rect.minX + 90, y: rect.midY - 80, width: rect.width - 180, height: 50), fontName: "Menlo-Bold", fontSize: 52, color: amber, alignment: .left)
    ctx.restoreGState()
}

// 10. Synthwave 80s
func drawSynthwave(ctx: CGContext, rect: CGRect) {
    // Deep midnight purple sky
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x1D063A), hexColor(0x0C021B)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // Glowing Striped Synthwave Sun
    let sunRect = CGRect(x: rect.midX - 190, y: rect.midY - 90, width: 380, height: 380)
    let sunPath = CGPath(ellipseIn: sunRect, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: hexColor(0xFF007F))
    ctx.addPath(sunPath)
    ctx.clip()
    drawLinearGradient(
        in: ctx, rect: sunRect,
        colors: [hexColor(0xFFE600), hexColor(0xFF7700), hexColor(0xFF0077)],
        startPoint: CGPoint(x: sunRect.midX, y: sunRect.maxY),
        endPoint: CGPoint(x: sunRect.midX, y: sunRect.minY)
    )
    
    // Horizontal sun blinds
    ctx.setFillColor(hexColor(0x1D063A))
    for (i, y) in stride(from: sunRect.midY - 30, to: sunRect.minY, by: -18).enumerated() {
        let barHeight = CGFloat(3 + i * 2)
        ctx.fill(CGRect(x: sunRect.minX, y: y, width: sunRect.width, height: barHeight))
    }
    ctx.restoreGState()
    
    // Perspective Grid Floor (cyan wireframe)
    ctx.saveGState()
    let horizonY = rect.midY - 90
    ctx.setLineWidth(2)
    ctx.setStrokeColor(hexColor(0x00F5FF, alpha: 0.8))
    
    // Horizontal perspective lines
    var curY = horizonY
    var step: CGFloat = 6
    while curY > rect.minY {
        ctx.move(to: CGPoint(x: rect.minX, y: curY))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: curY))
        curY -= step
        step *= 1.35
    }
    
    // Vanishing perspective rays
    for x in stride(from: rect.minX - 200, to: rect.maxX + 200, by: 70) {
        ctx.move(to: CGPoint(x: rect.midX, y: horizonY))
        ctx.addLine(to: CGPoint(x: x, y: rect.minY))
    }
    ctx.strokePath()
    ctx.restoreGState()
    
    // Glowing Neon Swift Bird
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 24, color: hexColor(0x00F5FF))
    drawSFSymbol(name: "swift", in: ctx, rect: rect.offsetBy(dx: 0, dy: 40), tintColor: hexColor(0xFFFFFF), pointSize: 310, weight: .bold)
    ctx.restoreGState()
}

// 11. Xcode Blueprint
func drawBlueprint(ctx: CGContext, rect: CGRect) {
    // Blueprint navy background
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x0F4C81), hexColor(0x072A4A)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // Technical drafting grid
    ctx.saveGState()
    ctx.setLineWidth(0.8)
    ctx.setStrokeColor(color(r: 1, g: 1, b: 1, a: 0.15))
    for x in stride(from: rect.minX, to: rect.maxX, by: 25) {
        ctx.move(to: CGPoint(x: x, y: rect.minY))
        ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
    }
    for y in stride(from: rect.minY, to: rect.maxY, by: 25) {
        ctx.move(to: CGPoint(x: rect.minX, y: y))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
    }
    ctx.strokePath()
    
    // Major grid lines
    ctx.setLineWidth(1.8)
    ctx.setStrokeColor(color(r: 1, g: 1, b: 1, a: 0.35))
    for x in stride(from: rect.minX, to: rect.maxX, by: 100) {
        ctx.move(to: CGPoint(x: x, y: rect.minY))
        ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
    }
    for y in stride(from: rect.minY, to: rect.maxY, by: 100) {
        ctx.move(to: CGPoint(x: rect.minX, y: y))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
    }
    ctx.strokePath()
    ctx.restoreGState()
    
    // Drafting circles and crosshairs
    ctx.saveGState()
    ctx.setLineWidth(2.0)
    ctx.setStrokeColor(color(r: 1, g: 1, b: 1, a: 0.5))
    ctx.addEllipse(in: rect.insetBy(dx: 180, dy: 180))
    ctx.strokePath()
    
    // White chalk drafted Curly Braces { }
    drawSFSymbol(name: "curlybraces", in: ctx, rect: rect, tintColor: color(r: 1, g: 1, b: 1, a: 0.95), pointSize: 340, weight: .light)
    
    // Technical measurement label
    drawText("R = 184.5px", in: ctx, rect: CGRect(x: rect.minX + 80, y: rect.minY + 60, width: 220, height: 40), fontName: "Helvetica", fontSize: 26, color: color(r: 1, g: 1, b: 1, a: 0.7), alignment: .left)
    drawText("W: 824.0px", in: ctx, rect: CGRect(x: rect.maxX - 300, y: rect.minY + 60, width: 220, height: 40), fontName: "Helvetica", fontSize: 26, color: color(r: 1, g: 1, b: 1, a: 0.7), alignment: .right)
    ctx.restoreGState()
}

// 12. Floppy Retro 1.44MB
func drawFloppyRetro(ctx: CGContext, rect: CGRect) {
    // Floppy disk black casing
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x272A30), hexColor(0x15171B)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // Metal Sliding Shutter at top
    let shutterRect = CGRect(x: rect.minX + 130, y: rect.maxY - 310, width: rect.width - 260, height: 280)
    let shutterPath = CGPath(roundedRect: shutterRect, cornerWidth: 20, cornerHeight: 20, transform: nil)
    ctx.saveGState()
    ctx.addPath(shutterPath)
    ctx.clip()
    drawLinearGradient(
        in: ctx, rect: shutterRect,
        colors: [hexColor(0xD2D6DC), hexColor(0x8B929D), hexColor(0xB0B7C1)],
        startPoint: CGPoint(x: shutterRect.midX, y: shutterRect.maxY),
        endPoint: CGPoint(x: shutterRect.midX, y: shutterRect.minY)
    )
    // Read/write cutout window
    let windowRect = CGRect(x: shutterRect.midX - 70, y: shutterRect.minY + 40, width: 140, height: 180)
    ctx.setFillColor(hexColor(0x15171B))
    ctx.fill(windowRect)
    ctx.restoreGState()
    
    // Paper Label at bottom
    let labelRect = CGRect(x: rect.minX + 90, y: rect.minY + 70, width: rect.width - 180, height: 380)
    let labelPath = CGPath(roundedRect: labelRect, cornerWidth: 16, cornerHeight: 16, transform: nil)
    ctx.saveGState()
    ctx.addPath(labelPath)
    ctx.clip()
    ctx.setFillColor(hexColor(0xF8F9FA))
    ctx.fill(labelRect)
    
    // Red/Blue header stripes on label
    ctx.setFillColor(hexColor(0xEF4444))
    ctx.fill(CGRect(x: labelRect.minX, y: labelRect.maxY - 20, width: labelRect.width, height: 10))
    ctx.setFillColor(hexColor(0x3B82F6))
    ctx.fill(CGRect(x: labelRect.minX, y: labelRect.maxY - 32, width: labelRect.width, height: 10))
    
    // Handwritten text
    drawText("SwiftCode v1.0", in: ctx, rect: CGRect(x: labelRect.minX + 30, y: labelRect.midY + 30, width: labelRect.width - 60, height: 60), fontName: "Courier-Bold", fontSize: 50, color: hexColor(0x1F2937), alignment: .left)
    drawText("Disk 1 of 1 [2HD]", in: ctx, rect: CGRect(x: labelRect.minX + 30, y: labelRect.midY - 40, width: labelRect.width - 60, height: 50), fontName: "Courier", fontSize: 36, color: hexColor(0x4B5563), alignment: .left)
    drawText("1.44 MB FORMATTED", in: ctx, rect: CGRect(x: labelRect.minX + 30, y: labelRect.midY - 110, width: labelRect.width - 60, height: 40), fontName: "Courier-Bold", fontSize: 30, color: hexColor(0x9CA3AF), alignment: .left)
    ctx.restoreGState()
}

// 13. Curly Braces { }
func drawCodeBraces(ctx: CGContext, rect: CGRect) {
    // Dark code editor background
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x1A102F), hexColor(0x0A0614)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // Glowing Curly Braces
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 36, color: hexColor(0x8B5CF6))
    drawSFSymbol(name: "curlybraces", in: ctx, rect: rect, tintColor: hexColor(0xC084FC), pointSize: 420, weight: .bold)
    ctx.restoreGState()
    
    // Syntax Dots (Green, Orange, Pink)
    let dotY = rect.midY
    let dotColors = [hexColor(0x10B981), hexColor(0xF59E0B), hexColor(0xEC4899)]
    for (i, c) in dotColors.enumerated() {
        let x = rect.midX - 60 + CGFloat(i * 60)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 14, color: c)
        ctx.setFillColor(c)
        ctx.fillEllipse(in: CGRect(x: x - 12, y: dotY - 12, width: 24, height: 24))
        ctx.restoreGState()
    }
}

// 14. Terminal Prompt >_
func drawTerminalCli(ctx: CGContext, rect: CGRect) {
    // Dark terminal canvas
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x1E222B), hexColor(0x0F1116)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // macOS traffic lights at top
    let trafficY = rect.maxY - 110
    let trafficColors = [hexColor(0xFF5F56), hexColor(0xFFBD2E), hexColor(0x27C93F)]
    for (i, c) in trafficColors.enumerated() {
        let x = rect.minX + 90 + CGFloat(i * 44)
        ctx.setFillColor(c)
        ctx.fillEllipse(in: CGRect(x: x, y: trafficY, width: 26, height: 26))
    }
    
    // Giant glowing prompt: >_
    ctx.saveGState()
    let cyan = hexColor(0x00F0FF)
    ctx.setShadow(offset: .zero, blur: 32, color: cyan)
    drawText(">_", in: ctx, rect: rect.offsetBy(dx: 0, dy: -20), fontName: "Menlo-Bold", fontSize: 280, color: cyan)
    ctx.restoreGState()
}

// 15. Markup Tag </>
func drawMarkupTag(ctx: CGContext, rect: CGRect) {
    // Dark violet background
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x24123A), hexColor(0x0E0519)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // Center </> symbol with magenta & cyan glow
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 36, color: hexColor(0xD946EF))
    drawSFSymbol(name: "chevron.left.forwardslash.chevron.right", in: ctx, rect: rect, tintColor: hexColor(0xF0ABFC), pointSize: 360, weight: .bold)
    ctx.restoreGState()
}

// 16. Lambda Closure λ
func drawLambdaClosure(ctx: CGContext, rect: CGRect) {
    // Deep dark teal background
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x062A32), hexColor(0x021115)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // Radiant turquoise Greek Lambda λ
    ctx.saveGState()
    let turquoise = hexColor(0x2DD4BF)
    ctx.setShadow(offset: .zero, blur: 36, color: turquoise)
    drawText("λ", in: ctx, rect: rect.offsetBy(dx: 0, dy: 10), fontName: "Times-Bold", fontSize: 440, color: turquoise)
    ctx.restoreGState()
    
    // Functional closure hint
    drawText("{ (x) in x * 2 }", in: ctx, rect: CGRect(x: rect.minX, y: rect.minY + 90, width: rect.width, height: 40), fontName: "Menlo-Bold", fontSize: 32, color: hexColor(0x14B8A6))
}

// 17. Silicon Processor
func drawSiliconChip(ctx: CGContext, rect: CGRect) {
    // Matte dark semiconductor substrate
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x282C35), hexColor(0x15171C)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // Gold Bus Traces radiating from center
    ctx.saveGState()
    ctx.setLineWidth(3)
    ctx.setStrokeColor(hexColor(0xD4AF37, alpha: 0.65))
    for angle in stride(from: 0.0, to: Double.pi * 2, by: Double.pi / 8) {
        let start = CGPoint(x: rect.midX + cos(angle) * 160, y: rect.midY + sin(angle) * 160)
        let mid = CGPoint(x: rect.midX + cos(angle) * 260, y: rect.midY + sin(angle) * 260)
        let end = CGPoint(x: rect.midX + cos(angle) * 350, y: rect.midY + sin(angle) * 350)
        ctx.move(to: start)
        ctx.addLine(to: mid)
        ctx.addLine(to: end)
    }
    ctx.strokePath()
    ctx.restoreGState()
    
    // Central Silicon Die square with gold rim
    let dieRect = rect.insetBy(dx: 220, dy: 220)
    let diePath = CGPath(roundedRect: dieRect, cornerWidth: 32, cornerHeight: 32, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: color(r: 0, g: 0, b: 0, a: 0.6))
    ctx.setFillColor(hexColor(0x0A0B0E))
    ctx.addPath(diePath)
    ctx.fillPath()
    
    // Gold bevel rim
    ctx.setLineWidth(5)
    ctx.setStrokeColor(hexColor(0xFFD700))
    ctx.addPath(diePath)
    ctx.strokePath()
    
    // Laser etched Swift core
    drawSFSymbol(name: "swift", in: ctx, rect: dieRect, tintColor: hexColor(0xFFD700), pointSize: 220, weight: .bold)
    ctx.restoreGState()
}

// 18. Bug Hunter
func drawBugHunter(ctx: CGContext, rect: CGRect) {
    // Tactical radar dark olive slate
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x13211B), hexColor(0x08100C)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // Radar concentric circles
    ctx.saveGState()
    ctx.setLineWidth(2)
    ctx.setStrokeColor(hexColor(0x10B981, alpha: 0.35))
    ctx.addEllipse(in: rect.insetBy(dx: 120, dy: 120))
    ctx.addEllipse(in: rect.insetBy(dx: 220, dy: 220))
    ctx.addEllipse(in: rect.insetBy(dx: 310, dy: 310))
    // Crosshairs
    ctx.move(to: CGPoint(x: rect.minX + 90, y: rect.midY))
    ctx.addLine(to: CGPoint(x: rect.maxX - 90, y: rect.midY))
    ctx.move(to: CGPoint(x: rect.midX, y: rect.minY + 90))
    ctx.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 90))
    ctx.strokePath()
    ctx.restoreGState()
    
    // Glowing Emerald Beetle Bug in crosshairs
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30, color: hexColor(0x10B981))
    drawSFSymbol(name: "ladybug.fill", in: ctx, rect: rect, tintColor: hexColor(0x34D399), pointSize: 340, weight: .bold)
    ctx.restoreGState()
}

// 19. Git Branch Tree
func drawGitBranch(ctx: CGContext, rect: CGRect) {
    // Dark commit graph canvas
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x181F2C), hexColor(0x0C1017)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // Branching lines
    ctx.saveGState()
    ctx.setLineWidth(14)
    ctx.setLineCap(.round)
    
    // Main branch (orange)
    ctx.setStrokeColor(hexColor(0xF97316))
    ctx.move(to: CGPoint(x: rect.minX + 220, y: rect.minY + 140))
    ctx.addLine(to: CGPoint(x: rect.minX + 220, y: rect.maxY - 140))
    ctx.strokePath()
    
    // Feature branch (cyan curve)
    ctx.setStrokeColor(hexColor(0x06B6D4))
    ctx.move(to: CGPoint(x: rect.minX + 220, y: rect.minY + 280))
    ctx.addCurve(
        to: CGPoint(x: rect.maxX - 240, y: rect.midY + 50),
        control1: CGPoint(x: rect.minX + 220, y: rect.midY - 40),
        control2: CGPoint(x: rect.maxX - 240, y: rect.midY - 40)
    )
    ctx.addLine(to: CGPoint(x: rect.maxX - 240, y: rect.maxY - 140))
    ctx.strokePath()
    ctx.restoreGState()
    
    // Commit Nodes (glowing circles)
    let nodes: [(x: CGFloat, y: CGFloat, color: UInt32)] = [
        (rect.minX + 220, rect.minY + 200, 0xF97316),
        (rect.minX + 220, rect.minY + 380, 0xF97316),
        (rect.minX + 220, rect.maxY - 200, 0xF97316),
        (rect.maxX - 240, rect.midY + 90, 0x06B6D4),
        (rect.maxX - 240, rect.maxY - 200, 0x06B6D4),
    ]
    for n in nodes {
        ctx.saveGState()
        let c = hexColor(n.color)
        ctx.setShadow(offset: .zero, blur: 18, color: c)
        ctx.setFillColor(c)
        ctx.fillEllipse(in: CGRect(x: n.x - 24, y: n.y - 24, width: 48, height: 48))
        ctx.setFillColor(hexColor(0xFFFFFF))
        ctx.fillEllipse(in: CGRect(x: n.x - 10, y: n.y - 10, width: 20, height: 20))
        ctx.restoreGState()
    }
}

// 20. Turbo Compiler ⚡️
func drawCompilerTurbo(ctx: CGContext, rect: CGRect) {
    // High voltage dark background
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x2A1E07), hexColor(0x120C02)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // Hazard chevron bottom stripes
    ctx.saveGState()
    let hazardY = rect.minY + 40
    for i in 0..<10 {
        let x = rect.minX + CGFloat(i * 80)
        ctx.setFillColor(i % 2 == 0 ? hexColor(0xF59E0B) : hexColor(0x1F1A12))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: hazardY))
        path.addLine(to: CGPoint(x: x + 40, y: hazardY + 40))
        path.addLine(to: CGPoint(x: x + 70, y: hazardY + 40))
        path.addLine(to: CGPoint(x: x + 30, y: hazardY))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
    }
    ctx.restoreGState()
    
    // High voltage lightning bolt
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: hexColor(0xFBBF24))
    drawSFSymbol(name: "bolt.fill", in: ctx, rect: rect.offsetBy(dx: 0, dy: 20), tintColor: hexColor(0xFDE047), pointSize: 380, weight: .black)
    ctx.restoreGState()
}

// 21. Cyberpunk Neon
func drawCyberpunk(ctx: CGContext, rect: CGRect) {
    // Dark carbon tile
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x181528), hexColor(0x090710)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // Neon outer border frame (Hot Pink & Electric Cyan)
    let frameRect = rect.insetBy(dx: 70, dy: 70)
    let framePath = CGPath(roundedRect: frameRect, cornerWidth: 50, cornerHeight: 50, transform: nil)
    ctx.saveGState()
    ctx.setLineWidth(8)
    ctx.setShadow(offset: .zero, blur: 24, color: hexColor(0xFF0055))
    ctx.setStrokeColor(hexColor(0xFF0055))
    ctx.addPath(framePath)
    ctx.strokePath()
    ctx.restoreGState()
    
    // Neon Swift bird with cyan glow
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 32, color: hexColor(0x00F0FF))
    drawSFSymbol(name: "swift", in: ctx, rect: rect, tintColor: hexColor(0x00F0FF), pointSize: 330, weight: .bold)
    ctx.restoreGState()
}

// 22. Matrix Rain
func drawMatrixRain(ctx: CGContext, rect: CGRect) {
    // Pitch black background
    ctx.setFillColor(hexColor(0x000000))
    ctx.fill(rect)
    
    // Vertical code rain streams
    let glyphs = ["0", "1", "7", "X", "λ", "9", "Z", "4", "A", "8"]
    let cols = 14
    let colWidth = rect.width / CGFloat(cols)
    
    for c in 0..<cols {
        let x = rect.minX + CGFloat(c) * colWidth + colWidth / 2
        let startRow = (c * 3) % 8
        for r in startRow..<16 {
            let y = rect.maxY - 90 - CGFloat(r * 48)
            let isHead = (r == startRow)
            let charColor = isHead ? hexColor(0xFFFFFF) : hexColor(0x00FF41, alpha: max(0.15, 1.0 - CGFloat(r - startRow) * 0.12))
            let glyph = glyphs[(c * 7 + r) % glyphs.count]
            drawText(glyph, in: ctx, rect: CGRect(x: x - 20, y: y, width: 40, height: 40), fontName: "Menlo-Bold", fontSize: 32, color: charColor)
        }
    }
    
    // Centered glowing Swift symbol watermark
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 28, color: hexColor(0x00FF41))
    drawSFSymbol(name: "swift", in: ctx, rect: rect, tintColor: hexColor(0x00FF41, alpha: 0.85), pointSize: 320, weight: .bold)
    ctx.restoreGState()
}

// 23. Dracula Vampire
func drawDracula(ctx: CGContext, rect: CGRect) {
    // Dracula slate background
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x282A36), hexColor(0x1E1F29)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // Dracula Purple ambient glow
    drawRadialGradient(
        in: ctx, center: CGPoint(x: rect.midX, y: rect.midY),
        startRadius: 40, endRadius: 380,
        colors: [hexColor(0xBD93F9, alpha: 0.35), hexColor(0x282A36, alpha: 0.0)]
    )
    
    // Center Swift emblem in Dracula Pink
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 28, color: hexColor(0xFF79C6))
    drawSFSymbol(name: "swift", in: ctx, rect: rect, tintColor: hexColor(0xFF79C6), pointSize: 330, weight: .bold)
    ctx.restoreGState()
    
    // Dracula accent dots (Cyan & Green)
    let dotY = rect.minY + 90
    ctx.setFillColor(hexColor(0x8BE9FD))
    ctx.fillEllipse(in: CGRect(x: rect.midX - 40, y: dotY, width: 22, height: 22))
    ctx.setFillColor(hexColor(0x50FA7B))
    ctx.fillEllipse(in: CGRect(x: rect.midX + 18, y: dotY, width: 22, height: 22))
}

// 24. Monokai Pro
func drawMonokai(ctx: CGContext, rect: CGRect) {
    // Monokai Pro charcoal
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x2D2A2E), hexColor(0x1F1D20)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // Center Swift emblem in Monokai Coral Red
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 28, color: hexColor(0xFF6188))
    drawSFSymbol(name: "swift", in: ctx, rect: rect, tintColor: hexColor(0xFF6188), pointSize: 330, weight: .bold)
    ctx.restoreGState()
    
    // Monokai Syntax Dot Palette
    let dots = [hexColor(0xFFD866), hexColor(0xA9DC76), hexColor(0x78DCE8), hexColor(0xAB9DF2)]
    let startX = rect.midX - 90
    for (i, d) in dots.enumerated() {
        ctx.setFillColor(d)
        ctx.fillEllipse(in: CGRect(x: startX + CGFloat(i * 50), y: rect.minY + 90, width: 22, height: 22))
    }
}

// 25. Solarized Dark
func drawSolarized(ctx: CGContext, rect: CGRect) {
    // Solarized Base03 / Base02
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x002B36), hexColor(0x073642)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // Center Swift emblem in Solarized Yellow & Orange
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 24, color: hexColor(0xB58900))
    drawSFSymbol(name: "swift", in: ctx, rect: rect, tintColor: hexColor(0xB58900), pointSize: 330, weight: .bold)
    ctx.restoreGState()
    
    // Solarized Cyan and Blue dots
    ctx.setFillColor(hexColor(0x2AA198))
    ctx.fillEllipse(in: CGRect(x: rect.midX - 40, y: rect.minY + 90, width: 22, height: 22))
    ctx.setFillColor(hexColor(0x268BD2))
    ctx.fillEllipse(in: CGRect(x: rect.midX + 18, y: rect.minY + 90, width: 22, height: 22))
}

// 26. Midnight Ultraviolet
func drawMidnightPurple(ctx: CGContext, rect: CGRect) {
    // Deep galactic violet
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x2E1065), hexColor(0x0F051D)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // Ultraviolet nebula glow
    drawRadialGradient(
        in: ctx, center: CGPoint(x: rect.midX, y: rect.midY),
        startRadius: 40, endRadius: 420,
        colors: [hexColor(0xA855F7, alpha: 0.5), hexColor(0x2E1065, alpha: 0.0)]
    )
    
    // Glowing Ultraviolet Swift Bird
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 36, color: hexColor(0xC084FC))
    drawSFSymbol(name: "swift", in: ctx, rect: rect, tintColor: hexColor(0xF3E8FF), pointSize: 330, weight: .bold)
    ctx.restoreGState()
}

// 27. 24K Bullion Gold
func drawPureGold(ctx: CGContext, rect: CGRect) {
    // Brushed metallic 24K gold bullion
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0xFFEAA7), hexColor(0xD4AF37), hexColor(0xAA7C11), hexColor(0xFFE082)],
        startPoint: CGPoint(x: rect.minX, y: rect.maxY),
        endPoint: CGPoint(x: rect.maxX, y: rect.minY)
    )
    
    // 3D Chamfered inner frame
    let insetRect = rect.insetBy(dx: 45, dy: 45)
    let insetPath = CGPath(roundedRect: insetRect, cornerWidth: cornerRadius * 0.85, cornerHeight: cornerRadius * 0.85, transform: nil)
    ctx.saveGState()
    ctx.setLineWidth(4)
    ctx.setStrokeColor(hexColor(0xFFF9C4, alpha: 0.8))
    ctx.addPath(insetPath)
    ctx.strokePath()
    ctx.restoreGState()
    
    // Debossed stamped Swift emblem
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 10, color: hexColor(0x5A3E00, alpha: 0.8))
    drawSFSymbol(name: "swift", in: ctx, rect: rect, tintColor: hexColor(0x8C6510), pointSize: 330, weight: .bold)
    ctx.restoreGState()
    
    // Top highlight rim
    ctx.saveGState()
    drawSFSymbol(name: "swift", in: ctx, rect: rect.offsetBy(dx: 0, dy: 4), tintColor: hexColor(0xFFFDE7, alpha: 0.6), pointSize: 330, weight: .bold)
    ctx.restoreGState()
}

// 28. Brushed Titanium
func drawTitanium(ctx: CGContext, rect: CGRect) {
    // Circular radial brushed titanium
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x565E6B), hexColor(0x2B2F38), hexColor(0x404753)],
        startPoint: CGPoint(x: rect.minX, y: rect.minY),
        endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
    )
    
    // Circular machining tracks
    ctx.saveGState()
    ctx.setLineWidth(1.5)
    ctx.setStrokeColor(color(r: 1, g: 1, b: 1, a: 0.12))
    for r in stride(from: 60.0, to: 420.0, by: 45.0) {
        ctx.addEllipse(in: rect.insetBy(dx: rect.width / 2 - r, dy: rect.height / 2 - r))
    }
    ctx.strokePath()
    ctx.restoreGState()
    
    // Laser engraved Swift symbol
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 6, color: color(r: 0, g: 0, b: 0, a: 0.6))
    drawSFSymbol(name: "swift", in: ctx, rect: rect, tintColor: hexColor(0xD1D5DB), pointSize: 330, weight: .bold)
    ctx.restoreGState()
}

// 29. Emerald Gemstone
func drawEmerald(ctx: CGContext, rect: CGRect) {
    // Deep royal emerald
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x064E3B), hexColor(0x022C22)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // Gemstone crystalline facets
    ctx.saveGState()
    ctx.setLineWidth(2)
    ctx.setStrokeColor(hexColor(0x34D399, alpha: 0.35))
    let corners = [
        CGPoint(x: rect.minX + 160, y: rect.minY + 160),
        CGPoint(x: rect.maxX - 160, y: rect.minY + 160),
        CGPoint(x: rect.maxX - 160, y: rect.maxY - 160),
        CGPoint(x: rect.minX + 160, y: rect.maxY - 160)
    ]
    let center = CGPoint(x: rect.midX, y: rect.midY)
    for pt in corners {
        ctx.move(to: center)
        ctx.addLine(to: pt)
    }
    ctx.strokePath()
    ctx.restoreGState()
    
    // Luminous Emerald Swift Bird
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 32, color: hexColor(0x10B981))
    drawSFSymbol(name: "swift", in: ctx, rect: rect, tintColor: hexColor(0x6EE7B7), pointSize: 330, weight: .bold)
    ctx.restoreGState()
}

// 30. Ocean Abyss
func drawOceanAbyss(ctx: CGContext, rect: CGRect) {
    // Deep trench ocean navy to teal
    drawLinearGradient(
        in: ctx, rect: rect,
        colors: [hexColor(0x0C4A6E), hexColor(0x021B2A)],
        startPoint: CGPoint(x: rect.midX, y: rect.maxY),
        endPoint: CGPoint(x: rect.midX, y: rect.minY)
    )
    
    // Bioluminescent Caustics
    drawRadialGradient(
        in: ctx, center: CGPoint(x: rect.midX, y: rect.midY - 40),
        startRadius: 30, endRadius: 400,
        colors: [hexColor(0x38BDF8, alpha: 0.45), hexColor(0x0C4A6E, alpha: 0.0)]
    )
    
    // Luminous Bioluminescent Swift Bird
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 36, color: hexColor(0x38BDF8))
    drawSFSymbol(name: "swift", in: ctx, rect: rect, tintColor: hexColor(0xE0F2FE), pointSize: 330, weight: .bold)
    ctx.restoreGState()
}

// MARK: - Asset Catalog Generation Engine

func savePNG(image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    let destDir = url.deletingLastPathComponent().path
    try? FileManager.default.createDirectory(atPath: destDir, withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    _ = CGImageDestinationFinalize(dest)
}

func resize(image: CGImage, to size: Int) -> CGImage? {
    guard let ctx = createBaseContext(size: CGFloat(size)) else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()
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

// AppIcon contents.json generator
func writeAppIconContentsJSON(to setDir: String) {
    let json = """
    {
      "images" : [
        { "filename" : "icon_16x16@1x.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
        { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
        { "filename" : "icon_32x32@1x.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
        { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
        { "filename" : "icon_128x128@1x.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
        { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
        { "filename" : "icon_256x256@1x.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
        { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
        { "filename" : "icon_512x512@1x.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
        { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" },
        { "filename" : "AppIcon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }
    """
    try? json.write(toFile: "\(setDir)/Contents.json", atomically: true, encoding: .utf8)
}

func writePreviewContentsJSON(to previewSetDir: String) {
    let json = """
    {
      "images" : [
        { "filename" : "preview.png", "idiom" : "universal" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }
    """
    try? json.write(toFile: "\(previewSetDir)/Contents.json", atomically: true, encoding: .utf8)
}

func exportIconSet(name: String, macMaster: CGImage, universalMaster: CGImage) {
    let setDir = "\(baseAssetsDir)/AppIcon-\(name).appiconset"
    savePNG(image: universalMaster, to: "\(setDir)/AppIcon-1024.png")
    for entry in macSizes {
        if let scaled = resize(image: macMaster, to: entry.pixel) {
            savePNG(image: scaled, to: "\(setDir)/icon_\(entry.point)x\(entry.point)@\(entry.scale)x.png")
        }
    }
    writeAppIconContentsJSON(to: setDir)
    
    // Preview Imageset for in-app UI & dynamic dock icon
    let previewSetDir = "\(baseAssetsDir)/AppIcon-Preview-\(name).imageset"
    if let previewImg = resize(image: macMaster, to: 512) {
        savePNG(image: previewImg, to: "\(previewSetDir)/preview.png")
        writePreviewContentsJSON(to: previewSetDir)
    }
    print("Exported: \(name)")
}

// MARK: - Process Existing 4 Liquid Glass Icons

struct ExistingIconSpec {
    let name: String
    let sourcePath: String
    let cropRect: CGRect
}

let existingSpecs: [ExistingIconSpec] = [
    ExistingIconSpec(name: "Light", sourcePath: "/Users/dylan/.gemini/antigravity-ide/brain/23dd43fd-ef9c-40aa-89a6-6f824bdf1c40/icon_light_mode_1788751657841.jpg", cropRect: CGRect(x: 128, y: 127, width: 766, height: 767)),
    ExistingIconSpec(name: "Dark", sourcePath: "/Users/dylan/.gemini/antigravity-ide/brain/23dd43fd-ef9c-40aa-89a6-6f824bdf1c40/icon_dark_mode_1788751677454.jpg", cropRect: CGRect(x: 185, y: 185, width: 650, height: 648)),
    ExistingIconSpec(name: "Glass", sourcePath: "/Users/dylan/.gemini/antigravity-ide/brain/23dd43fd-ef9c-40aa-89a6-6f824bdf1c40/icon_glass_mode_1788751741542.jpg", cropRect: CGRect(x: 114, y: 115, width: 792, height: 792)),
    ExistingIconSpec(name: "Tinted", sourcePath: "/Users/dylan/.gemini/antigravity-ide/brain/23dd43fd-ef9c-40aa-89a6-6f824bdf1c40/icon_tinted_mode_1788751949881.jpg", cropRect: CGRect(x: 185, y: 185, width: 651, height: 652))
]

func cropImage(cgImage: CGImage, cropRect: CGRect) -> CGImage? {
    let cgCropRect = CGRect(x: cropRect.origin.x, y: CGFloat(cgImage.height) - cropRect.origin.y - cropRect.size.height, width: cropRect.size.width, height: cropRect.size.height)
    return cgImage.cropping(to: cgCropRect)
}

for spec in existingSpecs {
    let url = URL(fileURLWithPath: spec.sourcePath)
    guard let nsImg = NSImage(contentsOf: url),
          let cg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let cropped = cropImage(cgImage: cg, cropRect: spec.cropRect) else {
        print("Skipping existing \(spec.name) (source missing)")
        continue
    }
    
    let macMaster = renderMacSquircle { ctx, rect in
        ctx.draw(cropped, in: rect)
    }!
    let universalMaster = renderUniversal { ctx, rect in
        ctx.draw(cropped, in: rect)
    }!
    exportIconSet(name: spec.name, macMaster: macMaster, universalMaster: universalMaster)
}

// MARK: - Process 26 Vector Icons

struct VectorIconSpec {
    let name: String
    let draw: (CGContext, CGRect) -> Void
}

let vectorSpecs: [VectorIconSpec] = [
    // Nostalgia & Heritage
    VectorIconSpec(name: "RetroMac", draw: drawRetroMac),
    VectorIconSpec(name: "Aqua2001", draw: drawAqua2001),
    VectorIconSpec(name: "NeXTSTEP", draw: drawNeXTSTEP),
    VectorIconSpec(name: "CRTGreen", draw: drawPhosphorCRT),
    VectorIconSpec(name: "CRTAmber", draw: drawAmberCRT),
    VectorIconSpec(name: "Synthwave", draw: drawSynthwave),
    VectorIconSpec(name: "Blueprint", draw: drawBlueprint),
    VectorIconSpec(name: "FloppyRetro", draw: drawFloppyRetro),
    
    // Developer & Coding Symbols
    VectorIconSpec(name: "CodeBraces", draw: drawCodeBraces),
    VectorIconSpec(name: "TerminalCli", draw: drawTerminalCli),
    VectorIconSpec(name: "MarkupTag", draw: drawMarkupTag),
    VectorIconSpec(name: "LambdaClosure", draw: drawLambdaClosure),
    VectorIconSpec(name: "SiliconChip", draw: drawSiliconChip),
    VectorIconSpec(name: "BugHunter", draw: drawBugHunter),
    VectorIconSpec(name: "GitBranch", draw: drawGitBranch),
    VectorIconSpec(name: "CompilerTurbo", draw: drawCompilerTurbo),
    
    // Syntax & Themes
    VectorIconSpec(name: "Cyberpunk", draw: drawCyberpunk),
    VectorIconSpec(name: "MatrixRain", draw: drawMatrixRain),
    VectorIconSpec(name: "Dracula", draw: drawDracula),
    VectorIconSpec(name: "Monokai", draw: drawMonokai),
    VectorIconSpec(name: "Solarized", draw: drawSolarized),
    VectorIconSpec(name: "MidnightPurple", draw: drawMidnightPurple),
    
    // Luxury Materials
    VectorIconSpec(name: "PureGold", draw: drawPureGold),
    VectorIconSpec(name: "Titanium", draw: drawTitanium),
    VectorIconSpec(name: "Emerald", draw: drawEmerald),
    VectorIconSpec(name: "OceanAbyss", draw: drawOceanAbyss)
]

for spec in vectorSpecs {
    guard let macMaster = renderMacSquircle(drawArtwork: spec.draw),
          let universalMaster = renderUniversal(drawArtwork: spec.draw) else {
        print("Failed to render \(spec.name)")
        continue
    }
    exportIconSet(name: spec.name, macMaster: macMaster, universalMaster: universalMaster)
}

print("\nSuccessfully generated all 30 app icons, multi-scale iconsets, and preview imagesets!")
