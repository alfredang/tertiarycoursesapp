import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// TC LMS app icon: "TC" monogram over "LMS <country>" on the deep-blue brand gradient.
// Opaque sRGB Core Graphics context + ImageIO export (no alpha, never the
// NSImage path, which has produced all-black icons).
//
//   swift scripts/make_icon.swift <COUNTRY> <out.png> [size=1024] [--foreground]
//
// --foreground renders only the white lettering on a transparent canvas,
// inside the Android adaptive-icon safe zone (the background colour is set
// separately in the Android project).

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: make_icon.swift <COUNTRY> <out.png> [size] [--foreground]")
    exit(2)
}
let country = args[1]
let out = URL(fileURLWithPath: args[2])
let size = args.count > 3 ? Int(args[3]) ?? 1024 : 1024
let foreground = args.contains("--foreground")

let S = CGFloat(size)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: foreground ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)!

if !foreground {
    // Deep-blue vertical gradient: #0D3E91 (top) → #0A2D6F (bottom).
    let top = CGColor(colorSpace: space, components: [13 / 255, 62 / 255, 145 / 255, 1])!
    let bottom = CGColor(colorSpace: space, components: [10 / 255, 45 / 255, 111 / 255, 1])!
    let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
}

func draw(_ text: String, size pt: CGFloat, weight: CGFloat, centerY: CGFloat, tracking: CGFloat = 0) {
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, pt, nil)
    let white = CGColor(colorSpace: space, components: [1, 1, 1, 1])!
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): white,
        NSAttributedString.Key(kCTKernAttributeName as String): tracking,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: (S - bounds.width) / 2 - bounds.minX, y: centerY - bounds.height / 2 - bounds.minY)
    CTLineDraw(line, ctx)
}

// Android's adaptive icon crops to the inner ~61% circle, so shrink the art there.
let k: CGFloat = foreground ? 0.62 : 1.0
let mid = S / 2
draw("TC", size: S * 0.40 * k, weight: 1, centerY: mid + S * 0.11 * k, tracking: S * 0.01 * k)
draw("LMS \(country)", size: S * 0.15 * k, weight: 1, centerY: mid - S * 0.20 * k, tracking: S * 0.004 * k)

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
print("wrote \(out.path) (\(size)px\(foreground ? ", foreground" : ""))")
