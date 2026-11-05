import SwiftUI

/// A small picture of the talent as the camera sees them, lit by the plot: which side the key is on,
/// how hard it is, whether there's fill, a rim from anything behind, and the colour of each lamp.
/// Exposure is set for the key and white balance to the key's colour, the way a camera would be.
/// It's a guide to the shape of the light, not a render.
struct CameraPreview: View {
    let plot: Plot
    @State private var large = false

    var body: some View {
        let size = large ? CGSize(width: 150, height: 190) : CGSize(width: 84, height: 106)
        VStack(alignment: .leading, spacing: 3) {
            if let image = CameraPreview.render(plot, width: 168, height: 212) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.ruleStrong))
            }
            Text("CAMERA").font(.lwLabel).foregroundStyle(Palette.quiet)
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy(duration: 0.2)) { large.toggle() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camera view of the talent, lit by this plot. Tap to make it bigger.")
    }

    /// One light as the face sees it: direction in camera space, strength and colour.
    private struct Source {
        var dir: SIMD3<Double>
        var strength: Double
        var rgb: SIMD3<Double>
        /// 0 hard (a fresnel or open point source), up to 0.6 very soft (a big frame or a lantern).
        var wrap: Double
    }

    static func render(_ plot: Plot, width w: Int, height h: Int) -> CGImage? {
        let sources = sources(plot)
        // Exposure from the key at the talent, so a 4:1 looks like a 4:1 whatever the lux.
        let key = sources.filter { $0.strength > 0 }.map(\.strength).max() ?? 1
        let exposure = 0.85 / max(1, LightMath.keyLux(plot) > 0 ? LightMath.keyLux(plot) : key)
        let balance = SIMD3<Double>(1, 1, 1) / (keyColour(plot) + 0.0001)

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        // Head and shoulders as two ellipsoids, in a frame 1 wide.
        let aspect = Double(h) / Double(w)
        for py in 0..<h {
            for px in 0..<w {
                let x = (Double(px) + 0.5) / Double(w) - 0.5
                let y = (0.5 - (Double(py) + 0.5) / Double(h)) * aspect
                var normal: SIMD3<Double>?
                var albedo = 0.62
                // Head, a little above centre.
                let hx = x / 0.27, hy = (y - 0.12) / 0.36
                if hx * hx + hy * hy < 1 {
                    normal = SIMD3(hx, hy, (1 - hx * hx - hy * hy).squareRoot())
                } else {
                    // Shoulders and chest, wide and low; the neck in between.
                    let sx = x / 0.62, sy = (y + 0.62) / 0.42
                    let nx = x / 0.11, ny = (y + 0.26) / 0.18
                    if sx * sx + sy * sy < 1 && y < -0.3 {
                        normal = SIMD3(sx, sy, (1 - sx * sx - sy * sy).squareRoot())
                        albedo = 0.35
                    } else if nx * nx + ny * ny < 1 {
                        normal = SIMD3(nx * 0.8, 0, (1 - nx * nx * 0.64).squareRoot())
                        albedo = 0.55
                    }
                }
                var c = SIMD3<Double>(0.004, 0.004, 0.004)
                if let n0 = normal {
                    let n = n0 / (n0 * n0).sum().squareRoot()
                    var lit = SIMD3<Double>(0, 0, 0)
                    for s in sources {
                        let d = (n * s.dir).sum()
                        let shade = max(0, (d + s.wrap) / (1 + s.wrap))
                        lit += s.rgb * (shade * s.strength)
                    }
                    c = lit * exposure * albedo * balance + SIMD3(0.006, 0.006, 0.006)
                }
                // Soft shoulder of a film curve, so hot sides roll off instead of clipping hard.
                let mapped = SIMD3(1 - exp(-c.x * 1.6), 1 - exp(-c.y * 1.6), 1 - exp(-c.z * 1.6))
                let i = (py * w + px) * 4
                pixels[i] = UInt8(max(0, min(255, (mapped.x.squareRoot() * 255).rounded())))
                pixels[i + 1] = UInt8(max(0, min(255, (mapped.y.squareRoot() * 255).rounded())))
                pixels[i + 2] = UInt8(max(0, min(255, (mapped.z.squareRoot() * 255).rounded())))
                pixels[i + 3] = 255
            }
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    /// Every light that's on, turned into camera space: x to the camera's right, y up, z towards the lens.
    private static func sources(_ plot: Plot) -> [Source] {
        let t = plot.talent
        var f = SIMD2(plot.camera.x - t.x, plot.camera.y - t.y)
        let fl = (f * f).sum().squareRoot()
        f = fl > 0 ? f / fl : SIMD2(0, 1)
        // The plan's y runs down the screen, so the camera's right is (f.y, -f.x).
        let right = SIMD2(f.y, -f.x)
        let headHeight = 1.6
        var out: [Source] = []
        for item in plot.items {
            guard let lamp = item.lamp else { continue }
            let lux: Double
            var position = item.position
            var height = IsoCanvas.height(item)
            var wrap: Double
            if lamp.isLight {
                guard plot.isOn(item) else { continue }
                lux = LightMath.lux(from: item, at: t, in: plot)
                wrap = softness(item, lamp, plot)
            } else if lamp.kind == .bounce {
                // A bounce re-lights from where it stands, softly, with about 45% of the key.
                let key = plot.items.filter { plot.isOn($0) && $0.role == .key }.reduce(0) { $0 + LightMath.lux(from: $1, at: t, in: plot) }
                let falloff = max(1, pow(item.position.distance(to: t), 2) / 2)
                lux = key * 0.45 * min(1, lamp.width / 1.2) / falloff
                height = headHeight
                wrap = 0.55
                position = item.position
            } else {
                continue
            }
            guard lux > 0 else { continue }
            let d2 = SIMD2(position.x - t.x, position.y - t.y)
            let flat = (d2 * d2).sum().squareRoot()
            guard flat > 0.01 else { continue }
            var dir = SIMD3((d2 * right).sum() / flat, (height - headHeight) / max(flat, 0.3), (d2 * f).sum() / flat)
            dir /= (dir * dir).sum().squareRoot()
            out.append(Source(dir: dir, strength: lux, rgb: colour(item), wrap: wrap))
        }
        return out
    }

    /// How soft a head is at the face: its kind, its modifier and any diff frame in front.
    private static func softness(_ item: PlacedLamp, _ lamp: Lamp, _ plot: Plot) -> Double {
        var w: Double
        switch lamp.kind {
        case .panel: w = 0.35
        case .tube: w = 0.3
        case .practical: w = 0.45
        default: w = 0.05
        }
        switch item.modifier {
        case "Softbox", "Chimera, medium", "Dome M": w = max(w, 0.45)
        case "Lantern", "8x8 full grid": w = max(w, 0.55)
        case "Snapgrid 40°", "Honeycrate", "Snoot", "Fresnel lens": w = min(w, 0.15)
        default: break
        }
        if LightMath.diffFrame(for: item, in: plot) != nil { w = max(w, 0.5) }
        return w
    }

    /// The colour a head gives after its gel, as linear RGB with green as 1.
    private static func colour(_ item: PlacedLamp) -> SIMD3<Double> {
        let shift: [String: Double] = ["¼ CTO": 64, "½ CTO": 109, "Full CTO": 159, "¼ CTB": -30, "½ CTB": -68, "Full CTB": -131]
        var k = item.cct > 0 ? item.cct : 5600
        if let m = shift[item.gel] { k = 1_000_000 / (1_000_000 / k + m) }
        var c = kelvin(k)
        if item.gel == "¼ Plus green" { c *= SIMD3(0.92, 1, 0.92) }
        return c
    }

    private static func keyColour(_ plot: Plot) -> SIMD3<Double> {
        let key = plot.items.first { $0.role == .key && plot.isOn($0) }
        return key.map(colour) ?? kelvin(5600)
    }

    /// Black-body colour, close enough for a preview (Tanner Helland's fit), normalised to green.
    private static func kelvin(_ k: Double) -> SIMD3<Double> {
        let t = max(1000, min(40000, k)) / 100
        let r = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let g = t <= 66 ? 99.4708025861 * log(t) - 161.1195681661 : 288.1221695283 * pow(t - 60, -0.0755148492)
        let b = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307)
        let c = SIMD3(max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b))) / 255
        // Into linear light, then green-normalised so colour doesn't change brightness.
        let lin = SIMD3(pow(c.x, 2.2), pow(c.y, 2.2), pow(c.z, 2.2))
        return lin / max(lin.y, 0.0001)
    }
}
