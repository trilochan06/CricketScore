// Renders CricketScore/Resources/AppIcon.icns.
// Usage: swift Scripts/make-icon.swift   (run from the project root)
import AppKit

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let body = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSColor.black.setFill()
    body.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGradient(colors: [NSColor(red: 0.13, green: 0.14, blue: 0.17, alpha: 1),
                        NSColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1)])!.draw(in: body, angle: -90)

    // Pill "widget" motif.
    let pill = NSRect(x: rect.minX + rect.width * 0.14, y: rect.midY - rect.height * 0.3,
                      width: rect.width * 0.72, height: rect.height * 0.16)
    NSColor.white.withAlphaComponent(0.1).setFill()
    NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
    let dot = pill.height * 0.36
    NSColor(red: 1, green: 0.27, blue: 0.23, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: pill.minX + pill.height * 0.4, y: pill.midY - dot / 2, width: dot, height: dot)).fill()
    NSColor.white.withAlphaComponent(0.55).setFill()
    let bar = NSRect(x: pill.minX + pill.height * 1.05, y: pill.midY - pill.height * 0.09,
                     width: pill.width * 0.55, height: pill.height * 0.18)
    NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()

    // Ball.
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.36, weight: .medium)
        .applying(.init(paletteColors: [NSColor(red: 1, green: 0.33, blue: 0.27, alpha: 1)]))
    if let ball = NSImage(systemSymbolName: "cricket.ball.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let size = ball.size
        ball.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2 + rect.height * 0.1,
                             width: size.width, height: size.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, px) in sizes {
    try! render(px).write(to: iconset.appendingPathComponent("\(name).png"))
}
let out = "CricketScore/Resources/AppIcon.icns"
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote \(out)" : "iconutil failed")
