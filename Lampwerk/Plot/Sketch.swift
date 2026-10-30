import Foundation

/// Sketch draws lamps and aims them; Move drags things around.
enum PlanMode { case sketch, move }

/// Reads a finger-drawn stroke on the plan as a lamp. A circle is a soft source, a triangle or scribble a hard light,
/// a box a panel, a long thin box a frame, a straight line a tube. A stroke drawn out from a lamp aims it.
enum Sketch {
    enum Shape: String, CaseIterable {
        case spot, soft, panel, frame, tube

        var word: String {
            switch self {
            case .spot: "hard"
            case .soft: "soft"
            case .panel: "panel"
            case .frame: "frame"
            case .tube: "tube"
            }
        }

        /// What each shape turns into until you've shown it something else.
        var fallback: String {
            switch self {
            case .spot: "a600"
            case .soft: "china"
            case .panel: "s60"
            case .frame: "f8d"
            case .tube: "titan"
            }
        }

        /// The shape a head would be drawn as.
        init(_ lamp: Lamp) {
            switch lamp.kind {
            case .panel: self = .panel
            case .tube: self = .tube
            case .practical: self = .soft
            case .bounce, .diff, .flag: self = .frame
            case .point, .fresnel: self = .spot
            }
        }

        /// The head this shape becomes: the last one of its sort you dropped or swapped to.
        var lamp: Lamp {
            let id = UserDefaults.standard.string(forKey: "sketch." + rawValue) ?? fallback
            return LampLibrary.lamp(id) ?? LampLibrary.lamp(fallback)!
        }

        /// Remember a head as the one to use next time this shape is drawn.
        static func remember(_ lamp: Lamp) {
            UserDefaults.standard.set(lamp.id, forKey: "sketch." + Shape(lamp).rawValue)
        }
    }

    enum Reading {
        case tap
        /// Aim in degrees; nil means straight at the talent.
        case aim(Double?)
        case shape(Shape, Point2)
        case unclear

        /// What the label beside your finger says while you draw.
        func label(from: PlacedLamp?) -> String? {
            switch self {
            case .tap, .unclear: return nil
            case .aim(let a): return "Aim \(from?.lamp?.shortName ?? "")" + (a == nil ? " at talent" : "")
            case .shape(let s, _): return "\(s.lamp.shortName) · \(s.word)"
            }
        }
    }

    static func read(_ pts: [Point2], from: PlacedLamp?, talent: Point2) -> Reading {
        guard let a = pts.first, let b = pts.last, pts.count > 1 else { return .tap }
        let len = zip(pts, pts.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        let gap = a.distance(to: b)
        if len < 0.2 { return .tap }
        if let from, gap > len * 0.6, gap > 0.4 {
            let aim = from.position.bearing(to: b), toTalent = from.position.bearing(to: talent)
            var off = abs(aim - toTalent).truncatingRemainder(dividingBy: 360)
            if off > 180 { off = 360 - off }
            return .aim(off < 15 ? nil : aim)
        }
        if gap < max(0.35, len * 0.22) {
            guard let shape = shape(pts) else { return .unclear }
            let c = Point2(x: pts.map(\.x).reduce(0, +) / Double(pts.count), y: pts.map(\.y).reduce(0, +) / Double(pts.count))
            return .shape(shape, c)
        }
        if gap / len > 0.85, gap > 0.5 {
            return .shape(.tube, Point2(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
        }
        return .unclear
    }

    /// Closed strokes: how much of its smallest box the shape fills, and how round it is.
    private static func shape(_ pts: [Point2]) -> Shape? {
        let h = hull(pts)
        guard h.count >= 3 else { return nil }
        var area = 0.0, perimeter = 0.0
        for (i, p) in h.enumerated() {
            let q = h[(i + 1) % h.count]
            area += p.x * q.y - q.x * p.y
            perimeter += p.distance(to: q)
        }
        area = abs(area) / 2
        // The smallest box, tried along each hull edge, so a tilted box still reads as a box.
        var best = (area: Double.infinity, w: 0.0, h: 0.0)
        for (i, p) in h.enumerated() {
            let q = h[(i + 1) % h.count], t = atan2(q.y - p.y, q.x - p.x), c = cos(-t), s = sin(-t)
            let xs = h.map { $0.x * c - $0.y * s }, ys = h.map { $0.x * s + $0.y * c }
            let w = xs.max()! - xs.min()!, d = ys.max()! - ys.min()!
            if w * d < best.area { best = (w * d, w, d) }
        }
        let fill = area / best.area
        let round = 4 * Double.pi * area / (perimeter * perimeter)
        let aspect = max(best.w, best.h) / max(0.01, min(best.w, best.h))
        if fill > 0.86 { return aspect > 2.6 ? .frame : .panel }
        if round > 0.78 { return .soft }
        return .spot
    }

    private static func hull(_ ps: [Point2]) -> [Point2] {
        let p = ps.sorted { $0.x < $1.x || ($0.x == $1.x && $0.y < $1.y) }
        func cross(_ o: Point2, _ a: Point2, _ b: Point2) -> Double { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lower: [Point2] = [], upper: [Point2] = []
        for q in p {
            while lower.count > 1, cross(lower[lower.count - 2], lower[lower.count - 1], q) <= 0 { lower.removeLast() }
            lower.append(q)
        }
        for q in p.reversed() {
            while upper.count > 1, cross(upper[upper.count - 2], upper[upper.count - 1], q) <= 0 { upper.removeLast() }
            upper.append(q)
        }
        return Array(lower.dropLast()) + Array(upper.dropLast())
    }
}
