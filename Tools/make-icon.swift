// Draws the MacBee app icon (1024 x 1024 PNG): "Vinyl Bee", a black record with a bee on its amber label, on honey yellow.
// Usage: swift Tools/make-icon.swift <output.png>
import AppKit
import CoreGraphics

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let size: CGFloat = 1024
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
let amber = gradient([color(0xFFDA5C), color(0xFFA51F), color(0xF2851A)], [0, 0.6, 1])

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x000000, 0.45))
ctx.addPath(bodyPath); ctx.setFillColor(color(0x0B0D10)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()

func glassWing(_ c: CGPoint, _ angle: CGFloat, _ w: CGFloat, _ h: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y); ctx.rotate(by: angle)
    let r = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
    ctx.saveGState(); ctx.addEllipse(in: r); ctx.clip()
    ctx.drawLinearGradient(gradient([color(0xFFFFFF, 0.85), color(0xBFEFF5, 0.30)], [0, 1]),
                           start: CGPoint(x: w / 2, y: 0), end: CGPoint(x: -w / 2, y: 0), options: [])
    ctx.restoreGState()
    ctx.addEllipse(in: r); ctx.setStrokeColor(color(0xFFFFFF, 0.9)); ctx.setLineWidth(w * 0.03); ctx.strokePath()
    ctx.restoreGState()
}

// Vinyl record with an amber label and a small bee in the middle.
ctx.drawLinearGradient(gradient([color(0xFFD84A), color(0xF5A623)], [0, 1]), // honey yellow
                       start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
let c = CGPoint(x: 512, y: 512)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: color(0x000000, 0.7))
ctx.addEllipse(in: CGRect(x: c.x - 345, y: c.y - 345, width: 690, height: 690))
ctx.setFillColor(color(0x0C0D0F)); ctx.fillPath()
ctx.restoreGState()
for r in stride(from: CGFloat(160), through: 335, by: 9) {
    ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    ctx.setStrokeColor(color(0xFFFFFF, 0.055)); ctx.setLineWidth(2); ctx.strokePath()
}
// Light reflections on the record.
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: c.x - 345, y: c.y - 345, width: 690, height: 690)); ctx.clip()
for base in [CGFloat.pi * 0.25, CGFloat.pi * 1.25] {
    let p = CGMutablePath(); p.move(to: c)
    p.addArc(center: c, radius: 400, startAngle: base - 0.22, endAngle: base + 0.22, clockwise: false)
    p.closeSubpath()
    ctx.addPath(p); ctx.setFillColor(color(0xFFFFFF, 0.07)); ctx.fillPath()
}
ctx.restoreGState()
// Label.
let lr: CGFloat = 150
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: c.x - lr, y: c.y - lr, width: 2 * lr, height: 2 * lr)); ctx.clip()
ctx.drawLinearGradient(amber, start: CGPoint(x: 512, y: c.y + lr), end: CGPoint(x: 512, y: c.y - lr), options: [])
ctx.restoreGState()
// Bee: wings, then striped body.
glassWing(CGPoint(x: 478, y: 560), 2.2, 100, 52)
glassWing(CGPoint(x: 546, y: 560), 0.94, 100, 52)
let bee = CGRect(x: 512 - 82, y: 488 - 50, width: 164, height: 100)
ctx.saveGState()
ctx.addEllipse(in: bee); ctx.clip()
ctx.setFillColor(color(0x15110C)); ctx.fill(bee)
ctx.setFillColor(color(0xFFC23A))
for x in [CGFloat(452), 500, 548] { ctx.fill(CGRect(x: x, y: 400, width: 24, height: 200)) }
ctx.restoreGState()


ctx.drawLinearGradient(gradient([color(0xFFFFFF, 0.08), color(0xFFFFFF, 0)], [0, 1]),
                       start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 640), options: [])
ctx.restoreGState()
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
