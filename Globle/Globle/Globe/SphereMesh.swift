import SceneKit

/// Builds a UV sphere whose texture mapping we fully control, so the equirectangular
/// map painted by `GlobeTextureRenderer` lines up exactly and "spin to a country" is precise.
///
/// Convention (matches `Geo.unitVector`): y up, east +X, the point at lon 0 / lat 0 faces +Z.
/// Texture coords: u = (lon+180)/360 increasing east, v = 0 at the north pole (top of the image).
enum SphereMesh {
    static func make(radius: Float = 1, stacks: Int = 90, slices: Int = 180) -> SCNGeometry {
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        positions.reserveCapacity((stacks + 1) * (slices + 1))

        for i in 0...stacks {
            let v = Float(i) / Float(stacks)              // 0 at north pole … 1 at south pole
            let latR = (Float.pi / 2) - v * Float.pi       // +90° … -90°
            for j in 0...slices {
                let u = Float(j) / Float(slices)           // 0 at lon -180 … 1 at lon +180
                let lonR = -Float.pi + u * 2 * Float.pi
                let x = cosf(latR) * sinf(lonR)
                let y = sinf(latR)
                let z = cosf(latR) * cosf(lonR)
                positions.append(SCNVector3(x * radius, y * radius, z * radius))
                normals.append(SCNVector3(x, y, z))
                // v stays 0 at the top → north drawn at the top of the texture.
                // (If the globe ever appears upside-down, use `1 - v` here.)
                uvs.append(CGPoint(x: CGFloat(u), y: CGFloat(v)))
            }
        }

        let cols = slices + 1
        var indices: [Int32] = []
        indices.reserveCapacity(stacks * slices * 6)
        for i in 0..<stacks {
            for j in 0..<slices {
                let a = Int32(i * cols + j)
                let b = Int32(i * cols + j + 1)
                let c = Int32((i + 1) * cols + j)
                let d = Int32((i + 1) * cols + j + 1)
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions),
                SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: uvs),
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        return geometry
    }
}
