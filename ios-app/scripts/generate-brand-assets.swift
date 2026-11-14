// Generates Rook's brand images from the ROOK wordmark design (wide-tracked, squared geometric sans
// in light gray on the app's gunmetal background).
//
//   swift scripts/generate-brand-assets.swift
//
// Outputs (into Rook/Resources/Assets.xcassets):
//   AppIcon.appiconset/AppIcon-1024.png   wordmark centered on the background color (opaque, as Apple requires)
//   Wordmark.imageset/Wordmark@3x.png     transparent wordmark for the launch screen and in-app headers
//
// The background must stay identical to `Theme.background` and the `LaunchBackground` color so the logo
// blends seamlessly into the app. To use final artwork instead, replace the two PNGs and delete this script.
import AppKit

let background = NSColor(srgbRed: 0x11 / 255, green: 0x11 / 255, blue: 0x18 / 255, alpha: 1)
let letterTop = NSColor(srgbRed: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF6 / 255, alpha: 1)
let letterBottom = NSColor(srgbRed: 0xC9 / 255, green: 0xC9 / 255, blue: 0xD0 / 255, alpha: 1)
let fontName = "DINAlternate-Bold"
let horizontalStretch: CGFloat = 1.22 // the design's letters are wider than DIN's

let assets = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Rook/Resources/Assets.xcassets")

/// Draws the wordmark so it spans `width` points, centered in `rect`.
func drawWordmark(in rect: NSRect, width: CGFloat) {
    guard let font = NSFont(name: fontName, size: 100) else { fatalError("Font \(fontName) not installed") }
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: 52]
    let text = NSAttributedString(string: "ROOK", attributes: attributes)
    // Trailing kern after the last letter shouldn't count toward the visual width.
    let rawSize = text.size()
    let visualWidth = (rawSize.width - 52) * horizontalStretch
    let scale = width / visualWidth
    let capHeight = font.capHeight * scale

    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: rect.midX - width / 2, yBy: rect.midY - capHeight / 2 - (-font.descender) * scale)
    transform.scaleX(by: scale * horizontalStretch, yBy: scale)
    transform.concat()

    // Clip to the glyph shapes, then fill a subtle top-to-bottom gradient (as in the design).
    let path = NSBezierPath()
    let storage = NSTextStorage(attributedString: text)
    let layout = NSLayoutManager()
    let container = NSTextContainer(size: NSSize(width: 10_000, height: 1_000))
    layout.addTextContainer(container)
    storage.addLayoutManager(layout)
    let glyphRange = layout.glyphRange(for: container)
    var glyphs = [CGGlyph](repeating: 0, count: glyphRange.length)
    _ = layout.getGlyphs(in: glyphRange, glyphs: &glyphs, properties: nil, characterIndexes: nil, bidiLevels: nil)
    for (i, glyph) in glyphs.enumerated() {
        let location = layout.location(forGlyphAt: i)
        path.move(to: NSPoint(x: location.x, y: -font.descender))
        path.append(withCGGlyph: glyph, in: font)
    }
    path.addClip()
    NSGradient(starting: letterTop, ending: letterBottom)!
        .draw(in: NSRect(x: 0, y: -font.descender, width: rawSize.width, height: font.capHeight), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
}

func render(size: NSSize, opaque: Bool, wordmarkWidth: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let rect = NSRect(origin: .zero, size: size)
    if opaque {
        background.setFill()
        rect.fill()
    } else {
        NSColor.clear.setFill()
        rect.fill(using: .copy)
    }
    drawWordmark(in: rect, width: wordmarkWidth)
    NSGraphicsContext.restoreGraphicsState()
    if opaque {
        // App Store icons must not contain an alpha channel: redraw into an RGB (no alpha) context.
        let cg = rep.cgImage!
        let context = CGContext(
            data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }
    return rep.representation(using: .png, properties: [:])!
}

func write(_ data: Data, to relative: String) {
    let url = assets.appendingPathComponent(relative)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! data.write(to: url)
    print("wrote \(relative)")
}

write(render(size: NSSize(width: 1024, height: 1024), opaque: true, wordmarkWidth: 760), to: "AppIcon.appiconset/AppIcon-1024.png")
// 220pt × 60pt at @3x.
write(render(size: NSSize(width: 660, height: 180), opaque: false, wordmarkWidth: 640), to: "Wordmark.imageset/Wordmark@3x.png")
