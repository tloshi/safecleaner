import AppKit

// Repo-native icon drawing; no remote assets or image-generation dependency.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = CGFloat(size)
    let rect = NSRect(x: s * 0.07, y: s * 0.07, width: s * 0.86, height: s * 0.86)
    let background = NSBezierPath(roundedRect: rect, xRadius: s * 0.19, yRadius: s * 0.19)
    NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.20, blue: 0.22, alpha: 1),
               ending: NSColor(calibratedRed: 0.04, green: 0.07, blue: 0.09, alpha: 1))!
        .draw(in: background, angle: -55)
    let mint = NSColor(calibratedRed: 0.56, green: 0.91, blue: 0.74, alpha: 1)
    let check = NSBezierPath()
    check.move(to: NSPoint(x: s * 0.27, y: s * 0.53))
    check.line(to: NSPoint(x: s * 0.44, y: s * 0.34))
    check.line(to: NSPoint(x: s * 0.72, y: s * 0.67))
    check.lineWidth = s * 0.075; check.lineCapStyle = .round; check.lineJoinStyle = .round
    mint.setStroke(); check.stroke()
    let sparkle = NSBezierPath()
    sparkle.move(to: NSPoint(x: s * 0.72, y: s * 0.85))
    sparkle.curve(to: NSPoint(x: s * 0.81, y: s * 0.76), controlPoint1: NSPoint(x: s * 0.73, y: s * 0.78), controlPoint2: NSPoint(x: s * 0.75, y: s * 0.77))
    sparkle.curve(to: NSPoint(x: s * 0.72, y: s * 0.67), controlPoint1: NSPoint(x: s * 0.75, y: s * 0.75), controlPoint2: NSPoint(x: s * 0.73, y: s * 0.74))
    sparkle.curve(to: NSPoint(x: s * 0.63, y: s * 0.76), controlPoint1: NSPoint(x: s * 0.71, y: s * 0.74), controlPoint2: NSPoint(x: s * 0.69, y: s * 0.75))
    sparkle.curve(to: NSPoint(x: s * 0.72, y: s * 0.85), controlPoint1: NSPoint(x: s * 0.69, y: s * 0.77), controlPoint2: NSPoint(x: s * 0.71, y: s * 0.78))
    sparkle.close(); mint.setFill(); sparkle.fill()
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    // Explicit pixels prevent Retina display scaling from changing icon dimensions.
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSImage(cgImage: rep.cgImage!, size: NSSize(width: size, height: size)).draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon-\(size).png"))
}
