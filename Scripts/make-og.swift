// Renders server/public/og.png (then: sips -s format jpeg -s formatOptions 82 og.png --out og.jpg) — the 1200×630 link-preview image (WhatsApp, X, iMessage…).
// Usage: swift Scripts/make-og.swift   (from the project root)
import AppKit

let W: CGFloat = 1200, H: CGFloat = 630
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let rgb = { (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) in NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a) }

// Background
NSGradient(colors: [rgb(24, 28, 38, 1), rgb(11, 13, 18, 1)])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -60)
rgb(168, 85, 247, 0.22).setFill(); NSBezierPath(ovalIn: NSRect(x: 820, y: 330, width: 520, height: 420)).fill()
rgb(31, 124, 255, 0.18).setFill(); NSBezierPath(ovalIn: NSRect(x: -160, y: -200, width: 560, height: 460)).fill()

func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor, mono: Bool = false) {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color, .kern: mono ? 0 : -0.5])
}

// Brand
rgb(255, 69, 58, 1).setFill(); NSBezierPath(ovalIn: NSRect(x: 80, y: 500, width: 54, height: 54)).fill()
text("Cricket Live", 152, 500, size: 46, weight: .heavy, color: .white)
text("Live cricket, ball by ball.", 80, 380, size: 64, weight: .heavy, color: .white)
text("Without the clutter.", 80, 305, size: 64, weight: .heavy, color: rgb(164, 171, 184, 1))

// Mock widget pill
let pill = NSRect(x: 80, y: 170, width: 700, height: 84)
rgb(0, 0, 0, 1).setFill(); NSBezierPath(roundedRect: pill, xRadius: 42, yRadius: 42).fill()
rgb(255, 69, 58, 1).setFill(); NSBezierPath(ovalIn: NSRect(x: 118, y: 202, width: 20, height: 20)).fill()
text("LIVE", 152, 192, size: 26, weight: .heavy, color: rgb(255, 69, 58, 1))
text("IND", 250, 189, size: 32, weight: .bold, color: .white)
text("188/4", 322, 186, size: 36, weight: .bold, color: .white, mono: true)
text("32.3", 462, 191, size: 26, weight: .medium, color: rgb(164, 171, 184, 1), mono: true)
text("· AUS 241/8", 560, 191, size: 26, weight: .medium, color: rgb(164, 171, 184, 1))
// "4" ball
rgb(31, 124, 255, 1).setFill(); NSBezierPath(ovalIn: NSRect(x: 812, y: 176, width: 72, height: 72)).fill()
text("4", 834, 186, size: 44, weight: .heavy, color: .white)

// Feature line
text("Follow your team  ·  Pop-out scoreboard  ·  Free, no ads, no account", 80, 80, size: 28, weight: .semibold, color: rgb(214, 219, 228, 1))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "server/public/og.png (then: sips -s format jpeg -s formatOptions 82 og.png --out og.jpg)"))
print("Wrote server/public/og.png (then: sips -s format jpeg -s formatOptions 82 og.png --out og.jpg)")
