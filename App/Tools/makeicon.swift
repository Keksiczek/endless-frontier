import AppKit
import CoreGraphics

// Renders the Endless Frontier app icon: a home under a rocket's rising arc.
// House + terracotta roof + lit window (the colony), an amber arc a rocket
// flies over it (progress / the frontier), a small colonist, a dusk sky.

let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                    bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let S = CGFloat(size)
func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: CGFloat(x) * S, y: CGFloat(y) * S) }
// y is measured from the bottom (CoreGraphics origin).

// ---- Sky: a dusk gradient ----
let sky = CGGradient(colorsSpace: cs,
    colors: [c(0.11, 0.14, 0.22), c(0.16, 0.14, 0.20), c(0.06, 0.07, 0.10)] as CFArray,
    locations: [0, 0.5, 1])!
ctx.drawLinearGradient(sky, start: P(0, 1), end: P(0, 0), options: [])

// ---- Stars ----
let stars: [(Double, Double, Double)] = [
    (0.14, 0.86, 4), (0.22, 0.74, 3), (0.30, 0.90, 2.5), (0.68, 0.90, 3),
    (0.80, 0.80, 4), (0.88, 0.70, 2.5), (0.58, 0.82, 2), (0.10, 0.66, 2.5),
    (0.92, 0.86, 3), (0.40, 0.94, 2)]
for (x, y, r) in stars {
    ctx.setFillColor(c(0.95, 0.95, 0.98, 0.85))
    let rr = CGFloat(r) * S / 512
    ctx.fillEllipse(in: CGRect(x: P(x, y).x - rr, y: P(x, y).y - rr, width: rr * 2, height: rr * 2))
}

// ---- Ground: a low hill ----
ctx.beginPath()
ctx.move(to: P(0, 0))
ctx.addLine(to: P(0, 0.24))
ctx.addCurve(to: P(1, 0.22), control1: P(0.35, 0.30), control2: P(0.7, 0.17))
ctx.addLine(to: P(1, 0))
ctx.closePath()
ctx.setFillColor(c(0.13, 0.17, 0.14))
ctx.fillPath()
// A warmer rim where the ground meets the sky.
ctx.beginPath()
ctx.move(to: P(0, 0.24))
ctx.addCurve(to: P(1, 0.22), control1: P(0.35, 0.30), control2: P(0.7, 0.17))
ctx.setStrokeColor(c(0.30, 0.28, 0.20, 0.5))
ctx.setLineWidth(S * 0.006)
ctx.strokePath()

// ---- The rocket's arc (drawn behind the house top, over the sky) ----
// A parabola from lower-left, up over the house, to the upper-right.
func arcPoint(_ t: Double) -> CGPoint {
    // Quadratic bezier: start -> control (high) -> end.
    let p0 = P(0.10, 0.30), p1 = P(0.50, 1.02), p2 = P(0.90, 0.66)
    let u = 1 - t
    let x = u*u*Double(p0.x) + 2*u*t*Double(p1.x) + t*t*Double(p2.x)
    let y = u*u*Double(p0.y) + 2*u*t*Double(p1.y) + t*t*Double(p2.y)
    return CGPoint(x: x, y: y)
}
// Dotted trail (the progress travelled).
ctx.setFillColor(c(0.98, 0.70, 0.28, 0.9))
var t = 0.0
while t < 0.82 {
    let p = arcPoint(t)
    let r = CGFloat(0.006 + t * 0.006) * S
    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    t += 0.055
}

