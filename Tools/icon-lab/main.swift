import AppKit

// Renders candidate app icons so they can be compared at real sizes.

typealias Stop = (r: CGFloat, g: CGFloat, b: CGFloat)

func color(_ s: Stop) -> NSColor { NSColor(calibratedRed: s.r, green: s.g, blue: s.b, alpha: 1) }

func canvas(_ pixels: Int, _ draw: (CGContext, CGFloat) -> Void) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)
    guard let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.cgContext.setShouldAntialias(true)
    draw(graphics.cgContext, CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func squircle(_ side: CGFloat) -> (rect: CGRect, path: CGPath) {
    let inset = side * 0.085
    let rect = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let radius = rect.width * 0.2237
    return (rect, CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
}

func plate(_ context: CGContext, _ side: CGFloat, _ top: Stop, _ bottom: Stop, gloss: CGFloat = 0.10) {
    let shape = squircle(side)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -side * 0.012), blur: side * 0.045,
                      color: NSColor.black.withAlphaComponent(0.3).cgColor)
    context.addPath(shape.path)
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape.path)
    context.clip()
    let colors = [color(top).cgColor, color(bottom).cgColor] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: shape.rect.minX, y: shape.rect.maxY),
            end: CGPoint(x: shape.rect.maxX, y: shape.rect.minY),
            options: []
        )
    }
    if gloss > 0 {
        context.setFillColor(NSColor.white.withAlphaComponent(gloss).cgColor)
        context.fill(CGRect(x: shape.rect.minX, y: shape.rect.midY,
                            width: shape.rect.width, height: shape.rect.height / 2))
    }
    context.restoreGState()
}

func symbol(_ name: String, side: CGFloat, fraction: CGFloat, weight: NSFont.Weight,
            tint: NSColor, offset: CGPoint = .zero, alpha: CGFloat = 1,
            secondary: NSColor? = nil) {
    let palette = secondary.map { [tint, $0] } ?? [tint]
    let configuration = NSImage.SymbolConfiguration(pointSize: side * fraction, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: palette))
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) else { return }
    let size = image.size
    let rect = CGRect(x: (side - size.width) / 2 + offset.x,
                      y: (side - size.height) / 2 + offset.y,
                      width: size.width, height: size.height)
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
}

func keyholePath(side: CGFloat, scale: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let centre = CGPoint(x: side / 2, y: side * 0.56)
    let radius = side * 0.13 * scale
    path.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                               width: radius * 2, height: radius * 2))
    let stemTop = centre.y - radius * 0.35
    let stemBottom = side * 0.30
    let halfTop = radius * 0.52, halfBottom = radius * 0.86
    path.move(to: CGPoint(x: centre.x - halfTop, y: stemTop))
    path.addLine(to: CGPoint(x: centre.x + halfTop, y: stemTop))
    path.addLine(to: CGPoint(x: centre.x + halfBottom, y: stemBottom))
    path.addLine(to: CGPoint(x: centre.x - halfBottom, y: stemBottom))
    path.closeSubpath()
    return path
}

func text(_ string: String, side: CGFloat, fraction: CGFloat, tint: NSColor, offsetY: CGFloat = 0) {
    let font = NSFont.systemFont(ofSize: side * fraction, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: tint]
    let measured = string.size(withAttributes: attributes)
    string.draw(at: NSPoint(x: (side - measured.width) / 2,
                            y: (side - measured.height) / 2 + offsetY),
                withAttributes: attributes)
}


func keyPath(side: CGFloat, scale: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let centre = CGPoint(x: side / 2, y: side * 0.63)
    let bow = side * 0.115 * scale
    path.addEllipse(in: CGRect(x: centre.x - bow, y: centre.y - bow, width: bow * 2, height: bow * 2))
    let hole = bow * 0.40
    path.addEllipse(in: CGRect(x: centre.x - hole, y: centre.y - hole + bow * 0.1,
                               width: hole * 2, height: hole * 2))
    let bladeWidth = bow * 0.52
    let bladeTop = centre.y - bow * 0.55
    let bladeBottom = side * 0.30
    path.addRect(CGRect(x: centre.x - bladeWidth / 2, y: bladeBottom,
                        width: bladeWidth, height: bladeTop - bladeBottom))
    for offset in [CGFloat(0.0), CGFloat(0.085)] {
        path.addRect(CGRect(x: centre.x + bladeWidth / 2,
                            y: bladeBottom + side * (0.02 + offset),
                            width: bow * 0.55, height: bow * 0.34))
    }
    return path
}

