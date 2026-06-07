import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Render the app icon: a real globe (orthographic projection of the actual continents
// from countries.json) with gradient sphere shading and a soft highlight. Swift port of
// make_icon.py, using only CoreGraphics (radial gradients instead of image blur).

let size = 1024
let cx = 512.0, cy = 512.0
let radius = 410.0
let lat0 = 20.0, lon0 = 10.0

func projectDir() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
}

struct GeoCountry: Decodable { let geometry: [[[[Double]]]] }

func project(lat: Double, lon: Double) -> (x: Double, y: Double, visible: Bool) {
    let la = lat * .pi / 180, lo = lon * .pi / 180
    let la0 = lat0 * .pi / 180, lo0 = lon0 * .pi / 180
    let cosc = sin(la0) * sin(la) + cos(la0) * cos(la) * cos(lo - lo0)
    let x = cos(la) * sin(lo - lo0)
    let y = cos(la0) * sin(la) - sin(la0) * cos(la) * cos(lo - lo0)
    return (cx + x * radius, cy - y * radius, cosc >= 0)
}

func visibleRuns(_ ring: [[Double]]) -> [[CGPoint]] {
    var runs: [[CGPoint]] = [], current: [CGPoint] = []
    for pt in ring where pt.count == 2 {
        let p = project(lat: pt[1], lon: pt[0])
        if p.visible {
            current.append(CGPoint(x: p.x, y: p.y))
        } else if !current.isEmpty {
            runs.append(current); current = []
        }
    }
    if !current.isEmpty { runs.append(current) }
    return runs
}

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Could not create bitmap context")
}
ctx.translateBy(x: 0, y: CGFloat(size))   // flip to a top-left origin like the projection math
ctx.scaleBy(x: 1, y: -1)
ctx.interpolationQuality = .high
ctx.setShouldAntialias(true)

func radial(_ colors: [CGColor], _ locations: [CGFloat],
            from c0: CGPoint, r0: Double, to c1: CGPoint, r1: Double,
            options: CGGradientDrawingOptions = []) {
    guard let g = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locations) else { return }
    ctx.drawRadialGradient(g, startCenter: c0, startRadius: r0, endCenter: c1, endRadius: r1, options: options)
}

let center = CGPoint(x: cx, y: cy)

// Background: vertical gradient.
if let bg = CGGradient(colorsSpace: cs, colors: [rgb(0.11, 0.14, 0.29), rgb(0.05, 0.06, 0.14)] as CFArray,
                       locations: [0, 1]) {
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(size)), options: [])
}

// Atmosphere glow behind the globe.
radial([rgb(0.35, 0.59, 0.90, 0.55), rgb(0.35, 0.59, 0.90, 0)], [0, 1],
       from: center, r0: radius * 0.96, to: center, r1: radius * 1.20,
       options: [.drawsBeforeStartLocation])

// Globe disk: clip to the circle for everything that follows.
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
ctx.clip()

ctx.setFillColor(rgb(0.16, 0.38, 0.61))         // ocean
ctx.fill(CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))

// Land.
let dataURL = projectDir().appendingPathComponent("Globle/Resources/countries.json")
let countries = try JSONDecoder().decode([GeoCountry].self, from: Data(contentsOf: dataURL))
ctx.setFillColor(rgb(0.41, 0.68, 0.37))
for country in countries {
    for polygon in country.geometry {
        for ring in polygon {
            for run in visibleRuns(ring) where run.count >= 3 {
                ctx.beginPath()
                ctx.addLines(between: run)
                ctx.closePath()
                ctx.fillPath()
            }
        }
    }
}

// Limb darkening: clear at the center fading to dark at the edge.
radial([rgb(0, 0, 0, 0), rgb(0, 0, 0, 0.55)], [0.55, 1],
       from: center, r0: 0, to: center, r1: radius)

// Specular highlight, upper-left.
let hl = CGPoint(x: cx - radius * 0.36, y: cy + radius * 0.40)
radial([rgb(1, 1, 1, 0.40), rgb(1, 1, 1, 0)], [0, 1],
       from: hl, r0: 0, to: hl, r1: radius * 0.75)

ctx.restoreGState()

// Write PNG.
guard let image = ctx.makeImage() else { fatalError("Could not render image") }
let outURL = projectDir().appendingPathComponent("Globle/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Could not create PNG destination")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("Could not write PNG") }
print("Wrote \(outURL.path) (\(size)x\(size))")
