import ModelIO
import SceneKit
import SceneKit.ModelIO
import UIKit

/// The stand-in for the camera preview: a neutral head and shoulders sculpted in code, so it carries no
/// third-party licence. One dense, smooth surface for the head (an ellipsoid shaped by soft bumps for the
/// brow, eyes, nose, cheeks, mouth, jaw, chin and ears), plus a neck and shoulders. Units are metres,
/// with the base of the neck at the origin and the eyes about 1.6 m up once it stands on the mark.
enum StandIn {
    /// Planes: a study head built from flat planes, so every change of light direction shows at a glance.
    /// Sculpt: the same head smooth, like a clay sculpt.
    enum Style: String { case planes, sculpt }

    /// Head, neck and shoulders in one node, already in the clay material.
    static func node(_ style: Style = .planes) -> SCNNode {
        if style == .sculpt, let scan = scanNode() { return scan }
        let root = SCNNode()
        let head = SCNNode(geometry: style == .planes ? PlanarHead.geometry() : headGeometry())
        head.position = SCNVector3(0, style == .planes ? 0.2 : 0.19, 0)
        root.addChildNode(head)

        let neckShape = SCNCylinder(radius: 0.062, height: 0.13)
        neckShape.radialSegmentCount = style == .planes ? 8 : 48
        let neck = SCNNode(geometry: neckShape)
        neck.position = SCNVector3(0, 0.06, -0.012)
        root.addChildNode(neck)

        // Shoulders: a capsule across the collarbones, and a rounded chest below it, cut off by the frame.
        let across = SCNCapsule(capRadius: 0.06, height: 0.36)
        across.radialSegmentCount = style == .planes ? 10 : 48
        across.capSegmentCount = style == .planes ? 6 : 24
        let shoulders = SCNNode(geometry: across)
        shoulders.eulerAngles.z = .pi / 2
        shoulders.position = SCNVector3(0, -0.03, -0.015)
        root.addChildNode(shoulders)

        let chestShape = SCNBox(width: 0.3, height: 0.3, length: 0.18, chamferRadius: 0.07)
        chestShape.chamferSegmentCount = style == .planes ? 2 : 12
        let chest = SCNNode(geometry: chestShape)
        chest.position = SCNVector3(0, -0.19, -0.02)
        root.addChildNode(chest)

        let clay = material()
        for n in [head, neck, shoulders, chest] {
            n.geometry?.materials = [clay]
            n.castsShadow = true
        }
        // A slight turn of the head, so the face isn't dead square to the lens.
        head.eulerAngles.y = -0.12
        return root
    }

    /// The sculpt: the Lee Perry-Smith head scan (Infinite-Realities, CC BY 3.0, credited in About),
    /// head and shoulders, in the same matte clay. Eyes sit 0.2 m above the node's origin, like the planar head.
    private static func scanNode() -> SCNNode? {
        guard let url = Bundle.main.url(forResource: "StandInScan", withExtension: "obj") else { return nil }
        let asset = MDLAsset(url: url)
        guard let mesh = asset.object(at: 0) as? MDLMesh else { return nil }
        let node = SCNNode(mdlObject: mesh)
        let clay = material()
        node.geometry?.materials = [clay]
        node.castsShadow = true
        node.position = SCNVector3(0, 0.2, 0)
        let root = SCNNode()
        root.addChildNode(node)
        return root
    }

