// Draws the MacBee app icon (1024 x 1024 PNG).
// Usage: swift Tools/make-icon.swift <output.png>
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

// macOS icon body: 824 pt rounded square centered, with a soft drop shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x000000, 0.45))
ctx.addPath(bodyPath); ctx.setFillColor(color(0x0B0D10)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
// Dark background, a little lighter at the top.
ctx.drawLinearGradient(gradient([color(0x1E252C), color(0x07090B)], [0, 1]),
                       start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
// Cyan glow behind the hexagon (the app's accent color).
ctx.drawRadialGradient(gradient([color(0x33D6E0, 0.42), color(0x33D6E0, 0)], [0, 1]),
                       startCenter: CGPoint(x: 512, y: 470), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 470), endRadius: 420, options: [])

// Wings: two glassy ellipses behind the top of the hexagon.
func wing(center: CGPoint, angle: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle)
    let rect = CGRect(x: -160, y: -70, width: 320, height: 140)
    ctx.addEllipse(in: rect); ctx.clip()
    ctx.drawLinearGradient(gradient([color(0xFFFFFF, 0.80), color(0x9FEFF5, 0.30)], [0, 1]),
                           start: CGPoint(x: 160, y: 0), end: CGPoint(x: -160, y: 0), options: [])
    ctx.restoreGState()
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle)
    ctx.addEllipse(in: CGRect(x: -160, y: -70, width: 320, height: 140))
    ctx.setStrokeColor(color(0xFFFFFF, 0.85)); ctx.setLineWidth(5); ctx.strokePath()
    ctx.restoreGState()
}
// Each wing leans outward from the top of the hexagon (angle measured from the wing's long axis).
wing(center: CGPoint(x: 380, y: 745), angle: -2.45)
wing(center: CGPoint(x: 644, y: 745), angle: -0.69)

// Honeycomb hexagon (flat top) in amber, with a soft shadow.
let center = CGPoint(x: 512, y: 455)
let radius: CGFloat = 255
let hex = CGMutablePath()
for i in 0..<6 {
    let a = CGFloat(i) * .pi / 3
    let p = CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
    i == 0 ? hex.move(to: p) : hex.addLine(to: p)
}
hex.closeSubpath()
let rounded = hex.copy(strokingWithWidth: 40, lineCap: .round, lineJoin: .round, miterLimit: 10)
let hexShape = hex.union(rounded)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: color(0x000000, 0.5))
ctx.addPath(hexShape); ctx.setFillColor(color(0xFFB627)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(hexShape); ctx.clip()
ctx.drawLinearGradient(gradient([color(0xFFDA5C), color(0xFFA51F), color(0xF2851A)], [0, 0.6, 1]),
                       start: CGPoint(x: 512, y: center.y + radius), end: CGPoint(x: 512, y: center.y - radius), options: [])
ctx.restoreGState()

// Equalizer bars: the bee's stripes, and the "music" in MacBee.
let heights: [CGFloat] = [150, 270, 340, 240, 130]
let barWidth: CGFloat = 50, gap: CGFloat = 28
let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
for (i, h) in heights.enumerated() {
    let x = center.x - total / 2 + CGFloat(i) * (barWidth + gap)
    let bar = CGPath(roundedRect: CGRect(x: x, y: center.y - h / 2, width: barWidth, height: h),
                     cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
    ctx.addPath(bar); ctx.setFillColor(color(0x15110C)); ctx.fillPath()
}

// Light sheen across the top of the icon.
ctx.drawLinearGradient(gradient([color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)], [0, 1]),
                       start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 640), options: [])
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