func ticks(_ context: CGContext, side: CGFloat, radius: CGFloat, count: Int,
           length: CGFloat, width: CGFloat, tint: NSColor) {
    let centre = CGPoint(x: side / 2, y: side / 2)
    context.setLineCap(.round)
    context.setStrokeColor(tint.cgColor)
    context.setLineWidth(width)
    for step in 0..<count {
        let angle = CGFloat(step) * 2 * .pi / CGFloat(count)
        context.move(to: CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius))
        context.addLine(to: CGPoint(x: centre.x + cos(angle) * (radius + length),
                                    y: centre.y + sin(angle) * (radius + length)))
    }
    context.strokePath()
}


func shieldPath(side: CGFloat, scale: CGFloat, centreY: CGFloat = 0.5) -> CGPath {
    let width = side * 0.46 * scale
    let height = side * 0.56 * scale
    let cx = side / 2
    let top = side * centreY + height / 2
    let bottom = side * centreY - height / 2
    let path = CGMutablePath()
    let radius = width * 0.16
    path.move(to: CGPoint(x: cx - width / 2, y: top - radius))
    path.addQuadCurve(to: CGPoint(x: cx - width / 2 + radius, y: top),
                      control: CGPoint(x: cx - width / 2, y: top))
    path.addLine(to: CGPoint(x: cx + width / 2 - radius, y: top))
    path.addQuadCurve(to: CGPoint(x: cx + width / 2, y: top - radius),
                      control: CGPoint(x: cx + width / 2, y: top))
    path.addCurve(to: CGPoint(x: cx, y: bottom),
                  control1: CGPoint(x: cx + width / 2, y: bottom + height * 0.44),
                  control2: CGPoint(x: cx + width * 0.34, y: bottom + height * 0.10))
    path.addCurve(to: CGPoint(x: cx - width / 2, y: top - radius),
                  control1: CGPoint(x: cx - width * 0.34, y: bottom + height * 0.10),
                  control2: CGPoint(x: cx - width / 2, y: bottom + height * 0.44))
    path.closeSubpath()
    return path
}

func meander(_ context: CGContext, rect: CGRect, unit: CGFloat, width: CGFloat, tint: NSColor) {
    context.setStrokeColor(tint.cgColor)
    context.setLineWidth(width)
    context.setLineCap(.square)
    var x = rect.minX
    while x + unit <= rect.maxX {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: rect.maxY))
        path.addLine(to: CGPoint(x: x + unit * 0.66, y: rect.maxY))
        path.addLine(to: CGPoint(x: x + unit * 0.66, y: rect.minY + rect.height * 0.34))
        path.addLine(to: CGPoint(x: x + unit * 0.33, y: rect.minY + rect.height * 0.34))
        path.addLine(to: CGPoint(x: x + unit * 0.33, y: rect.minY + rect.height * 0.68))
        context.addPath(path)
        context.strokePath()
        x += unit
    }
}







let gold = NSColor(calibratedRed: 0.96, green: 0.80, blue: 0.44, alpha: 1)
let bronze = NSColor(calibratedRed: 0.80, green: 0.58, blue: 0.29, alpha: 1)



























