import Foundation

/// A head or a grip frame in the library. Ported from the prototype's `LIB`.
/// Watts and efficacy are only used for heads without a spec (see Specs.swift); beams match the spec sheets.
struct Lamp: Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case panel, point, fresnel, tube, practical, bounce, diff, flag
    }

    enum Group: String, CaseIterable, Codable, Sendable {
        case panels = "Panels"
        case point = "Point source"
        case tubes = "Tubes"
        case hmi = "HMI"
        case tungsten = "Tungsten"
        case practicals = "Practicals"
        case grip = "Grip"
    }

    let id: String
    let name: String
    /// Maker, or "generic", "practical" or "grip".
    let brand: String
    let group: Group
    let kind: Kind
    let watts: Double
    /// Full beam angle in degrees. 300 or more means it spills all round (practicals).
    let beam: Double
    /// Lowest and highest colour temperature in kelvin; nil for grip.
    let cct: ClosedRange<Double>?
    /// Lumens per watt.
    let efficacy: Double
    /// Footprint in metres, width by depth, as drawn on the plan.
    let width: Double
    let depth: Double

    var isLight: Bool { watts > 0 }
    var isGrip: Bool { kind == .bounce || kind == .diff || kind == .flag }
    var isHMI: Bool { group == .hmi }
    /// LED heads dim; HMIs and tungsten in the library are run at full.
    var isDimmable: Bool { isLight && group != .hmi && group != .tungsten }

    var fullName: String {
        ["generic", "grip", "practical"].contains(brand) ? name : "\(brand) \(name)"
    }

    var shortName: String {
        let trimmed = name.replacingOccurrences(of: " Pro", with: "").replacingOccurrences(of: "SkyPanel ", with: "")
        return String(trimmed.split(separator: ",").first ?? Substring(trimmed))
    }

    /// Modifiers that make sense on this kind of head. The first is the default.
    var modifiers: [String] {
        switch kind {
        case .panel: ["None", "Snapgrid 40°", "Softbox"]
        case .point: ["None", "Dome M", "Lantern", "Fresnel lens"]
        case .fresnel: ["Barn doors", "Snoot", "Chimera, medium", "8x8 full grid"]
        case .tube: ["None", "Honeycrate"]
        case .practical: ["None", "Shade"]
        case .diff: id == "f12" || id == "f20d" ? Diffusion.gridFirst : Diffusion.all
        default: ["None"]
        }
    }
}

/// What goes in a diff frame. A frame keeps its material in `PlacedLamp.modifier`.
enum Diffusion {
    struct Material: Sendable {
        let name: String
        /// Rough transmission, for planning only.
        let pass: Double
        /// How wide the light leaves the frame, in degrees.
        let spread: Double
    }

    /// Lightest to heaviest, roughly. Lee and Rosco numbers where gaffers use them.
    static let materials: [Material] = [
        Material(name: "Hampshire frost", pass: 0.85, spread: 90),
        Material(name: "Opal", pass: 0.75, spread: 110),
        Material(name: "251 quarter white", pass: 0.65, spread: 125),
        Material(name: "China silk", pass: 0.6, spread: 135),
        Material(name: "250 half white", pass: 0.5, spread: 145),
        Material(name: "Light grid cloth", pass: 0.45, spread: 155),
        Material(name: "216 full white", pass: 0.35, spread: 165),
        Material(name: "Half grid cloth", pass: 0.35, spread: 165),
        Material(name: "Magic cloth", pass: 0.3, spread: 170),
        Material(name: "Full grid cloth", pass: 0.25, spread: 170),
        Material(name: "Bleached muslin", pass: 0.2, spread: 175),
        Material(name: "Unbleached muslin", pass: 0.15, spread: 175),
    ]

    static let byName = Dictionary(uniqueKeysWithValues: materials.map { ($0.name, $0) })
    static let standard = "216 full white"
    static let all = [standard] + materials.map(\.name).filter { $0 != standard }
    static let gridFirst = ["Full grid cloth"] + materials.map(\.name).filter { $0 != "Full grid cloth" }

    /// Frame sizes, smallest first.
    static let frames = ["f4d", "f6", "f8d", "f12", "f20d"]

    /// The frame's material; older plots stored "None", which meant the frame's own default.
    static func material(_ frame: PlacedLamp) -> Material {
        byName[frame.modifier] ?? byName[frame.lamp?.modifiers.first ?? standard] ?? byName[standard]!
    }

    /// Light lost, in stops, as a gaffer would say it: "1½ stops".
    static func stops(_ m: Material) -> String {
        let s = (log2(1 / m.pass) * 2).rounded() / 2
        let whole = Int(s), half = s - Double(whole) >= 0.5
        let text = whole == 0 ? (half ? "½" : "0") : "\(whole)" + (half ? "½" : "")
        return text + (s == 1 ? " stop" : " stops")
    }
}

