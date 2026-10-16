import Foundation
import Observation
import simd

/// What's been tagged on the floor so far, in ARKit world space (metres, y up).
/// Floor points are kept as (x, z). Turned into a normal plot when you tap Done.
@MainActor
@Observable
final class ARTagModel {
    enum Step { case refA, refB, talent, camera, lamps }

    struct Tag: Identifiable, Equatable {
        let id = UUID()
        var lampID: String
        var role: Role
        var floor: SIMD2<Float>
        var height: Float
        var name = ""

        var lamp: Lamp? { LampLibrary.lamp(lampID) }
    }

    /// The heads offered on the rail while tagging. The full library stays in the plan editor.
    static let rail = ["a600", "s60", "titan", "m18", "t650", "china", "f4", "flag"]

    var step: Step = .talent
    var talent: SIMD2<Float>?
    var camera: SIMD2<Float>?
    var floorY: Float = 0
    var tags: [Tag] = []
    var selected: Tag.ID?
    var choice = "a600"

    /// Two spots picked on the floor plan (plot metres) and the same spots tagged in AR (world x, z).
    /// With both, Done lays the tags onto the plan instead of drawing a new room.
    var planA: Point2?
    var planB: Point2?
    var refA: SIMD2<Float>?
    var refB: SIMD2<Float>?
    var aligned: Bool { planA != nil && planB != nil && refA != nil && refB != nil }

    /// Starts by tagging the two plan spots.
    func lineUp(_ a: Point2, _ b: Point2) {
        planA = a
        planB = b
        step = .refA
        revision += 1
    }

    /// Where the centre of the screen meets the floor, if it does.
    var reticle: SIMD2<Float>?
    var trackingReady = false
    /// Screen positions for the labels drawn over the camera, keyed by tag id, "talent" and "camera".
    var screen: [String: CGPoint] = [:]
    /// Bumped whenever the placed things change, so the AR scene rebuilds its markers.
    var revision = 0

    var hint: String {
        if !trackingReady { return "Move the phone slowly to find the floor" }
        if reticle == nil { return "Point at the floor" }
        switch step {
        case .refA: return "Point at spot A from the plan, tap +"
        case .refB: return "Now spot B, tap +"
        case .talent: return "Point at where talent stands, tap +"
        case .camera: return "Now the camera position, tap +"
        case .lamps:
            if selected != nil { return "Set the head height below" }
            return "Tap + to stand a \(LampLibrary.lamp(choice)?.shortName ?? "lamp") here"
        }
    }

    var canFinish: Bool { talent != nil && camera != nil }

    /// Distance along the floor from the reticle to the talent mark.
    var reticleToTalent: Float? {
        guard let r = reticle, let t = talent else { return nil }
        return simd_distance(r, t)
    }

    func tag() {
        guard let r = reticle else { return }
        switch step {
        case .refA:
            refA = r
            step = .refB
        case .refB:
            refB = r
            step = .talent
        case .talent:
            talent = r
            step = .camera
        case .camera:
            camera = r
            step = .lamps
        case .lamps:
            guard let lamp = LampLibrary.lamp(choice) else { return }
            let tag = Tag(lampID: choice, role: Self.defaultRole(lamp, existing: tags), floor: r, height: Self.defaultHeight(lamp))
            tags.append(tag)
            selected = tag.id
        }
        revision += 1
    }

    func undo() {
        switch step {
        case .lamps where !tags.isEmpty:
            tags.removeLast()
            selected = nil
        case .lamps:
            camera = nil
            step = .camera
        case .camera:
            talent = nil
            step = .talent
        case .talent where planA != nil:
            refB = nil
            step = .refB
        case .talent:
            break
        case .refB:
            refA = nil
            step = .refA
        case .refA:
            break
        }
        revision += 1
    }

    func delete(_ id: Tag.ID) {
        tags.removeAll { $0.id == id }
        selected = nil
        revision += 1
    }

    static func defaultHeight(_ lamp: Lamp) -> Float {
        switch lamp.kind {
        case .fresnel: lamp.isHMI ? 3.0 : 2.3
        case .point: 2.4
        case .panel: 2.2
        case .tube: 1.8
        case .practical: 2.2
        case .bounce, .diff: 1.2
        case .flag: 1.8
        }
    }

    static func defaultRole(_ lamp: Lamp, existing: [Tag]) -> Role {
        switch lamp.kind {
        case .bounce: return .fill
        case .diff: return .diff
        case .flag: return .neg
        case .practical: return .practical
        case .tube: return .back
        default: return existing.contains { $0.role == .key } ? .fill : .key
        }
    }