let designsQ: [(name: String, draw: (CGContext, CGFloat) -> Void)] = [
    ("LEDGER", { context, side in
        plate(context, side, (0.22, 0.30, 0.52), (0.08, 0.11, 0.24), gloss: 0.05)
        let book = CGRect(x: side * 0.28, y: side * 0.26, width: side * 0.44, height: side * 0.48)
        context.addPath(CGPath(roundedRect: book, cornerWidth: side * 0.04,
                               cornerHeight: side * 0.04, transform: nil))
        context.setFillColor(NSColor(calibratedWhite: 0.96, alpha: 1).cgColor)
        context.fillPath()
        context.setFillColor(NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.42, alpha: 1).cgColor)
        context.fill(CGRect(x: book.minX, y: book.minY, width: side * 0.075, height: book.height))
        context.setStrokeColor(NSColor(calibratedRed: 0.20, green: 0.28, blue: 0.50, alpha: 0.55).cgColor)
        context.setLineWidth(side * 0.014)
        for y in ([0.38, 0.46, 0.54, 0.62] as [CGFloat]) {
            context.move(to: CGPoint(x: side * 0.40, y: side * y))
            context.addLine(to: CGPoint(x: side * 0.66, y: side * y))
        }
        context.strokePath()
        context.addEllipse(in: CGRect(x: side * 0.60, y: side * 0.66, width: side * 0.085, height: side * 0.085))
        context.setFillColor(gold.cgColor)
        context.fillPath()
    }),
    ("BASALT", { context, side in
        plate(context, side, (0.26, 0.28, 0.34), (0.08, 0.09, 0.12), gloss: 0.05)
        let columns: [(CGFloat, CGFloat)] = [(0.315, 0.30), (0.435, 0.44), (0.555, 0.36)]
        for (x, height) in columns {
            let width = side * 0.11
            let base = side * 0.26
            let hex = CGMutablePath()
            hex.move(to: CGPoint(x: side * x, y: base))
            hex.addLine(to: CGPoint(x: side * x + width, y: base))
            hex.addLine(to: CGPoint(x: side * x + width, y: base + side * height))
            hex.addLine(to: CGPoint(x: side * x + width / 2, y: base + side * height + side * 0.035))
            hex.addLine(to: CGPoint(x: side * x, y: base + side * height))
            hex.closeSubpath()
            context.addPath(hex)
            context.setFillColor(NSColor(calibratedWhite: 0.95, alpha: 1).cgColor)
            context.fillPath()
        }
        context.setFillColor(gold.cgColor)
        context.fill(CGRect(x: side * 0.26, y: side * 0.225, width: side * 0.48, height: side * 0.04))
    }),
    ("ANVIL", { context, side in
        plate(context, side, (0.34, 0.36, 0.42), (0.12, 0.13, 0.17), gloss: 0.06)
        let anvil = CGMutablePath()
        anvil.move(to: CGPoint(x: side * 0.24, y: side * 0.58))
        anvil.addLine(to: CGPoint(x: side * 0.74, y: side * 0.58))
        anvil.addLine(to: CGPoint(x: side * 0.66, y: side * 0.48))
        anvil.addLine(to: CGPoint(x: side * 0.56, y: side * 0.48))
        anvil.addLine(to: CGPoint(x: side * 0.56, y: side * 0.34))
        anvil.addLine(to: CGPoint(x: side * 0.66, y: side * 0.28))
        anvil.addLine(to: CGPoint(x: side * 0.34, y: side * 0.28))
        anvil.addLine(to: CGPoint(x: side * 0.44, y: side * 0.34))
        anvil.addLine(to: CGPoint(x: side * 0.44, y: side * 0.48))
        anvil.addLine(to: CGPoint(x: side * 0.32, y: side * 0.48))
        anvil.closeSubpath()
        context.addPath(anvil)
        context.setFillColor(NSColor(calibratedWhite: 0.96, alpha: 1).cgColor)
        context.fillPath()
        context.addEllipse(in: CGRect(x: side * 0.455, y: side * 0.66, width: side * 0.09, height: side * 0.09))
        context.setFillColor(gold.cgColor)
        context.fillPath()
    }),
    ("HARBOR", { context, side in
        plate(context, side, (0.12, 0.36, 0.56), (0.04, 0.14, 0.28), gloss: 0.05)
        context.setLineCap(.round)
        for (index, radius) in ([0.30, 0.21] as [CGFloat]).enumerated() {
            context.addArc(center: CGPoint(x: side / 2, y: side * 0.34), radius: side * radius,
                           startAngle: 0.25, endAngle: .pi - 0.25, clockwise: false)
            context.setStrokeColor(NSColor.white.withAlphaComponent(index == 0 ? 0.55 : 0.85).cgColor)
            context.setLineWidth(side * 0.034)
            context.strokePath()
        }
        let tower = CGMutablePath()
        tower.move(to: CGPoint(x: side * 0.455, y: side * 0.34))
        tower.addLine(to: CGPoint(x: side * 0.545, y: side * 0.34))
        tower.addLine(to: CGPoint(x: side * 0.525, y: side * 0.66))
        tower.addLine(to: CGPoint(x: side * 0.475, y: side * 0.66))
        tower.closeSubpath()
        context.addPath(tower)
        context.setFillColor(NSColor.white.cgColor)
        context.fillPath()
        context.addEllipse(in: CGRect(x: side * 0.462, y: side * 0.665, width: side * 0.076, height: side * 0.076))
        context.setFillColor(gold.cgColor)
        context.fillPath()
    }),
    ("NUCLEUS", { context, side in
        plate(context, side, (0.16, 0.20, 0.44), (0.05, 0.07, 0.20), gloss: 0.05)
        let centre = CGPoint(x: side / 2, y: side / 2)
        for angle in ([0.0, 1.047, 2.094] as [CGFloat]) {
            context.saveGState()
            context.translateBy(x: centre.x, y: centre.y)
            context.rotate(by: angle)
            context.scaleBy(x: 1, y: 0.42)
            context.addEllipse(in: CGRect(x: -side * 0.30, y: -side * 0.30,
                                          width: side * 0.60, height: side * 0.60))
            context.restoreGState()
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.65).cgColor)
            context.setLineWidth(side * 0.016)
            context.strokePath()
        }
        context.addEllipse(in: CGRect(x: centre.x - side * 0.10, y: centre.y - side * 0.10,
                                      width: side * 0.20, height: side * 0.20))
        context.setFillColor(gold.cgColor)
        context.fillPath()
    }),
    ("WICK", { context, side in
        plate(context, side, (0.20, 0.16, 0.24), (0.07, 0.05, 0.09), gloss: 0.04)
        let flame = CGMutablePath()
        flame.move(to: CGPoint(x: side * 0.50, y: side * 0.80))
        flame.addCurve(to: CGPoint(x: side * 0.50, y: side * 0.46),
                       control1: CGPoint(x: side * 0.64, y: side * 0.68),
                       control2: CGPoint(x: side * 0.60, y: side * 0.48))
        flame.addCurve(to: CGPoint(x: side * 0.50, y: side * 0.80),
                       control1: CGPoint(x: side * 0.40, y: side * 0.48),
                       control2: CGPoint(x: side * 0.36, y: side * 0.68))
        context.addPath(flame)
        context.setFillColor(NSColor(calibratedRed: 1, green: 0.78, blue: 0.34, alpha: 1).cgColor)
        context.fillPath()
        context.setFillColor(NSColor(calibratedWhite: 0.96, alpha: 1).cgColor)
        context.fill(CGRect(x: side * 0.485, y: side * 0.34, width: side * 0.03, height: side * 0.14))
        let cup = CGRect(x: side * 0.34, y: side * 0.24, width: side * 0.32, height: side * 0.11)
        context.addPath(CGPath(roundedRect: cup, cornerWidth: side * 0.05,
                               cornerHeight: side * 0.05, transform: nil))
        context.setFillColor(NSColor(calibratedWhite: 0.96, alpha: 1).cgColor)
        context.fillPath()
    }),
    ("NIMBUS", { context, side in
        plate(context, side, (0.28, 0.34, 0.56), (0.10, 0.13, 0.28), gloss: 0.05)
        let centre = CGPoint(x: side / 2, y: side * 0.52)
        for (index, radius) in ([0.31, 0.245, 0.18] as [CGFloat]).enumerated() {
            context.addEllipse(in: CGRect(x: centre.x - side * radius, y: centre.y - side * radius,
                                          width: side * radius * 2, height: side * radius * 2))
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.30 + CGFloat(index) * 0.28).cgColor)
            context.setLineWidth(side * 0.020)
            context.strokePath()
        }
        context.addEllipse(in: CGRect(x: centre.x - side * 0.085, y: centre.y - side * 0.085,
                                      width: side * 0.17, height: side * 0.17))
        context.setFillColor(NSColor.white.cgColor)
        context.fillPath()
    }),
    ("TUNDRA", { context, side in
        plate(context, side, (0.62, 0.78, 0.86), (0.24, 0.42, 0.58), gloss: 0.07)
        let centre = CGPoint(x: side / 2, y: side / 2)
        context.setLineCap(.round)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(side * 0.030)
        for step in 0..<6 {
            let angle = CGFloat(step) * .pi / 3
            context.move(to: CGPoint(x: centre.x - cos(angle) * side * 0.26,
                                     y: centre.y - sin(angle) * side * 0.26))
            context.addLine(to: CGPoint(x: centre.x + cos(angle) * side * 0.26,
                                        y: centre.y + sin(angle) * side * 0.26))
        }
        context.strokePath()
        context.setLineWidth(side * 0.018)
        for step in 0..<6 {
            let angle = CGFloat(step) * .pi / 3
            let tip = CGPoint(x: centre.x + cos(angle) * side * 0.26,
                              y: centre.y + sin(angle) * side * 0.26)
            for delta in ([0.5, -0.5] as [CGFloat]) {
                context.move(to: tip)
                context.addLine(to: CGPoint(x: tip.x - cos(angle + delta) * side * 0.09,
                                            y: tip.y - sin(angle + delta) * side * 0.09))
            }
        }
        context.strokePath()
    }),
    ("SLATE", { context, side in
        plate(context, side, (0.34, 0.36, 0.40), (0.13, 0.14, 0.17), gloss: 0.05)
        let tablet = CGRect(x: side * 0.28, y: side * 0.26, width: side * 0.44, height: side * 0.48)
        context.addPath(CGPath(roundedRect: tablet, cornerWidth: side * 0.05,
                               cornerHeight: side * 0.05, transform: nil))
        context.setFillColor(NSColor(calibratedWhite: 0.17, alpha: 1).cgColor)
        context.fillPath()
        context.addPath(CGPath(roundedRect: tablet.insetBy(dx: side * 0.028, dy: side * 0.028),
                               cornerWidth: side * 0.035, cornerHeight: side * 0.035, transform: nil))
        context.setStrokeColor(gold.withAlphaComponent(0.85).cgColor)
        context.setLineWidth(side * 0.012)
        context.strokePath()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        context.setLineWidth(side * 0.020)
        context.setLineCap(.round)
        for (y, half) in [(0.60, 0.11), (0.52, 0.13), (0.44, 0.09)] as [(CGFloat, CGFloat)] {
            context.move(to: CGPoint(x: side * (0.50 - half), y: side * y))
            context.addLine(to: CGPoint(x: side * (0.50 + half), y: side * y))
        }
        context.strokePath()
    }),
    ("PRISM", { context, side in
        plate(context, side, (0.13, 0.13, 0.18), (0.04, 0.04, 0.07), gloss: 0.04)
        let centre = CGPoint(x: side * 0.44, y: side * 0.50)
        let triangle = CGMutablePath()
        triangle.move(to: CGPoint(x: centre.x, y: centre.y + side * 0.26))
        triangle.addLine(to: CGPoint(x: centre.x + side * 0.225, y: centre.y - side * 0.13))
        triangle.addLine(to: CGPoint(x: centre.x - side * 0.225, y: centre.y - side * 0.13))
        triangle.closeSubpath()
        context.addPath(triangle)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(side * 0.024)
        context.strokePath()
        context.setLineWidth(side * 0.020)
        context.setLineCap(.round)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.move(to: CGPoint(x: side * 0.12, y: side * 0.50))
        context.addLine(to: CGPoint(x: centre.x - side * 0.09, y: side * 0.50))
        context.strokePath()
        let colours: [NSColor] = [
            NSColor(calibratedRed: 0.98, green: 0.36, blue: 0.36, alpha: 1),
            NSColor(calibratedRed: 0.99, green: 0.76, blue: 0.30, alpha: 1),
            NSColor(calibratedRed: 0.40, green: 0.86, blue: 0.56, alpha: 1),
            NSColor(calibratedRed: 0.36, green: 0.64, blue: 1.00, alpha: 1),
        ]
        for (index, colour) in colours.enumerated() {
            context.setStrokeColor(colour.cgColor)
            context.move(to: CGPoint(x: centre.x + side * 0.10, y: side * 0.50))
            context.addLine(to: CGPoint(x: side * 0.86, y: side * (0.62 - CGFloat(index) * 0.075)))
            context.strokePath()
        }
    }),
]

