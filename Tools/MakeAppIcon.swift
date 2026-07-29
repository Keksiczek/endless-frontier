import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// The app icon, drawn in the game's own direction: a "frontier ledger" —
// deep slate night, bone hairlines, one amber lantern. A settlement seen from
// the dark, which is what the whole game looks like.

let side = 1024
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                          bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}
let S = CGFloat(side)

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)])!
}

let ink       = rgb(0.045, 0.050, 0.068)
let inkUp     = rgb(0.105, 0.115, 0.150)
let bone      = rgb(0.91, 0.90, 0.86)
let boneDim   = rgb(0.62, 0.63, 0.66)
let amber     = rgb(0.95, 0.66, 0.27)
let ground    = rgb(0.085, 0.105, 0.095)

// MARK: - Night sky

if let sky = CGGradient(colorsSpace: space, colors: [inkUp, ink] as CFArray,
                        locations: [0, 1]) {
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0),
                           options: [])
}

// Stars: a scatter, deterministic, thinning toward the horizon.
var seed: UInt64 = 0x5EED_1CE
func roll() -> Double {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Double((seed >> 33) & 0xFFFF) / 65535
}
for _ in 0..<70 {
    let x = roll() * Double(side)
    let y = 0.42 + roll() * 0.55        // upper half only
    let r = (0.6 + roll() * 2.0) * Double(side) / 1024 * 2
    let bright = 0.25 + roll() * 0.55
    ctx.setFillColor(rgb(0.92, 0.93, 0.96, bright * (y - 0.35)))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y * Double(side) - r, width: r * 2, height: r * 2))
}

// MARK: - The lantern's glow

let glowCentre = CGPoint(x: S * 0.5, y: S * 0.40)
if let glow = CGGradient(colorsSpace: space,
                         colors: [rgb(0.95, 0.66, 0.27, 0.32),
                                  rgb(0.95, 0.66, 0.27, 0.10),
                                  rgb(0.95, 0.66, 0.27, 0.0)] as CFArray,
                         locations: [0, 0.45, 1]) {
    ctx.drawRadialGradient(glow, startCenter: glowCentre, startRadius: 0,
                           endCenter: glowCentre, endRadius: S * 0.42, options: [])
}

// MARK: - The land

ctx.setFillColor(ground)
let hill = CGMutablePath()
hill.move(to: CGPoint(x: 0, y: 0))
hill.addLine(to: CGPoint(x: 0, y: S * 0.30))
hill.addCurve(to: CGPoint(x: S, y: S * 0.28),
              control1: CGPoint(x: S * 0.35, y: S * 0.36),
              control2: CGPoint(x: S * 0.68, y: S * 0.24))
hill.addLine(to: CGPoint(x: S, y: 0))
hill.closeSubpath()
ctx.addPath(hill)
ctx.fillPath()

// A hairline along the ridge, the way the canvas draws its ground.
ctx.setStrokeColor(rgb(0.30, 0.34, 0.32, 0.9))
ctx.setLineWidth(S * 0.004)
ctx.move(to: CGPoint(x: 0, y: S * 0.30))
ctx.addCurve(to: CGPoint(x: S, y: S * 0.28),
             control1: CGPoint(x: S * 0.35, y: S * 0.36),
             control2: CGPoint(x: S * 0.68, y: S * 0.24))
ctx.strokePath()

// MARK: - The settlement

/// One gabled house: a filled body, a filled roof, bone outlines, a lit window.
/// The same silhouette `SettlementStructures` draws, so the icon is the game.
func house(x: CGFloat, y: CGFloat, w: CGFloat, lit: Bool, dim: Bool) {
    let h = w * 0.72
    let body = CGRect(x: x - w / 2, y: y, width: w, height: h)
    let wall = dim ? rgb(0.13, 0.14, 0.17) : rgb(0.17, 0.18, 0.21)
    let roofFill = dim ? rgb(0.09, 0.10, 0.12) : rgb(0.12, 0.13, 0.15)

    ctx.setFillColor(wall)
    ctx.fill(body)

    let roof = CGMutablePath()
    roof.move(to: CGPoint(x: body.minX - w * 0.12, y: body.maxY))
    roof.addLine(to: CGPoint(x: x, y: body.maxY + h * 0.66))
    roof.addLine(to: CGPoint(x: body.maxX + w * 0.12, y: body.maxY))
    roof.closeSubpath()
    ctx.setFillColor(roofFill)
    ctx.addPath(roof)
    ctx.fillPath()

    let stroke = dim ? boneDim : bone
    ctx.setStrokeColor(stroke.copy(alpha: dim ? 0.55 : 0.95)!)
    ctx.setLineWidth(S * (dim ? 0.0045 : 0.0075))
    ctx.stroke(body)
    ctx.addPath(roof)
    ctx.strokePath()

    guard lit else { return }
    let win = CGRect(x: x - w * 0.19, y: y + h * 0.26, width: w * 0.38, height: h * 0.36)
    ctx.setFillColor(amber)
    ctx.fill(win)
    ctx.setStrokeColor(rgb(0.05, 0.05, 0.06, 0.85))
    ctx.setLineWidth(S * 0.004)
    ctx.stroke(win)
}

// Two behind, smaller and dimmer — a settlement rather than a house.
house(x: S * 0.275, y: S * 0.285, w: S * 0.160, lit: false, dim: true)
house(x: S * 0.725, y: S * 0.285, w: S * 0.160, lit: true, dim: true)
// And the one you are looking at.
house(x: S * 0.50, y: S * 0.205, w: S * 0.275, lit: true, dim: false)

// A thread of smoke from its roof, the way the canvas draws a lived-in house.
ctx.setStrokeColor(rgb(0.70, 0.72, 0.75, 0.35))
ctx.setLineWidth(S * 0.007)
ctx.move(to: CGPoint(x: S * 0.575, y: S * 0.435))
ctx.addCurve(to: CGPoint(x: S * 0.585, y: S * 0.575),
             control1: CGPoint(x: S * 0.545, y: S * 0.490),
             control2: CGPoint(x: S * 0.615, y: S * 0.515))
ctx.strokePath()

// MARK: - Two pines, because the valley is a valley

func pine(x: CGFloat, y: CGFloat, h: CGFloat) {
    ctx.setStrokeColor(rgb(0.28, 0.38, 0.31, 0.85))
    ctx.setLineWidth(S * 0.005)
    ctx.setFillColor(rgb(0.10, 0.16, 0.13, 0.95))
    for tier in 0..<3 {
        let t = CGFloat(tier)
        let ty = y + t * h * 0.20
        let half = h * (0.27 - t * 0.062)
        let skirt = CGMutablePath()
        skirt.move(to: CGPoint(x: x - half, y: ty))
        skirt.addLine(to: CGPoint(x: x, y: ty + h * 0.34))
        skirt.addLine(to: CGPoint(x: x + half, y: ty))
        skirt.closeSubpath()
        ctx.addPath(skirt)
        ctx.fillPath()
        ctx.addPath(skirt)
        ctx.strokePath()
    }
}
pine(x: S * 0.115, y: S * 0.250, h: S * 0.185)
pine(x: S * 0.895, y: S * 0.240, h: S * 0.160)

// MARK: - Write it

guard let image = ctx.makeImage() else { fatalError("no image") }
let out = URL(fileURLWithPath: CommandLine.arguments[1])
guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("no destination")
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")
