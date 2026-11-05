import SwiftUI

/// Turns plot metres into points for the 3D view. The room turns about a pivot (yaw) and tips towards you (pitch).
struct IsoProjection {
    var yaw: Double
    var pitch: Double
    var scale: CGFloat
    var centre: CGPoint
    var pivot: Point2

    static let roomHeight = 2.8
    static let defaultYaw = 0.75
    static let defaultPitch = 0.62

    /// Unscaled, centred on the pivot.
    private static func raw(_ x: Double, _ y: Double, _ z: Double, yaw: Double, pitch: Double, pivot: Point2) -> CGPoint {
        let dx = x - pivot.x, dy = y - pivot.y, c = cos(yaw), s = sin(yaw)
        return CGPoint(x: dx * c - dy * s, y: (dx * s + dy * c) * sin(pitch) - z * cos(pitch))
    }

    /// Fits the room, its walls and a margin for the call-outs into a view.
    static func fit(_ plot: Plot, in size: CGSize, yaw: Double, pitch: Double, zoom: CGFloat) -> IsoProjection {
        let pivot = Point2(x: plot.roomWidth / 2, y: plot.roomDepth / 2)
        var pts: [CGPoint] = []
        for (x, y) in [(0.0, 0.0), (plot.roomWidth, 0), (plot.roomWidth, plot.roomDepth), (0, plot.roomDepth)] {
            pts.append(raw(x, y, 0, yaw: yaw, pitch: pitch, pivot: pivot))
            pts.append(raw(x, y, roomHeight, yaw: yaw, pitch: pitch, pivot: pivot))
        }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let w = (xs.max()! - xs.min()!) + 3.4, h = (ys.max()! - ys.min()!) + 1.6
        let scale = min(size.width / w, size.height / h) * zoom
        let mid = CGPoint(x: (xs.max()! + xs.min()!) / 2, y: (ys.max()! + ys.min()!) / 2)
        return IsoProjection(yaw: yaw, pitch: pitch, scale: scale,
                             centre: CGPoint(x: size.width / 2 - mid.x * scale, y: size.height / 2 - mid.y * scale), pivot: pivot)
    }

    func point(_ x: Double, _ y: Double, _ z: Double = 0) -> CGPoint {
        let r = Self.raw(x, y, z, yaw: yaw, pitch: pitch, pivot: pivot)
        return CGPoint(x: centre.x + r.x * scale, y: centre.y + r.y * scale)
    }

    func point(_ p: Point2, _ z: Double = 0) -> CGPoint { point(p.x, p.y, z) }

    /// Where a point on screen lands on a level plane at height z.
    func floor(at s: CGPoint, z: Double = 0) -> Point2 {
        let rx = (s.x - centre.x) / scale, ry = ((s.y - centre.y) / scale + z * cos(pitch)) / sin(pitch)
        let c = cos(yaw), sn = sin(yaw)
        return Point2(x: rx * c + ry * sn + pivot.x, y: -rx * sn + ry * c + pivot.y)
    }

    /// Bigger is nearer to you.
    func depth(_ x: Double, _ y: Double) -> Double {
        (x - pivot.x) * sin(yaw) + (y - pivot.y) * cos(yaw)
    }
}

/// The 3D view: an architect's line drawing of the room you can walk around and edit.
/// Drag a lamp, the talent or the camera to move it, drag empty floor to turn the room, pinch to zoom,
/// and drag the yellow handles on two walls to grow or shrink the set.
struct IsoCanvas: View {
    @Binding var plot: Plot
    @Binding var selected: PlacedLamp.ID?
    @Binding var zoom: CGFloat
    @Binding var popTab: LampPop.Tab
    /// The lamp's card: a first tap only picks the lamp (so it can be dragged); a second tap opens this.
    var cardOpen: Binding<Bool> = .constant(false)
    /// Opens the lamp list to change the picked lamp's head.
    var change: () -> Void = {}
    @Binding var yaw: Double
    @Binding var pitch: Double
    var armed: Lamp?
    var drop: (String, Point2) -> Void
    var more: () -> Void
    /// Off for exported pictures.
    var showHandles = true
    /// Off while the drawer shows the lamp's full settings, so only one panel is ever open.
    var showPop = true
    /// A line for whatever just happened.
    var say: (String) -> Void = { _ in }