    /// Matte off-white clay.
    static func material() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(white: 0.74, alpha: 1)
        m.isDoubleSided = true
        m.roughness.contents = 0.8
        m.metalness.contents = 0.0
        return m
    }

    /// The head as a grid over the sphere: rows top to bottom, columns round. Radius in metres.
    /// With `planes`, the smooth surface keeps its outline but its shading snaps to broad planes (forehead,
    /// temples, cheeks, nose wedge, jaw, chin), like a painter's planar study head.
    private static func headGeometry(rows: Int = 160, cols: Int = 224, planes: Bool = false) -> SCNGeometry {
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        positions.reserveCapacity((rows + 1) * (cols + 1))

        func point(_ theta: Double, _ phi: Double) -> SIMD3<Double> {
            // theta from the top (0) to the bottom (pi); phi round from the face (0 faces +z).
            let d = SIMD3(sin(theta) * sin(phi), cos(theta), sin(theta) * cos(phi))
            return surface(d)
        }

        for r in 0...rows {
            let theta = Double(r) / Double(rows) * .pi
            for c in 0...cols {
                let phi = Double(c) / Double(cols) * 2 * .pi
                let p = point(theta, phi)
                // Normal from the surface's own slope, so every bump shades smoothly.
                let e = 0.002
                let tu = point(min(.pi, theta + e), phi) - point(max(0, theta - e), phi)
                let tv = point(theta, phi + e) - point(theta, phi - e)
                var n = simd_cross(tv, tu)
                let len = simd_length(n)
                n = len > 1e-9 ? n / len : simd_normalize(p)
                if simd_dot(n, p) < 0 { n = -n }
                if planes {
                    // The plane comes from the big forms only, so small features don't break it into a mosaic.
                    let e2 = 0.01
                    let q = { (t: Double, f: Double) in surface(SIMD3(sin(t) * sin(f), cos(t), sin(t) * cos(f)), coarse: true) }
                    var cn = simd_cross(q(theta, phi + e2) - q(theta, phi - e2), q(min(.pi, theta + e2), phi) - q(max(0, theta - e2), phi))
                    let cl = simd_length(cn)
                    cn = cl > 1e-9 ? cn / cl : n
                    if simd_dot(cn, p) < 0 { cn = -cn }
                    n = plane(cn)
                }
                positions.append(SCNVector3(Float(p.x), Float(p.y), Float(p.z)))
                normals.append(SCNVector3(Float(n.x), Float(n.y), Float(n.z)))
            }
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(rows * cols * 6)
        let stride = UInt32(cols + 1)
        for r in 0..<UInt32(rows) {
            for c in 0..<UInt32(cols) {
                let a = r * stride + c, b = a + 1, d = a + stride, e = d + 1
                indices += [a, d, b, b, d, e]
            }
        }
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        return geometry
    }

    /// The same head cut into flat planes: a coarse grid over the sculpted surface, each triangle shaded flat.
    private static func planarGeometry(rows: Int = 18, cols: Int = 26) -> SCNGeometry {
        func point(_ r: Int, _ c: Int) -> SIMD3<Double> {
            let theta = Double(r) / Double(rows) * .pi
            let phi = Double(c) / Double(cols) * 2 * .pi
            return surface(SIMD3(sin(theta) * sin(phi), cos(theta), sin(theta) * cos(phi)))
        }
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        func tri(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) {
            var n = simd_cross(b - a, c - a)
            let len = simd_length(n)
            guard len > 1e-12 else { return }
            n /= len
            if simd_dot(n, (a + b + c) / 3) < 0 { n = -n }
            for p in [a, b, c] {
                positions.append(SCNVector3(Float(p.x), Float(p.y), Float(p.z)))
                normals.append(SCNVector3(Float(n.x), Float(n.y), Float(n.z)))
            }
        }
        for r in 0..<rows {
            for c in 0..<cols {
                let a = point(r, c), b = point(r, c + 1), d = point(r + 1, c), e = point(r + 1, c + 1)
                // Split each quad along its shorter diagonal, so the planes follow the form.
                if simd_distance(a, e) < simd_distance(b, d) { tri(a, d, e); tri(a, e, b) } else { tri(a, d, b); tri(b, d, e) }
            }
        }
        let indices = (0..<UInt32(positions.count)).map { $0 }
        return SCNGeometry(
            sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
    }

    /// Snaps a surface direction to its plane: steps of yaw round the head and pitch up and down,
    /// finer across the face where the planes are smaller.
    private static func plane(_ n: SIMD3<Double>) -> SIMD3<Double> {
        let yaw = atan2(n.x, n.z), pitch = asin(max(-1, min(1, n.y)))
        let face = abs(yaw) < 0.9
        let yawStep = (face ? 30.0 : 45.0) * .pi / 180
        let pitchStep = (face ? 28.0 : 40.0) * .pi / 180
        let y = (yaw / yawStep).rounded() * yawStep
        let p = (pitch / pitchStep).rounded() * pitchStep
        return SIMD3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
    }

    private static func bump(_ x: Double, _ cx: Double, _ wx: Double, _ y: Double, _ cy: Double, _ wy: Double) -> Double {
        exp(-pow((x - cx) / wx, 2) - pow((y - cy) / wy, 2))
    }

    private static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// Where the head's surface is in direction d (unit vector, y up, z towards the face), in metres.
    /// `coarse` keeps only the big forms, for working out which plane a point belongs to.
    private static func surface(_ d: SIMD3<Double>, coarse: Bool = false) -> SIMD3<Double> {
        let x = d.x, y = d.y, z = d.z
        let front = smooth(0.1, 0.55, z)
        // Narrower at the jaw, fuller at the crown.
        let jawTaper = 1 - 0.12 * smooth(-0.2, -0.9, y)
        let ax = 0.08 * jawTaper, ay = 0.108, az = 0.1 * (1 - 0.08 * smooth(-0.3, -0.9, y))
        var r = 1 / sqrt(pow(x / ax, 2) + pow(y / ay, 2) + pow(z / az, 2))
        var k = 0.0
        k += 0.05 * front * bump(x, 0, 0.42, y, 0.3, 0.08)                  // brow
        if !coarse { k -= 0.055 * front * (bump(x, 0.27, 0.13, y, 0.14, 0.08) + bump(x, -0.27, 0.13, y, 0.14, 0.08)) } // eyes
        k += 0.2 * front * bump(x, 0, 0.075, y, -0.02, 0.17)                 // nose bridge to tip
        if !coarse { k += 0.06 * front * bump(x, 0, 0.13, y, -0.13, 0.05) } // nose tip and wings
        k += 0.035 * front * (bump(x, 0.42, 0.14, y, -0.05, 0.12) + bump(x, -0.42, 0.14, y, -0.05, 0.12)) // cheekbones
        if !coarse { k += 0.035 * front * bump(x, 0, 0.18, y, -0.36, 0.05) } // lips
        if !coarse { k -= 0.02 * front * bump(x, 0, 0.2, y, -0.44, 0.03) } // under the lip
        k += 0.11 * front * bump(x, 0, 0.26, y, -0.62, 0.12)                 // chin
        k += 0.05 * smooth(0.3, 0.75, abs(x)) * bump(y, -0.5, 0.14, z, 0.3, 0.35) // jaw corners
        let side = smooth(0.82, 0.97, abs(x))
        if !coarse { k += 0.12 * side * bump(y, 0.02, 0.19, z, -0.08, 0.13) } // ears
        r *= 1 + k
        return d * r
    }
}
