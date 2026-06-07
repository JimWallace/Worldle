import UIKit

/// Paints the equirectangular map texture wrapped onto the globe with Core Graphics.
///
/// The base layer (oceans + every country in soft green + faint borders) is drawn once
/// and cached; each turn we composite the guessed countries (colored by closeness) on top.
final class GlobeTextureRenderer {
    let size: CGSize
    private let countries: [Country]
    private lazy var baseImage: UIImage = makeBaseImage()

    // Palette
    private let ocean   = UIColor(red: 0.13, green: 0.28, blue: 0.46, alpha: 1)
    private let land    = UIColor(red: 0.60, green: 0.72, blue: 0.55, alpha: 1)
    private let border  = UIColor(white: 1, alpha: 0.30)
    private let guessBorder = UIColor(white: 0, alpha: 0.45)

    init(countries: [Country], width: Int = 2048) {
        self.countries = countries
        self.size = CGSize(width: width, height: width / 2)
    }

    // MARK: - Public

    /// The plain map with no guesses (used before the first guess).
    func baseTexture() -> UIImage { baseImage }

    /// The map with each guessed country filled by its proximity color, plus an
    /// optional revealed mystery country marked with a bright ring.
    func texture(fills: [(country: Country, color: UIColor)],
                 reveal: (country: Country, color: UIColor)?) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size, format: opaqueFormat())
        return renderer.image { context in
            baseImage.draw(in: CGRect(origin: .zero, size: size))
            let ctx = context.cgContext
            for entry in fills {
                fill(entry.country, color: entry.color.withAlphaComponent(0.95), in: ctx)
                stroke(entry.country, color: guessBorder, width: 1.5, in: ctx)
            }
            if let reveal {
                fill(reveal.country, color: reveal.color, in: ctx)
                stroke(reveal.country, color: UIColor(white: 1, alpha: 0.9), width: 2.5, in: ctx)
                drawMarker(at: reveal.country, fill: reveal.color, ring: .white, radius: markerRadius * 1.6, in: ctx)
            }
        }
    }

    // MARK: - Base layer

    private func makeBaseImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size, format: opaqueFormat())
        return renderer.image { context in
            let ctx = context.cgContext
            ocean.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            for country in countries {
                fill(country, color: land, in: ctx)
            }
            for country in countries {
                stroke(country, color: border, width: 0.8, in: ctx)
            }
        }
    }

    // MARK: - Drawing helpers

    private var markerRadius: CGFloat { max(3, size.width / 320) }

    private func opaqueFormat() -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = true
        format.scale = 1
        return format
    }

    private func project(lon: Double, lat: Double, offset: Double = 0) -> CGPoint {
        CGPoint(x: (lon + offset + 180.0) / 360.0 * size.width,
                y: (90.0 - lat) / 180.0 * size.height)
    }

    private func fill(_ country: Country, color: UIColor, in ctx: CGContext) {
        if isTiny(country) {
            drawMarker(at: country, fill: color, ring: nil, radius: markerRadius, in: ctx)
            return
        }
        color.setFill()
        for polygon in country.geometry {
            ctx.beginPath()
            for ring in polygon { addRingSubpaths(ring, to: ctx) }
            ctx.fillPath(using: .evenOdd)
        }
    }

    private func stroke(_ country: Country, color: UIColor, width: CGFloat, in ctx: CGContext) {
        guard !isTiny(country) else { return }
        color.setStroke()
        ctx.setLineWidth(width)
        ctx.setLineJoin(.round)
        for polygon in country.geometry {
            for ring in polygon {
                ctx.beginPath()
                addRingSubpaths(ring, to: ctx)
                ctx.strokePath()
            }
        }
    }

    /// Adds a ring as one (or, for antimeridian-spanning rings, three offset) closed subpaths.
    private func addRingSubpaths(_ ring: [[Double]], to ctx: CGContext) {
        guard ring.count >= 3 else { return }
        let lons = ring.map { $0[0] }
        let span = (lons.max() ?? 0) - (lons.min() ?? 0)
        let offsets: [Double] = span > 180 ? [-360, 0, 360] : [0]
        for offset in offsets {
            for (index, point) in ring.enumerated() where point.count == 2 {
                let p = project(lon: point[0], lat: point[1], offset: offset)
                if index == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
            }
            ctx.closePath()
        }
    }

    private func drawMarker(at country: Country, fill: UIColor, ring: UIColor?, radius: CGFloat, in ctx: CGContext) {
        let center = project(lon: country.lon, lat: country.lat)
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        fill.setFill()
        ctx.fillEllipse(in: rect)
        if let ring {
            ring.setStroke()
            ctx.setLineWidth(max(1, radius * 0.35))
            ctx.strokeEllipse(in: rect)
        }
    }

    /// A country is "tiny" (drawn as a dot) when its footprint is barely a pixel or two.
    private func isTiny(_ country: Country) -> Bool {
        var minLon = 999.0, maxLon = -999.0, minLat = 999.0, maxLat = -999.0
        for polygon in country.geometry {
            for ring in polygon {
                for point in ring where point.count == 2 {
                    minLon = min(minLon, point[0]); maxLon = max(maxLon, point[0])
                    minLat = min(minLat, point[1]); maxLat = max(maxLat, point[1])
                }
            }
        }
        guard maxLon >= minLon else { return true } // no geometry → dot
        let widthPx = (maxLon - minLon) / 360.0 * Double(size.width)
        let heightPx = (maxLat - minLat) / 180.0 * Double(size.height)
        return max(widthPx, heightPx) < Double(markerRadius)
    }
}