enum Gels {
    static let all = ["None", "¼ CTO", "½ CTO", "Full CTO", "¼ CTB", "½ CTB", "Full CTB", "¼ Plus green"]

    /// Rough transmission, for planning only.
    static let loss: [String: Double] = [
        "¼ CTO": 0.81, "½ CTO": 0.73, "Full CTO": 0.58,
        "¼ CTB": 0.74, "½ CTB": 0.52, "Full CTB": 0.36, "¼ Plus green": 0.9,
    ]
}

enum Modifiers {
    /// Rough transmission, for planning only. A fresnel lens concentrates, so it's above 1.
    static let loss: [String: Double] = [
        "Snapgrid 40°": 0.8, "Softbox": 0.45, "Dome M": 0.45, "Lantern": 0.35, "Fresnel lens": 1.3,
        "Snoot": 0.9, "Chimera, medium": 0.4, "8x8 full grid": 0.3, "Honeycrate": 0.85, "Shade": 0.6,
    ]

    /// Beam angle with the modifier on, in degrees. 300 and over glows all round. Missing means the head's own beam.
    static let beam: [String: Double] = [
        "Snapgrid 40°": 40, "Softbox": 130, "Dome M": 140, "Lantern": 300, "Fresnel lens": 30,
        "Snoot": 15, "Chimera, medium": 120, "8x8 full grid": 150, "Honeycrate": 70, "Shade": 300,
    ]
}

