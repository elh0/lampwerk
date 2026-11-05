import SceneKit

/// A planar study head, modelled by hand as flat planes (our own design): forehead, brow, eye sockets,
/// nose wedge, cheekbone, muzzle, lips, chin, jaw, skull and a simple ear. Each plane is shaded flat, so
/// the edge between lit and shadow planes shows the light's direction at a glance, the way painters and
/// photographers use a planar head. Metres, eyes at y = 0, face towards +z. Built for the right side and mirrored.
enum PlanarHead {
    private typealias P = SIMD3<Double>

    // Centre line.
    private static let c: [String: P] = [
        "top": P(0, 0.125, -0.02), "foreheadTop": P(0, 0.095, 0.075), "glabella": P(0, 0.025, 0.098),
        "bridge": P(0, 0.0, 0.1), "tip": P(0, -0.04, 0.125), "subnasal": P(0, -0.055, 0.103),
        "upperLip": P(0, -0.07, 0.106), "mouth": P(0, -0.08, 0.1), "lowerLip": P(0, -0.09, 0.102),
        "chin": P(0, -0.115, 0.093), "chinBase": P(0, -0.132, 0.07), "throat": P(0, -0.12, 0.02),
        "back": P(0, 0.07, -0.1), "occiput": P(0, -0.03, -0.095), "nape": P(0, -0.08, -0.06),
    ]
    // Right side (x > 0).
    private static let r: [String: P] = [
        "foreheadCorner": P(0.05, 0.085, 0.07), "templeTop": P(0.072, 0.07, 0.02), "browOuter": P(0.06, 0.03, 0.075),
        "browInner": P(0.025, 0.03, 0.095), "socketInner": P(0.02, 0.005, 0.085), "socketOuter": P(0.055, 0.0, 0.07),
        "cheekbone": P(0.065, -0.015, 0.06), "noseSideTop": P(0.012, -0.005, 0.095), "noseWing": P(0.018, -0.05, 0.1),
        "cheekFront": P(0.036, -0.03, 0.085), "mouthCorner": P(0.025, -0.08, 0.092), "muzzle": P(0.04, -0.07, 0.08),
        "chinSide": P(0.022, -0.118, 0.085), "jawFront": P(0.035, -0.125, 0.06), "jawAngle": P(0.064, -0.095, 0.005),
        "cheekLow": P(0.068, -0.055, 0.035), "headSide": P(0.078, 0.03, -0.02), "backUpper": P(0.065, 0.075, -0.07),
        "backLower": P(0.07, -0.02, -0.065), "skullSide": P(0.045, 0.115, -0.01), "neckSide": P(0.05, -0.115, -0.01),
        "behindEar": P(0.07, -0.06, -0.04),
        "earTop": P(0.083, 0.022, -0.015), "earLow": P(0.084, -0.035, -0.032),
        "earBackTop": P(0.092, 0.018, -0.045), "earBackLow": P(0.09, -0.03, -0.055),
    ]

    /// Each plane, as points in order round its edge. Names in `r` are mirrored for the left side.
    private static let planes: [[String]] = [
        ["foreheadTop", "foreheadCorner", "browOuter", "browInner", "glabella"],
        ["foreheadCorner", "templeTop", "browOuter"],
        ["top", "skullSide", "foreheadCorner", "foreheadTop"],
        ["skullSide", "templeTop", "foreheadCorner"],
        ["skullSide", "backUpper", "headSide", "templeTop"],
        ["top", "back", "backUpper", "skullSide"],
        ["back", "occiput", "backLower", "backUpper"],
        ["backUpper", "backLower", "behindEar", "headSide"],
        ["templeTop", "headSide", "socketOuter", "browOuter"],
        ["browInner", "browOuter", "socketOuter", "socketInner"],
        ["socketInner", "socketOuter", "cheekbone", "cheekFront"],
        ["glabella", "browInner", "socketInner", "noseSideTop", "bridge"],
        ["bridge", "noseSideTop", "noseWing", "tip"],
        ["tip", "noseWing", "subnasal"],
        ["socketInner", "cheekFront", "noseWing", "noseSideTop"],
        ["cheekbone", "cheekLow", "muzzle", "cheekFront"],
        ["socketOuter", "headSide", "cheekLow", "cheekbone"],
        ["subnasal", "noseWing", "mouthCorner", "upperLip"],
        ["noseWing", "cheekFront", "muzzle", "mouthCorner"],
        ["upperLip", "mouthCorner", "mouth"],
        ["mouth", "mouthCorner", "lowerLip"],
        ["lowerLip", "mouthCorner", "chinSide", "chin"],
        ["chin", "chinSide", "jawFront", "chinBase"],
        ["muzzle", "cheekLow", "jawAngle"],
        ["mouthCorner", "muzzle", "jawAngle", "jawFront", "chinSide"],
        ["chinBase", "jawFront", "neckSide", "throat"],
        ["jawFront", "jawAngle", "neckSide"],
        ["cheekLow", "headSide", "behindEar", "jawAngle"],
        ["jawAngle", "behindEar", "neckSide"],
        ["backLower", "occiput", "nape", "behindEar"],
        ["behindEar", "nape", "throat", "neckSide"],
        // The ear: a slim wedge standing off the side of the head.
        ["earTop", "earLow", "earBackLow", "earBackTop"],
        ["headSide", "earTop", "earBackTop"],
        ["behindEar", "earBackLow", "earLow"],
        ["headSide", "behindEar", "earLow", "earTop"],
    ]

    static func geometry() -> SCNGeometry {
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []

        func point(_ name: String, mirror: Bool) -> P {
            if let p = c[name] { return p }
            let p = r[name]!
            return mirror ? P(-p.x, p.y, p.z) : p
        }

        for side in [false, true] {
            for plane in planes {
                let pts = plane.map { point($0, mirror: side) }
                // One normal for the whole plane (Newell's method), so it shades as a single flat facet.
                var n = P(0, 0, 0)
                for i in pts.indices {
                    let a = pts[i], b = pts[(i + 1) % pts.count]
                    n += P((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
                }
                guard simd_length(n) > 1e-12 else { continue }
                n = simd_normalize(n)
                let centre = pts.reduce(P(0, 0, 0), +) / Double(pts.count)
                if simd_dot(n, centre - P(0, -0.01, -0.005)) < 0 { n = -n }
                for i in 1..<(pts.count - 1) {
                    for p in [pts[0], pts[i], pts[i + 1]] {
                        positions.append(SCNVector3(Float(p.x), Float(p.y), Float(p.z)))
                        normals.append(SCNVector3(Float(n.x), Float(n.y), Float(n.z)))
                    }
                }
            }
        }
        // Both faces of every triangle are drawn, so winding never hides a plane.
        let indices = (0..<UInt32(positions.count)).map { $0 }
        return SCNGeometry(
            sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
    }
}