    /// Lays the tags out as a plot. Everything is kept relative to the talent and the camera,
    /// with the camera at the bottom looking up the plan, so the same plot can be laid out on another set later.
    func plot(from base: Plot) -> Plot? {
        if aligned { return alignedPlot(from: base) }
        guard let t = talent, let c = camera else { return nil }
        var u = c - t
        let len = simd_length(u)
        u = len > 0.05 ? u / len : SIMD2<Float>(0, 1)
        // Camera looks from c to t; its right-hand side on the floor.
        let right = SIMD2<Float>(u.y, -u.x)
        func local(_ p: SIMD2<Float>) -> (x: Double, y: Double) {
            let d = p - t
            return (Double(simd_dot(d, right)), Double(simd_dot(d, u)))
        }

        let points = [t, c] + tags.map(\.floor)
        let locals = points.map(local)
        let margin = 1.0
        let minX = locals.map { $0.x }.min()!, maxX = locals.map { $0.x }.max()!
        let minY = locals.map { $0.y }.min()!, maxY = locals.map { $0.y }.max()!
        let offX = margin - minX, offY = margin - minY

        var plot = base
        plot.roomWidth = max(3, (maxX - minX) + margin * 2)
        plot.roomDepth = max(3, (maxY - minY) + margin * 2)
        plot.talent = Point2(x: offX, y: offY)
        let cl = local(c)
        plot.camera = Point2(x: cl.x + offX, y: cl.y + offY)
        plot.items = tags.compactMap { tag in
            guard let lamp = tag.lamp else { return nil }
            let l = local(tag.floor)
            let pos = Point2(x: l.x + offX, y: l.y + offY)
            let aim = pos.bearing(to: plot.talent)
            return PlacedLamp(
                lampID: lamp.id, x: pos.x, y: pos.y,
                angle: lamp.isGrip ? aim + 90 : aim,
                role: tag.role,
                cct: lamp.cct?.lowerBound ?? 5600,
                modifier: lamp.modifiers[0],
                height: Double(tag.height),
                name: tag.name.isEmpty ? nil : tag.name
            )
        }
        return plot
    }

    /// Lays the tags onto the existing plan using the two shared spots: turn and slide the AR
    /// world so A and B land on the plan's A and B. If the plan's scale disagrees with the
    /// measured distance, the room (and the plan stretched over it) is resized to match.
    private func alignedPlot(from base: Plot) -> Plot? {
        guard let t = talent, let c = camera, let pa = planA, let pb = planB, let wa = refA, let wb = refB else { return nil }
        let worldDist = Double(simd_distance(wa, wb))
        let planDist = pa.distance(to: pb)
        guard worldDist > 0.2, planDist > 0.05 else { return nil }

        var plot = base
        var k = worldDist / planDist
        if k < 0.33 || k > 3 { k = 1 }   // Way off means a mis-tap, not a wrong scale.
        plot.roomWidth *= k
        plot.roomDepth *= k
        let a = Point2(x: pa.x * k, y: pa.y * k), b = Point2(x: pb.x * k, y: pb.y * k)

        // Seen from above, world (x, z) and plan (x, y) turn the same way, so a rotation is enough.
        let angleW = atan2(Double(wb.y - wa.y), Double(wb.x - wa.x))
        let angleP = atan2(b.y - a.y, b.x - a.x)
        let r = angleP - angleW, cr = cos(r), sr = sin(r)
        func map(_ w: SIMD2<Float>) -> Point2 {
            let dx = Double(w.x - wa.x), dy = Double(w.y - wa.y)
            return Point2(x: a.x + dx * cr - dy * sr, y: a.y + dx * sr + dy * cr)
        }

        plot.talent = map(t)
        plot.camera = map(c)
        plot.items = tags.compactMap { tag in
            guard let lamp = tag.lamp else { return nil }
            let pos = map(tag.floor)
            let aim = pos.bearing(to: plot.talent)
            return PlacedLamp(
                lampID: lamp.id, x: pos.x, y: pos.y,
                angle: lamp.isGrip ? aim + 90 : aim,
                role: tag.role,
                cct: lamp.cct?.lowerBound ?? 5600,
                modifier: lamp.modifiers[0],
                height: Double(tag.height),
                name: tag.name.isEmpty ? nil : tag.name
            )
        }
        return plot
    }
}
