import AppKit

// Draws the artwork behind the installer window: an arrow from the app to the
// Applications folder, plus one line of instruction.

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = CGSize(width: 640, height: 400)

func render(scale: CGFloat) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width * scale),
        pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: size.width, height: size.height)

    guard let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.setShouldAntialias(true)

    // Flat white: any gradient shows a seam against the window chrome.
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(origin: .zero, size: size))

    // Arrow, drawn in Cocoa coordinates so y grows upwards.
    let arrowY = size.height - 190
    let shaft = CGRect(x: 268, y: arrowY - 7, width: 74, height: 14)
    context.addPath(CGPath(roundedRect: shaft, cornerWidth: 7, cornerHeight: 7, transform: nil))
    context.setFillColor(NSColor(calibratedWhite: 0.62, alpha: 1).cgColor)
    context.fillPath()

    let head = CGMutablePath()
    head.move(to: CGPoint(x: 372, y: arrowY))
    head.addLine(to: CGPoint(x: 336, y: arrowY + 24))
    head.addLine(to: CGPoint(x: 336, y: arrowY - 24))
    head.closeSubpath()
    context.addPath(head)
    context.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for (scale, suffix) in [(CGFloat(1), ""), (CGFloat(2), "@2x")] {
    guard let data = render(scale: scale) else { continue }
    let base = output.deletingPathExtension().lastPathComponent
    let url = output.deletingLastPathComponent()
        .appendingPathComponent(base + suffix + ".png")
    try data.write(to: url)
    print(url.lastPathComponent)
}
