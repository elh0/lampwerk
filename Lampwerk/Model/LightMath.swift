import Foundation

/// Light and power maths, ported from the prototype (`luxFrom`, `luxAt`, `itemAmps`, `circuits`).
/// Every figure is approximate and the UI says so.
enum LightMath {
    /// Supply voltage. UK and EU 230 V, US 120 V.
    enum Supply: Double, Codable, CaseIterable, Sendable {
        case uk = 230
        case us = 120
    }

    static let circuitAmps = 16.0
    /// Warn when a circuit passes this share of its rating.
    static let warnShare = 0.8

    /// Lux from one lamp at a point:
    /// watts × efficacy × output × modifier × gel × diff ÷ (max(0.4, beam ÷ 60) × distance²) × 0.9.
    /// The beam is the one with the modifier and any diff frame in front. Outside the beam counts 12%.
    static func lux(from item: PlacedLamp, at p: Point2, in plot: Plot? = nil) -> Double {
        guard let lamp = item.lamp, lamp.isLight else { return 0 }
        let beam = spread(item, in: plot)
        let d = max(0.5, item.position.distance(to: p))
        let inBeam = beam >= 300 || angleBetween(item.position.bearing(to: p), item.angle) <= beam / 2 ? 1.0 : 0.12
        let frame = plot.flatMap { diffFrame(for: item, in: $0) }
        let lumens = lamp.watts * lamp.efficacy * (item.output / 100)
            * (Modifiers.loss[item.modifier] ?? 1) * (Gels.loss[item.gel] ?? 1)
            * (frame.map { diffLoss($0) } ?? 1)
        let spreadFactor = max(0.4, beam / 60)
        return (lumens * inBeam / (spreadFactor * d * d) * 0.9).rounded()
    }

    /// The beam angle as it leaves the head: the modifier's if it has one, opened up by a diff frame in front.
    static func spread(_ item: PlacedLamp, in plot: Plot? = nil) -> Double {
        guard let lamp = item.lamp else { return 0 }
        var beam = Modifiers.beam[item.modifier] ?? lamp.beam
        if beam < 300, let plot, let frame = diffFrame(for: item, in: plot) { beam = max(beam, Diffusion.material(frame).spread) }
        return beam
    }

    /// A diff frame standing in this head's beam, close enough to soften it.
    static func diffFrame(for item: PlacedLamp, in plot: Plot) -> PlacedLamp? {
        guard let lamp = item.lamp, lamp.isLight else { return nil }
        let own = Modifiers.beam[item.modifier] ?? lamp.beam
        guard own < 300 else { return nil }
        return plot.items
            .filter { $0.lamp?.kind == .diff }
            .filter { f in
                let d = item.position.distance(to: f.position)
                return d > 0.15 && d < 2.2 && angleBetween(item.position.bearing(to: f.position), item.angle) <= max(20, own / 2)
            }
            .min { item.position.distance(to: $0.position) < item.position.distance(to: $1.position) }
    }

    /// Rough transmission of a diff frame, from its material.
    static func diffLoss(_ frame: PlacedLamp) -> Double { Diffusion.material(frame).pass }

    /// Lux at a point from every lamp in a role that's on in the current setup.
    /// A bounce in the role returns about 45% of the key, scaled by frame size and falling off with distance.
    static func lux(in plot: Plot, at p: Point2, role: Role) -> Double {
        var total = 0.0
        for item in plot.items where item.role == role {
            guard let lamp = item.lamp else { continue }
            if lamp.isLight {
                if plot.isOn(item) { total += lux(from: item, at: p, in: plot) }
            } else if lamp.kind == .bounce {
                let key = plot.items.filter { plot.isOn($0) && $0.role == .key }.reduce(0) { $0 + lux(from: $1, at: p, in: plot) }
                let falloff = max(1, pow(item.position.distance(to: p), 2) / 2)
                total += key * 0.45 * min(1, lamp.width / 1.2) / falloff
            }
        }
        return total
    }

    static func keyLux(_ plot: Plot) -> Double { lux(in: plot, at: plot.talent, role: .key) }
    static func fillLux(_ plot: Plot) -> Double { lux(in: plot, at: plot.talent, role: .fill) }

    /// Key to fill, as a gaffer would say it: "4:1", "1.5:1", "1:2", "No fill".
    static func ratioText(_ plot: Plot) -> String {
        let k = keyLux(plot), f = fillLux(plot)
        guard k > 0 else { return "—" }
        guard f > 0 else { return "No fill" }
        let r = k / f
        if r < 1 { return "1:" + trim(1 / r) }
        let rounded = r < 3 ? (r * 2).rounded() / 2 : r.rounded()
        return trim(rounded) + ":1"
    }

    /// Full draw of a head: watts ÷ volts, HMIs ×1.1 for the ballast.
    static func amps(_ lamp: Lamp, supply: Supply = .uk) -> Double {
        guard lamp.isLight else { return 0 }
        return lamp.watts / supply.rawValue * (lamp.isHMI ? 1.1 : 1)
    }

    /// Draw at the current output. LED heads scale down, never below 15%.
    static func amps(_ item: PlacedLamp, supply: Supply = .uk) -> Double {
        guard let lamp = item.lamp else { return 0 }
        let full = amps(lamp, supply: supply)
        return lamp.isDimmable ? full * max(0.15, item.output / 100) : full
    }

    struct Circuit: Identifiable, Hashable {
        let id: String
        var amps: Double
        var items: [UUID]
        var share: Double { amps / LightMath.circuitAmps }
        var isWarning: Bool { share > LightMath.warnShare }
    }

    /// Packs every head on the plot into 16 A circuits at full draw, first fit, in plot order.
    static func circuits(_ plot: Plot, supply: Supply = .uk) -> [Circuit] {
        var out: [Circuit] = []
        for item in plot.items {
            guard let lamp = item.lamp, lamp.isLight else { continue }
            let a = amps(lamp, supply: supply)
            if let i = out.firstIndex(where: { $0.amps + a <= circuitAmps }) {
                out[i].amps += a
                out[i].items.append(item.id)
            } else {
                let letter = String(Character(UnicodeScalar(UInt8(65 + out.count % 26))))
                out.append(Circuit(id: letter, amps: a, items: [item.id]))
            }
        }
        return out
    }

    /// What's drawing right now: the heads on in this setup, at their output.
    static func load(_ plot: Plot, supply: Supply = .uk) -> (amps: Double, watts: Double) {
        var a = 0.0, w = 0.0
        for item in plot.lightsOn {
            a += amps(item, supply: supply)
            w += item.lamp?.watts ?? 0
        }
        return (a, w)
    }

    /// Smallest angle between two bearings, 0 to 180.
    static func angleBetween(_ a: Double, _ b: Double) -> Double {
        abs((((a - b).truncatingRemainder(dividingBy: 360)) + 540).truncatingRemainder(dividingBy: 360) - 180)
    }

    /// Beam drawn on the plan: length in metres, from the head's draw.
    static func beamLength(_ lamp: Lamp, output: Double) -> Double {
        min(5.5, 1.4 + sqrt(lamp.watts * output / 100) / 9)
    }

    /// Practicals glow all round instead of throwing a beam.
    static func glowRadius(_ lamp: Lamp, output: Double) -> Double {
        min(2.2, 0.6 + sqrt(lamp.watts * output / 100) / 8)
    }

    private static func trim(_ v: Double) -> String {
        let s = String(format: "%.1f", v)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}