// ---- The rocket at the head of the arc ----
let head = arcPoint(0.86)
let ahead = arcPoint(0.92)
let dx = Double(ahead.x - head.x), dy = Double(ahead.y - head.y)
let ang = atan2(dy, dx)
ctx.saveGState()
ctx.translateBy(x: head.x, y: head.y)
ctx.rotate(by: CGFloat(ang))
let L = S * 0.16   // rocket length
let W = S * 0.055  // rocket width
// Flame.
ctx.beginPath()
ctx.move(to: CGPoint(x: -L * 0.55, y: 0))
ctx.addLine(to: CGPoint(x: -L * 0.95, y: W * 0.42))
ctx.addLine(to: CGPoint(x: -L * 1.25, y: 0))
ctx.addLine(to: CGPoint(x: -L * 0.95, y: -W * 0.42))
ctx.closePath()
ctx.setFillColor(c(0.99, 0.85, 0.45, 0.95))
ctx.fillPath()
// Body (capsule-ish).
ctx.beginPath()
ctx.move(to: CGPoint(x: L * 0.55, y: 0))                    // nose tip
ctx.addQuadCurve(to: CGPoint(x: L * 0.05, y: W * 0.5), control: CGPoint(x: L * 0.5, y: W * 0.5))
ctx.addLine(to: CGPoint(x: -L * 0.5, y: W * 0.5))
ctx.addLine(to: CGPoint(x: -L * 0.5, y: -W * 0.5))
ctx.addLine(to: CGPoint(x: L * 0.05, y: -W * 0.5))
ctx.addQuadCurve(to: CGPoint(x: L * 0.55, y: 0), control: CGPoint(x: L * 0.5, y: -W * 0.5))
ctx.closePath()
ctx.setFillColor(c(0.94, 0.92, 0.86))
ctx.fillPath()
// Fins.
ctx.setFillColor(c(0.98, 0.66, 0.27))
ctx.beginPath()
ctx.move(to: CGPoint(x: -L * 0.5, y: W * 0.5))
ctx.addLine(to: CGPoint(x: -L * 0.75, y: W * 0.95))
ctx.addLine(to: CGPoint(x: -L * 0.4, y: W * 0.5))
ctx.closePath(); ctx.fillPath()
ctx.beginPath()
ctx.move(to: CGPoint(x: -L * 0.5, y: -W * 0.5))
ctx.addLine(to: CGPoint(x: -L * 0.75, y: -W * 0.95))
ctx.addLine(to: CGPoint(x: -L * 0.4, y: -W * 0.5))
ctx.closePath(); ctx.fillPath()
// Porthole.
ctx.setFillColor(c(0.30, 0.55, 0.72))
ctx.fillEllipse(in: CGRect(x: L * 0.02, y: -W * 0.22, width: W * 0.44, height: W * 0.44))
ctx.restoreGState()

// ---- The house ----
let hx = 0.30, hw = 0.28          // left edge, width
let hy = 0.235, hh = 0.20         // base, height (walls)
// Ground shadow.
ctx.setFillColor(c(0, 0, 0, 0.28))
ctx.fillEllipse(in: CGRect(x: P(hx - 0.03, hy - 0.02).x, y: P(0, hy - 0.03).y,
                           width: (hw + 0.06) * S, height: 0.05 * S))
// Walls.
ctx.setFillColor(c(0.92, 0.89, 0.82))
ctx.fill(CGRect(x: P(hx, hy).x, y: P(0, hy).y, width: hw * S, height: hh * S))
// Roof (gabled, terracotta), overhanging.
ctx.beginPath()
ctx.move(to: P(hx - 0.035, hy + hh))
ctx.addLine(to: P(hx + hw / 2, hy + hh + 0.11))
ctx.addLine(to: P(hx + hw + 0.035, hy + hh))
ctx.closePath()
ctx.setFillColor(c(0.80, 0.45, 0.32))
ctx.fillPath()
// Roof shading line.
ctx.beginPath()
ctx.move(to: P(hx + 0.02, hy + hh + 0.028))
ctx.addLine(to: P(hx + hw - 0.02, hy + hh + 0.028))
ctx.setStrokeColor(c(0.62, 0.34, 0.24, 0.7)); ctx.setLineWidth(S * 0.006); ctx.strokePath()
// Lit window.
ctx.setFillColor(c(0.99, 0.74, 0.32))
ctx.fill(CGRect(x: P(hx + 0.045, hy + 0.10).x, y: P(0, hy + 0.10).y, width: 0.075 * S, height: 0.075 * S))
ctx.setStrokeColor(c(0.30, 0.24, 0.18)); ctx.setLineWidth(S * 0.006)
ctx.stroke(CGRect(x: P(hx + 0.045, hy + 0.10).x, y: P(0, hy + 0.10).y, width: 0.075 * S, height: 0.075 * S))
// Door.
ctx.setFillColor(c(0.26, 0.19, 0.15))
ctx.fill(CGRect(x: P(hx + 0.165, hy).x, y: P(0, hy).y, width: 0.06 * S, height: 0.115 * S))

// ---- A small colonist by the house ----
let cxp = 0.635, cyp = hy   // feet on the ground line
ctx.setFillColor(c(0.90, 0.88, 0.82))
// head
let hr = 0.022 * S
ctx.fillEllipse(in: CGRect(x: P(cxp, cyp + 0.085).x - hr, y: P(0, cyp + 0.085).y - hr, width: hr * 2, height: hr * 2))
// body + legs
ctx.setStrokeColor(c(0.90, 0.88, 0.82)); ctx.setLineCap(.round); ctx.setLineWidth(S * 0.014)
ctx.beginPath()
ctx.move(to: P(cxp, cyp + 0.075)); ctx.addLine(to: P(cxp, cyp + 0.03))
ctx.move(to: P(cxp - 0.016, cyp)); ctx.addLine(to: P(cxp, cyp + 0.03)); ctx.addLine(to: P(cxp + 0.016, cyp))
ctx.strokePath()

// ---- Export ----
let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
let png = rep.representation(using: .png, properties: [:])!
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/icon.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