let designs = designsQ
let labelOffset = 0

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icons")
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

var previews: [NSImage] = []
for design in designs {
    guard let rep = canvas(1024, design.draw),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: output.appendingPathComponent("\(design.name).png"))
    let image = NSImage(size: NSSize(width: 1024, height: 1024))
    image.addRepresentation(rep)
    previews.append(image)
}

// Contact sheet: five per row, each shown large plus at menu-bar size.
let cell: CGFloat = 200, gap: CGFloat = 34, margin: CGFloat = 40, labelSpace: CGFloat = 56
let columns = 5
let rows = (previews.count + columns - 1) / columns
let sheetWidth = margin * 2 + CGFloat(columns) * cell + CGFloat(columns - 1) * gap
let sheetHeight = margin * 2 + CGFloat(rows) * (cell + labelSpace) + CGFloat(rows - 1) * gap

guard let sheet = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(sheetWidth * 2), pixelsHigh: Int(sheetHeight * 2),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
sheet.size = NSSize(width: sheetWidth, height: sheetHeight)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
NSColor(calibratedWhite: 0.14, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight).fill()

for (index, image) in previews.enumerated() {
    let column = index % columns, row = index / columns
    let x = margin + CGFloat(column) * (cell + gap)
    let y = sheetHeight - margin - CGFloat(row + 1) * cell - CGFloat(row) * (gap + labelSpace)
    image.draw(in: NSRect(x: x, y: y, width: cell, height: cell))
    image.draw(in: NSRect(x: x, y: y - 44, width: 34, height: 34))
    let raw = designs[index].name
    let label = raw.first?.isNumber == false ? raw : "\(index + 1 + labelOffset)"
    label.draw(at: NSPoint(x: x + 44, y: y - 40), withAttributes: [
        .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
        .foregroundColor: NSColor.white,
    ])
}
NSGraphicsContext.restoreGraphicsState()
try sheet.representation(using: .png, properties: [:])!
    .write(to: output.appendingPathComponent("contact-sheet.png"))
print("wrote \(previews.count) icons to \(output.path)")
