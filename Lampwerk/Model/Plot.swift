import Foundation

struct Point2: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    func distance(to other: Point2) -> Double { hypot(x - other.x, y - other.y) }
    /// Direction to another point in degrees, 0 = +x, clockwise on screen (y grows downward).
    func bearing(to other: Point2) -> Double { atan2(other.y - y, other.x - x) * 180 / .pi }
}

enum Role: String, Codable, CaseIterable, Sendable {
    case key, fill, back, kicker, practical, diff, neg
    var title: String { rawValue.capitalized }
}

/// One plan, three setups. Each remembers which lamps are on.
enum Shot: String, Codable, CaseIterable, Sendable {
    case wide, close, reverse
    var title: String { rawValue.capitalized }
}

/// A lamp or frame placed on a plot. Positions are metres from the room's top-left corner.
struct PlacedLamp: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var lampID: String
    var x: Double
    var y: Double
    /// Aim in degrees (see `Point2.bearing`). Grip frames store their face direction + 90.
    var angle: Double
    var role: Role
    var cct: Double
    /// Output in percent, 5 to 100.
    var output: Double = 100
    var modifier: String
    var gel = "None"
    /// Setups this lamp is switched off in.
    var offIn: Set<Shot> = []
    /// Head height in metres, when it was tagged in AR. Nil for lamps placed on the plan.
    var height: Double? = nil
    /// Your own name for it, e.g. "Window key". Falls back to the role.
    var name: String? = nil

    /// What the plan, the sheet and the lists call this lamp.
    var title: String {
        let n = name?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? role.title : n
    }

    var position: Point2 {
        get { Point2(x: x, y: y) }
        set { x = newValue.x; y = newValue.y }
    }

    var lamp: Lamp? { LampLibrary.lamp(lampID) }
}

struct Plot: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var number: Int
    var starter: Starter
    var shot: Shot = .wide
    var talent = Point2(x: 3, y: 4.4)
    var camera = Point2(x: 3, y: 7.6)
    /// Room size in metres.
    var roomWidth = 6.0
    var roomDepth = 8.4
    /// File name of the location's floor plan in Documents/floorplans, drawn under the plan.
    var floorPlan: String? = nil
    var items: [PlacedLamp]
    var updated = Date()

    func isOn(_ item: PlacedLamp) -> Bool {
        guard let lamp = item.lamp, lamp.isLight else { return false }
        return !item.offIn.contains(shot)
    }

    var lightsOn: [PlacedLamp] { items.filter(isOn) }
}
