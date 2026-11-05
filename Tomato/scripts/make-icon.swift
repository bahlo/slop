// Renders the app icon (white timer symbol on a tomato-red rounded rect)
// into an .iconset directory for iconutil. Run: swift scripts/make-icon.swift <outdir>
// No asset catalogs / actool — works with Command Line Tools only.
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dist/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let variants: [(pixels: Int, name: String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let side = CGFloat(pixels)
    // macOS icon grid: content inset ~10% with a continuous-ish corner radius.
    let inset = side * 0.09
    let rect = NSRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let background = NSBezierPath(roundedRect: rect, xRadius: side * 0.185, yRadius: side * 0.185)
    NSColor(srgbRed: 0.85, green: 0.27, blue: 0.21, alpha: 1).setFill()
    background.fill()

    let configuration = NSImage.SymbolConfiguration(pointSize: side * 0.42, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
    {
        let symbolSize = symbol.size
        let scale = (side * 0.52) / max(symbolSize.width, symbolSize.height)
        let drawSize = NSSize(width: symbolSize.width * scale, height: symbolSize.height * scale)
        let origin = NSPoint(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2)
        symbol.draw(
            in: NSRect(origin: origin, size: drawSize),
            from: .zero, operation: .sourceOver, fraction: 1
        )
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for variant in variants {
    let rep = render(pixels: variant.pixels)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed for \(variant.name)")
    }
    let path = "\(outDir)/\(variant.name).png"
    try png.write(to: URL(fileURLWithPath: path))
}
print("Wrote \(variants.count) icons to \(outDir)")