    @State private var drag: DragState?
    @State private var hold: Task<Void, Never>?
    @GestureState private var pinch: CGFloat = 1

    private enum Target { case lamp(PlacedLamp.ID), talent(Double), camera(Double), wall(Bool), turn(Double, Double), none }

    private struct DragState {
        var target: Target
        var moved = false
        /// A press and hold removed the lamp, so letting go does nothing more.
        var held = false
        /// Held still while a wall is dragged, so the room doesn't slide out from under your finger.
        var locked: IsoProjection?
    }

    static let stands = [0.6, 1.2, 1.8, 2.4, 3.0, 3.6, 4.2]

    /// Head height: what AR measured or you set, otherwise a sensible stand height for the kind of head.
    static func height(_ item: PlacedLamp) -> Double {
        if let h = item.height { return h }
        guard let lamp = item.lamp else { return 1.8 }
        switch lamp.kind {
        case .bounce, .diff, .flag: return 0
        case .practical: return 2.4
        case .tube: return 1.2
        case .panel: return 1.8
        default: return 2.3
        }
    }

    var body: some View {
        GeometryReader { geo in
            let v = drag?.locked ?? IsoProjection.fit(plot, in: geo.size, yaw: yaw, pitch: pitch, zoom: min(5, max(0.6, zoom * pinch)))
            Canvas { ctx, _ in draw(ctx, v) }
                .contentShape(Rectangle())
                .gesture(gesture(v))
                .dropDestination(for: String.self) { ids, location in
                    guard let id = ids.first, LampLibrary.lamp(id) != nil else { return false }
                    drop(id, v.floor(at: location))
                    return true
                }
                .overlay(alignment: .bottom) {
                // The card sits docked under the plan, never over the lamp, so the lamp can always be dragged
                // and the card never runs off the screen. Too wide for the screen, it scrolls sideways.
                if showPop, cardOpen.wrappedValue, let id = selected, drag?.moved != true, plot.items.contains(where: { $0.id == id }) {
                    ViewThatFits(in: .horizontal) {
                        LampPop(plot: $plot, id: id, tab: $popTab, more: more, showHeight: true, change: change)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LampPop(plot: $plot, id: id, tab: $popTab, more: more, showHeight: true, change: change)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 70)
                    .transition(.opacity)
                }
            }
                .simultaneousGesture(
                    MagnifyGesture()
                        .updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in zoom = min(5, max(0.6, zoom * value.magnification)) }
                )
                .accessibilityLabel("3D view of the room. Drag lamps to move them, drag the floor to turn the room, pinch to zoom.")
        }
    }

    // MARK: Drawing

    private func draw(_ ctx: GraphicsContext, _ v: IsoProjection) {
        let line = Palette.text.opacity(0.9), quiet = Palette.quiet, W = plot.roomWidth, D = plot.roomDepth
        let thin = StrokeStyle(lineWidth: 1), hair = StrokeStyle(lineWidth: 0.5)
        let sY = sin(v.yaw), cY = cos(v.yaw)

        // Floor grid and outline.
        var grid = Path()
        for x in stride(from: 1.0, to: W, by: 1) { grid.move(to: v.point(x, 0)); grid.addLine(to: v.point(x, D)) }
        for y in stride(from: 1.0, to: D, by: 1) { grid.move(to: v.point(0, y)); grid.addLine(to: v.point(W, y)) }
        ctx.stroke(grid, with: .color(Palette.text.opacity(0.07)), style: hair)
        ctx.stroke(poly([v.point(0, 0), v.point(W, 0), v.point(W, D), v.point(0, D)]), with: .color(line), style: thin)

        // Only the two far walls stand, so the room stays open towards you from any angle.
        let walls: [(Point2, Point2, Double)] = [
            (Point2(x: 0, y: 0), Point2(x: W, y: 0), -cY), (Point2(x: W, y: D), Point2(x: 0, y: D), cY),
            (Point2(x: 0, y: D), Point2(x: 0, y: 0), -sY), (Point2(x: W, y: 0), Point2(x: W, y: D), sY),
        ]
        let rh = IsoProjection.roomHeight
        for (a, b, facing) in walls where facing < 0 {
            let p = poly([v.point(a), v.point(b), v.point(b, rh), v.point(a, rh)])
            ctx.fill(p, with: .color(Palette.text.opacity(0.03)))
            ctx.stroke(p, with: .color(Palette.text.opacity(0.5)), style: thin)
        }

        // Dimensions along the two near edges, in millimetres.
        let ny = cY > 0 ? D : 0, nx = sY > 0 ? W : 0, oy = cY > 0 ? 0.6 : -0.6, ox = sY > 0 ? 0.6 : -0.6
        dimension(ctx, v.point(0, ny + oy), v.point(W, ny + oy), "\(Int(W * 1000)) mm")
        dimension(ctx, v.point(nx + ox, 0), v.point(nx + ox, D), "\(Int(D * 1000)) mm")

        // Far things first, so near ones sit on top.
        var items: [(Double, (GraphicsContext) -> Void)] = []
        let t = plot.talent, cam = plot.camera
        items.append((v.depth(t.x, t.y), { c in
            box(c, v, Point2(x: t.x, y: t.y), w: 0.4, d: 0.3, z: 0, h: 1.75, top: nil)
            PlanDrawing.label("TALENT", at: v.point(t, 1.75).applying(.init(translationX: 0, y: -12)), c)
        }))
        items.append((v.depth(cam.x, cam.y), { c in
            let ta = cam.bearing(to: t) * .pi / 180, ox = -sin(ta) * 0.9, oy = cos(ta) * 0.9
            var frame = Path()
            frame.move(to: v.point(cam, 1.4)); frame.addLine(to: v.point(t.x - ox, t.y - oy, 1.2))
            frame.move(to: v.point(cam, 1.4)); frame.addLine(to: v.point(t.x + ox, t.y + oy, 1.2))
            c.stroke(frame, with: .color(quiet), style: StrokeStyle(lineWidth: 0.6, dash: [4, 3]))
            var legs = Path()
            for (dx, dy) in [(-0.35, 0.25), (0.35, 0.25), (0.0, -0.35)] {
                legs.move(to: v.point(cam, 1.25)); legs.addLine(to: v.point(cam.x + dx, cam.y + dy))
            }
            c.stroke(legs, with: .color(line), style: thin)
            box(c, v, cam, w: 0.35, d: 0.35, z: 1.25, h: 0.3, top: nil)
            PlanDrawing.label("CAMERA", at: v.point(cam, 1.55).applying(.init(translationX: 0, y: -12)), c)
        }))
        for (n, item) in plot.items.enumerated() {
            items.append((v.depth(item.x, item.y) - 0.01, { c in drawLamp(c, v, item, number: n + 1) }))
        }
        for (_, paint) in items.sorted(by: { $0.0 < $1.0 }) { paint(ctx) }

        // The handles that grow the set.
        for p in !showHandles ? [] : [v.point(W + 0.45, D / 2), v.point(W / 2, D + 0.45)] {
            let r: CGFloat = 11
            let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            ctx.fill(dot, with: .color(Palette.gel))
            ctx.stroke(dot, with: .color(Palette.p0), lineWidth: 1.5)
        }
    }

    private func drawLamp(_ c: GraphicsContext, _ v: IsoProjection, _ item: PlacedLamp, number: Int) {
        guard let lamp = item.lamp else { return }
        let line = Palette.text.opacity(0.9), on = plot.isOn(item), z = Self.height(item)
        let thin = StrokeStyle(lineWidth: 1)
        let head = v.point(item.position, z)
        let a = item.angle * .pi / 180
        if lamp.isGrip {
            // A standing frame, its face square to where it points.
            let face = a - .pi / 2, px = -sin(face) * lamp.width / 2, py = cos(face) * lamp.width / 2
            let f = poly([v.point(item.x - px, item.y - py, 0.3), v.point(item.x + px, item.y + py, 0.3),
                          v.point(item.x + px, item.y + py, 2.5), v.point(item.x - px, item.y - py, 2.5)])
            c.fill(f, with: .color(Palette.text.opacity(lamp.kind == .flag ? 0.25 : 0.08)))
            c.stroke(f, with: .color(line), style: lamp.kind == .diff ? StrokeStyle(lineWidth: 1, dash: [3, 2]) : thin)
        } else {
            if on {
                var beam = Path()
                beam.move(to: head); beam.addLine(to: v.point(plot.talent, 1.5))
                c.stroke(beam, with: .color(Palette.gel.opacity(0.7)), style: StrokeStyle(lineWidth: 0.8, dash: [5, 4]))
            }
            var stand = Path()
            stand.move(to: head); stand.addLine(to: v.point(item.position))
            for k in [0.0, 2.1, 4.2] {
                stand.move(to: v.point(item.position)); stand.addLine(to: v.point(item.x + 0.3 * cos(k), item.y + 0.3 * sin(k)))
            }
            c.stroke(stand, with: .color(line), style: thin)
            box(c, v, item.position, w: 0.46, d: 0.46, z: z - 0.15, h: 0.34, top: on ? Palette.text : nil)
            if on {
                let r: CGFloat = 3.5
                c.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2)), with: .color(Palette.gel))
            }
            modifier(c, v, item, z: z, a: a)
        }
        if item.id == selected {
            let r: CGFloat = 20
            c.stroke(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2)),
                     with: .color(Palette.gel), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        // Call-out: number and role, then head, modifier and height.
        let right = head.x > v.centre.x
        let tag = CGPoint(x: head.x + (right ? 26 : -26), y: head.y - 18)
        var leader = Path()
        leader.move(to: head); leader.addLine(to: tag)
        c.stroke(leader, with: .color(Palette.quiet), style: StrokeStyle(lineWidth: 0.6))
        var detail = lamp.shortName.lowercased()
        if !lamp.isGrip, item.modifier != "None", item.modifier != lamp.modifiers.first || lamp.kind != .fresnel {
            detail += ", " + item.modifier.lowercased()
        }
        if !lamp.isGrip { detail += String(format: ", %.1f m", z) }
        if !on && lamp.isLight { detail += ", off" }
        let anchor: UnitPoint = right ? .leading : .trailing
        c.draw(Text(String(format: "%02d ", number) + item.title.uppercased()).font(Fonts.mono(10, .medium)).foregroundStyle(Palette.text),
               at: CGPoint(x: tag.x + (right ? 4 : -4), y: tag.y - 6), anchor: anchor)
        c.draw(Text(detail).font(Fonts.mono(9, .regular)).foregroundStyle(Palette.quiet),
               at: CGPoint(x: tag.x + (right ? 4 : -4), y: tag.y + 6), anchor: anchor)
    }

    /// The modifier as a face square to the beam, out in front of the head.
    private func modifier(_ c: GraphicsContext, _ v: IsoProjection, _ item: PlacedLamp, z: Double, a: Double) {
        let ca = cos(a), sa = sin(a), px = -sa, py = ca
        func at(_ d: Double, _ s: Double, _ h: Double) -> CGPoint { v.point(item.x + ca * d + px * s, item.y + sa * d + py * s, z + h) }
        let line = Palette.text.opacity(0.85)
        switch item.modifier {
        case "Lantern", "Shade":
            let p = at(0.35, 0, 0), r = 0.32 * v.scale
            let ball = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            c.fill(ball, with: .color(Palette.p0.opacity(0.9)))
            c.stroke(ball, with: .color(line), lineWidth: 1)
        case "Softbox", "Chimera, medium", "Dome M":
            let d = 0.75, s = 0.45
            var ribs = Path()
            for (u, w) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] {
                ribs.move(to: at(0.2, u * 0.17, w * 0.17)); ribs.addLine(to: at(d, u * s, w * s))
            }
            c.stroke(ribs, with: .color(line), lineWidth: 0.8)
            let face = poly([at(d, -s, -s), at(d, s, -s), at(d, s, s), at(d, -s, s)])
            c.fill(face, with: .color(Palette.p0.opacity(0.92)))
            c.stroke(face, with: .color(line), lineWidth: 1)
        case "Snapgrid 40°", "Honeycrate", "8x8 full grid":
            let d = 0.32, s = 0.3
            var g = poly([at(d, -s, -s), at(d, s, -s), at(d, s, s), at(d, -s, s)])
            for k in 1..<4 {
                let t = -s + 2 * s * Double(k) / 4
                g.move(to: at(d, t, -s)); g.addLine(to: at(d, t, s))
                g.move(to: at(d, -s, t)); g.addLine(to: at(d, s, t))
            }
            c.stroke(g, with: .color(line), lineWidth: 0.7)
        case "Fresnel lens", "Snoot":
            let p = at(0.3, 0, 0), r = 0.12 * v.scale
            c.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(line), lineWidth: 1.2)
        default:
            break
        }
    }

    /// A box from its floor centre, with only the faces that turn towards you, and a solid top when it's lit.
    private func box(_ c: GraphicsContext, _ v: IsoProjection, _ at: Point2, w: Double, d: Double, z: Double, h: Double, top: Color?) {
        let x0 = at.x - w / 2, x1 = at.x + w / 2, y0 = at.y - d / 2, y1 = at.y + d / 2, z1 = z + h
        let sY = sin(v.yaw), cY = cos(v.yaw)
        let sides: [((Double, Double), (Double, Double), Double)] = [
            ((x0, y1), (x1, y1), cY), ((x1, y0), (x0, y0), -cY), ((x1, y1), (x1, y0), sY), ((x0, y0), (x0, y1), -sY),
        ]
        for (a, b, facing) in sides where facing > 0 {
            let f = poly([v.point(a.0, a.1, z), v.point(b.0, b.1, z), v.point(b.0, b.1, z1), v.point(a.0, a.1, z1)])
            c.fill(f, with: .color(Palette.p0))
            c.stroke(f, with: .color(Palette.text.opacity(0.9)), lineWidth: 1)
        }
        let lid = poly([v.point(x0, y0, z1), v.point(x1, y0, z1), v.point(x1, y1, z1), v.point(x0, y1, z1)])
        c.fill(lid, with: .color(top ?? Palette.p0))
        c.stroke(lid, with: .color(Palette.text.opacity(0.9)), lineWidth: 1)
    }

    private func dimension(_ c: GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ text: String) {
        var p = Path()
        p.move(to: a); p.addLine(to: b)
        for q in [a, b] { p.move(to: CGPoint(x: q.x - 4, y: q.y + 3)); p.addLine(to: CGPoint(x: q.x + 4, y: q.y - 3)) }
        c.stroke(p, with: .color(Palette.quiet), lineWidth: 0.7)
        var g = c
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        var angle = atan2(b.y - a.y, b.x - a.x)
        if abs(angle) > .pi / 2 { angle += .pi }
        g.translateBy(x: mid.x, y: mid.y)
        g.rotate(by: .radians(angle))
        g.draw(Text(text).font(Fonts.mono(10, .regular)).foregroundStyle(Palette.quiet), at: CGPoint(x: 0, y: 10))
    }

    private func poly(_ pts: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(pts)
        p.closeSubpath()
        return p
    }

    // MARK: Gestures

    private func hit(_ s: CGPoint, _ v: IsoProjection) -> Target {
        func near(_ p: CGPoint) -> CGFloat { hypot(p.x - s.x, p.y - s.y) }
        let reach: CGFloat = 34
        let W = plot.roomWidth, D = plot.roomDepth
        if near(v.point(W + 0.45, D / 2)) < 22 { return .wall(true) }
        if near(v.point(W / 2, D + 0.45)) < 22 { return .wall(false) }
        var best: (Target, CGFloat)?
        func consider(_ t: Target, _ d: CGFloat) { if d < reach, d < (best?.1 ?? .infinity) { best = (t, d) } }
        for item in plot.items { consider(.lamp(item.id), near(v.point(item.position, Self.height(item)))) }
        for z in [0.0, 1.75] { consider(.talent(z), near(v.point(plot.talent, z))) }
        for z in [0.0, 1.4] { consider(.camera(z), near(v.point(plot.camera, z))) }
        return best?.0 ?? .turn(yaw, pitch)
    }

    private func inRoom(_ p: Point2) -> Point2 {
        let g = { (v: Double) in (v * 4).rounded() / 4 }
        return Point2(x: min(plot.roomWidth - 0.3, max(0.3, g(p.x))), y: min(plot.roomDepth - 0.3, max(0.3, g(p.y))))
    }

    private func gesture(_ v: IsoProjection) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if drag == nil {
                    let target = hit(value.startLocation, v)
                    var state = DragState(target: target)
                    if case .wall = target { state.locked = v }
                    drag = state
                    if case .lamp(let id) = target { holdToRemove(id) }
                }
                guard var d = drag, !d.held else { return }
                if !d.moved, hypot(value.translation.width, value.translation.height) > 4 { d.moved = true; hold?.cancel() }
                drag = d
                guard d.moved else { return }
                let view = d.locked ?? v
                switch d.target {
                case .lamp(let id):
                    guard let i = plot.items.firstIndex(where: { $0.id == id }) else { return }
                    selected = id
                    let p = inRoom(view.floor(at: value.location, z: Self.height(plot.items[i])))
                    plot.items[i].x = p.x
                    plot.items[i].y = p.y
                case .talent(let z):
                    plot.talent = inRoom(view.floor(at: value.location, z: z))
                case .camera(let z):
                    plot.camera = inRoom(view.floor(at: value.location, z: z))
                case .wall(let across):
                    // Never smaller than what's in the room.
                    let p = view.floor(at: value.location)
                    let things = plot.items.map(\.position) + [plot.talent, plot.camera]
                    if across {
                        let least = max(2.5, (things.map(\.x).max() ?? 0) + 0.4)
                        plot.roomWidth = (min(30, max(least, p.x - 0.45)) * 10).rounded() / 10
                    } else {
                        let least = max(2.5, (things.map(\.y).max() ?? 0) + 0.4)
                        plot.roomDepth = (min(30, max(least, p.y - 0.45)) * 10).rounded() / 10
                    }
                case .turn(let y0, let p0):
                    yaw = y0 + value.translation.width * 0.01
                    pitch = min(1.45, max(0.2, p0 + value.translation.height * 0.006))
                case .none:
                    break
                }
            }
            .onEnded { value in
                hold?.cancel()
                if let d = drag, !d.moved, !d.held {
                    switch d.target {
                    case .lamp(let id):
                        if selected == id { cardOpen.wrappedValue.toggle() } else { selected = id; cardOpen.wrappedValue = false }
                    case .turn, .none:
                        if let armed { drop(armed.id, v.floor(at: value.startLocation)) } else { selected = nil }
                    default:
                        selected = nil
                    }
                }
                drag = nil
            }
    }

    /// Press and hold a lamp without moving it to take it off the plan. Undo brings it back.
    private func holdToRemove(_ id: PlacedLamp.ID) {
        hold?.cancel()
        hold = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled, var d = drag, !d.moved, let i = plot.items.firstIndex(where: { $0.id == id }) else { return }
            let name = plot.items[i].lamp?.shortName ?? "lamp"
            d.held = true
            drag = d
            if selected == id { selected = nil }
            plot.items.remove(at: i)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            say("Removed \(name) · Undo bottom left")
        }
    }
}
