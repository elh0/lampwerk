import Foundation

/// The classic setups a new plot can start from. Ported from the prototype's `SETUPS`.
enum Starter: String, Codable, CaseIterable, Identifiable, Sendable {
    case threePoint, rembrandt, window, car, blank

    var id: String { rawValue }

    var title: String {
        switch self {
        case .threePoint: "Three-point"
        case .rembrandt: "Rembrandt"
        case .window: "Window key"
        case .car: "Car interior"
        case .blank: "Empty room"
        }
    }

    static let talent = Point2(x: 3, y: 4.4)

    func items() -> [PlacedLamp] {
        let L = Starter.place
        switch self {
        case .threePoint:
            return [L("a600", 1.2, 3, .key, 5600, 80, []), L("f4", 4.7, 4.6, .fill, nil, nil, []), L("s30", 4.4, 2.1, .back, 5600, 60, [.reverse])]
        case .rembrandt:
            return [L("t1k", 1.3, 2.6, .key, 3200, nil, []), L("poly", 4.8, 5, .fill, nil, nil, []), L("titan", 4.6, 2.3, .kicker, 3200, 40, [.close])]
        case .window:
            var key = L("m18", -0.4, 3.6, .key, 5600, nil, [])
            key.modifier = "8x8 full grid"
            var back = L("s60", 4.9, 2.2, .back, 5600, 50, [.wide])
            back.gel = "½ CTB"
            return [key, L("f12", 0.5, 3.8, .diff, nil, nil, []), L("lamp", 4.6, 5.6, .practical, 2700, nil, [.close]), L("f4", 4.8, 4, .fill, nil, nil, []), back]
        case .car:
            return [L("titan", 2, 3.1, .key, 4300, 50, []), L("helios", 4, 3.3, .fill, 4300, 25, [.reverse]), L("b7c", 3, 5.2, .practical, 2400, 60, [])]
        case .blank:
            return []
        }
    }

    /// A lamp aimed at the talent; grip frames turn side-on so their face points at the talent.
    static func place(_ id: String, _ x: Double, _ y: Double, _ role: Role, _ cct: Double?, _ output: Double?, _ off: Set<Shot>) -> PlacedLamp {
        let lamp = LampLibrary.lamp(id)!
        let aim = Point2(x: x, y: y).bearing(to: talent)
        return PlacedLamp(
            lampID: id, x: x, y: y,
            angle: lamp.isGrip ? aim + 90 : aim,
            role: role,
            cct: cct ?? lamp.cct?.lowerBound ?? 5600,
            output: output ?? 100,
            modifier: lamp.modifiers[0],
            offIn: off
        )
    }
}