enum LampLibrary {
    static let all: [Lamp] = [
        Lamp(id: "s30", name: "SkyPanel S30-C", brand: "Arri", group: .panels, kind: .panel, watts: 210, beam: 105, cct: 2800...10000, efficacy: 60, width: 0.68, depth: 0.36),
        Lamp(id: "s60", name: "SkyPanel S60-C", brand: "Arri", group: .panels, kind: .panel, watts: 420, beam: 105, cct: 2800...10000, efficacy: 60, width: 0.68, depth: 0.36),
        Lamp(id: "x21", name: "SkyPanel X21", brand: "Arri", group: .panels, kind: .panel, watts: 800, beam: 121, cct: 2000...20000, efficacy: 65, width: 0.9, depth: 0.45),
        Lamp(id: "gem", name: "Gemini 1x1", brand: "Litepanels", group: .panels, kind: .panel, watts: 200, beam: 95, cct: 2700...10000, efficacy: 60, width: 0.4, depth: 0.4),
        Lamp(id: "lm4", name: "Litemat Spectrum 4", brand: "Litegear", group: .panels, kind: .panel, watts: 220, beam: 120, cct: 2700...6500, efficacy: 55, width: 1.2, depth: 0.3),
        Lamp(id: "a600", name: "600c Pro", brand: "Aputure", group: .point, kind: .point, watts: 720, beam: 55, cct: 2300...10000, efficacy: 70, width: 0.42, depth: 0.28),
        Lamp(id: "a1200", name: "1200d Pro", brand: "Aputure", group: .point, kind: .point, watts: 1400, beam: 66, cct: 5600...5600, efficacy: 75, width: 0.5, depth: 0.32),
        Lamp(id: "forza", name: "Forza 500", brand: "Nanlite", group: .point, kind: .point, watts: 580, beam: 55, cct: 5600...5600, efficacy: 70, width: 0.4, depth: 0.26),
        Lamp(id: "vtx", name: "Vortex8", brand: "Creamsource", group: .point, kind: .panel, watts: 650, beam: 110, cct: 2200...15000, efficacy: 70, width: 0.6, depth: 0.32),
        Lamp(id: "orb", name: "Orbiter", brand: "Arri", group: .point, kind: .point, watts: 500, beam: 60, cct: 2000...20000, efficacy: 65, width: 0.4, depth: 0.3),
        Lamp(id: "titan", name: "Titan Tube", brand: "Astera", group: .tubes, kind: .tube, watts: 72, beam: 135, cct: 1750...20000, efficacy: 60, width: 1.03, depth: 0.06),
        Lamp(id: "helios", name: "Helios Tube", brand: "Astera", group: .tubes, kind: .tube, watts: 36, beam: 135, cct: 1750...20000, efficacy: 60, width: 0.52, depth: 0.06),
        Lamp(id: "pavo", name: "PavoTube II 30X", brand: "Nanlite", group: .tubes, kind: .tube, watts: 36, beam: 160, cct: 2700...12000, efficacy: 55, width: 1.2, depth: 0.05),
        Lamp(id: "b7c", name: "Accent B7c", brand: "Aputure", group: .tubes, kind: .practical, watts: 7, beam: 300, cct: 2000...10000, efficacy: 60, width: 0.08, depth: 0.08),
        Lamp(id: "h12", name: "1.2K HMI par", brand: "generic", group: .hmi, kind: .fresnel, watts: 1200, beam: 30, cct: 5600...5600, efficacy: 90, width: 0.42, depth: 0.34),
        Lamp(id: "h4", name: "4K HMI par", brand: "generic", group: .hmi, kind: .fresnel, watts: 4000, beam: 30, cct: 5600...5600, efficacy: 90, width: 0.6, depth: 0.48),
        Lamp(id: "m18", name: "M18", brand: "Arri", group: .hmi, kind: .fresnel, watts: 1800, beam: 40, cct: 5600...5600, efficacy: 90, width: 0.5, depth: 0.42),
        Lamp(id: "h18", name: "18K HMI fresnel", brand: "generic", group: .hmi, kind: .fresnel, watts: 18000, beam: 50, cct: 5600...5600, efficacy: 95, width: 1, depth: 0.8),
        Lamp(id: "t300", name: "300W fresnel", brand: "generic", group: .tungsten, kind: .fresnel, watts: 300, beam: 55, cct: 3200...3200, efficacy: 20, width: 0.22, depth: 0.2),
        Lamp(id: "t650", name: "650W fresnel", brand: "generic", group: .tungsten, kind: .fresnel, watts: 650, beam: 54, cct: 3200...3200, efficacy: 20, width: 0.28, depth: 0.24),
        Lamp(id: "t1k", name: "1K fresnel", brand: "generic", group: .tungsten, kind: .fresnel, watts: 1000, beam: 54, cct: 3200...3200, efficacy: 20, width: 0.34, depth: 0.28),
        Lamp(id: "t2k", name: "2K fresnel", brand: "generic", group: .tungsten, kind: .fresnel, watts: 2000, beam: 57, cct: 3200...3200, efficacy: 20, width: 0.42, depth: 0.34),
        Lamp(id: "red", name: "Redhead 800W", brand: "generic", group: .tungsten, kind: .point, watts: 800, beam: 87, cct: 3200...3200, efficacy: 20, width: 0.26, depth: 0.22),
        Lamp(id: "lamp", name: "Table lamp", brand: "practical", group: .practicals, kind: .practical, watts: 60, beam: 300, cct: 2700...2700, efficacy: 15, width: 0.3, depth: 0.3),
        Lamp(id: "china", name: "China ball", brand: "practical", group: .practicals, kind: .practical, watts: 150, beam: 300, cct: 2700...5600, efficacy: 40, width: 0.5, depth: 0.5),
        Lamp(id: "f4", name: "4x4 frame, ultra bounce", brand: "grip", group: .grip, kind: .bounce, watts: 0, beam: 0, cct: nil, efficacy: 0, width: 1.2, depth: 0.06),
        Lamp(id: "f4d", name: "4x4 diff frame", brand: "grip", group: .grip, kind: .diff, watts: 0, beam: 0, cct: nil, efficacy: 0, width: 1.2, depth: 0.06),
        Lamp(id: "f6", name: "6x6 diff frame", brand: "grip", group: .grip, kind: .diff, watts: 0, beam: 0, cct: nil, efficacy: 0, width: 1.8, depth: 0.06),
        Lamp(id: "f8d", name: "8x8 diff frame", brand: "grip", group: .grip, kind: .diff, watts: 0, beam: 0, cct: nil, efficacy: 0, width: 2.4, depth: 0.06),
        Lamp(id: "f12", name: "12x12 diff frame", brand: "grip", group: .grip, kind: .diff, watts: 0, beam: 0, cct: nil, efficacy: 0, width: 3.6, depth: 0.08),
        Lamp(id: "f20d", name: "20x20 diff frame", brand: "grip", group: .grip, kind: .diff, watts: 0, beam: 0, cct: nil, efficacy: 0, width: 6.1, depth: 0.1),
        Lamp(id: "flag", name: "Flag 24x36", brand: "grip", group: .grip, kind: .flag, watts: 0, beam: 0, cct: nil, efficacy: 0, width: 0.9, depth: 0.06),
        Lamp(id: "floppy", name: "Floppy 4x4", brand: "grip", group: .grip, kind: .flag, watts: 0, beam: 0, cct: nil, efficacy: 0, width: 1.2, depth: 0.06),
        Lamp(id: "poly", name: "Poly bounce 4x8", brand: "grip", group: .grip, kind: .bounce, watts: 0, beam: 0, cct: nil, efficacy: 0, width: 1.2, depth: 0.08),
    ]

    static let byID: [String: Lamp] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func lamp(_ id: String) -> Lamp? { byID[id] }
}
