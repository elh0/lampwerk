import SwiftUI

// The rig drawing: ink on paper, the way a DP's prep deck draws a set. An axonometric line drawing of the room,
// lamps lettered by group with call-outs out to the side, inked when on and ghosted when off, next to a rig table.
// A second page, light in sections, draws the room once per setup.

/// Lamps that share a name, a head and a modifier read as one group on the drawing, e.g. six Dynos as "A CYC".
struct RigGroup: Identifiable {
    let id: Int
    let letter: String
    let title: String
    var items: [PlacedLamp]

    var lamp: Lamp? { items.first?.lamp }

    /// "6 × Dyno, softbox, ½ CTB"
    var what: String {
        guard let first = items.first, let lamp else { return "?" }
        var s = (items.count > 1 ? "\(items.count) × " : "") + lamp.fullName
        if first.modifier != "None" { s += ", " + first.modifier.lowercased() }
        if first.gel != "None" { s += ", " + first.gel }
        return s
    }

    /// Shorter, for the call-out under the letter.
    var short: String {
        guard let first = items.first, let lamp else { return "" }
        var s = (items.count > 1 ? "\(items.count) × " : "") + lamp.shortName
        if !lamp.isGrip, first.modifier != "None", first.modifier != "Barn doors" { s += ", " + first.modifier.lowercased() }
        if first.gel != "None" { s += ", " + first.gel }
        return s
    }

    func inked(in shot: Shot) -> Bool { items.contains { RigGroups.inked($0, in: shot) } }
}

enum RigGroups {
    static func make(_ plot: Plot) -> [RigGroup] {
        var groups: [RigGroup] = []
        for item in plot.items where item.lamp != nil {
            let key = item.title.lowercased()
            if let i = groups.firstIndex(where: {
                $0.title.lowercased() == key && $0.items[0].lampID == item.lampID && $0.items[0].modifier == item.modifier
            }) {
                groups[i].items.append(item)
            } else {
                let n = groups.count
                let letter = n < 26 ? String(Character(UnicodeScalar(UInt8(65 + n)))) : "Z\(n - 24)"
                groups.append(RigGroup(id: n, letter: letter, title: item.title, items: [item]))
            }
        }
        return groups
    }

    /// Drawn in ink in this setup. Frames and flags count too, unless they're struck for it.
    static func inked(_ item: PlacedLamp, in shot: Shot) -> Bool {
        item.lamp != nil && !item.offIn.contains(shot)
    }

    /// "Wide, Close" or "Every setup".
    static func usedFor(_ group: RigGroup) -> String {
        let shots = Shot.allCases.filter { group.inked(in: $0) }
        if shots.count == Shot.allCases.count { return "Every setup" }
        if shots.isEmpty { return "Standing by" }
        return shots.map(\.title).joined(separator: ", ")
    }

    /// One entry per different look: setups that switch on the same groups share a drawing.
    static func sections(_ plot: Plot, _ groups: [RigGroup]) -> [(shots: [Shot], letters: [String])] {
        var out: [(shots: [Shot], letters: [String])] = []
        for shot in Shot.allCases {
            let letters = groups.filter { $0.inked(in: shot) }.map(\.letter)
            if let i = out.firstIndex(where: { $0.letters == letters }) {
                out[i].shots.append(shot)
            } else {
                out.append((shots: [shot], letters: letters))
            }
        }
        return out
    }

    /// "6 000", the way drawings write millimetres.
    static func mm(_ metres: Double) -> String {
        let n = Int((metres * 1000).rounded())
        let s = String(n)
        guard s.count > 3 else { return s }
        return String(s.dropLast(3)) + " " + String(s.suffix(3))
    }
}

/// Draws the room in ink. `shot` nil draws everything inked (the whole rig).
struct AxoDrawing {
    let plot: Plot
    let groups: [RigGroup]
    var yaw = IsoProjection.defaultYaw
    var pitch = IsoProjection.defaultPitch
    var shot: Shot? = nil
    /// Lamps and frames left out: the clean set drawing.
    var setOnly = false
    /// Call-outs to the side; off for the small drawings in light in sections.
    var callouts = true
    var dimensions = true

    private let ink = Palette.ink
    private let paper = Palette.paper

    /// Width kept clear each side for the call-outs.
    static let column: CGFloat = 84

    func projection(in size: CGSize) -> IsoProjection {
        let W = plot.roomWidth, D = plot.roomDepth, rh = IsoProjection.roomHeight
        let pivot = Point2(x: W / 2, y: D / 2)
        let unit = IsoProjection(yaw: yaw, pitch: pitch, scale: 1, centre: .zero, pivot: pivot)
        var pts: [CGPoint] = []
        for (x, y) in [(0.0, 0.0), (W, 0), (W, D), (0, D)] {
            pts.append(unit.point(x, y, 0))
            pts.append(unit.point(x, y, rh))
        }
        // Lamps can stand outside the room (a key through a window), so they count too.
        if !setOnly {
            for item in plot.items {
                pts.append(unit.point(item.position, IsoCanvas.height(item)))
                pts.append(unit.point(item.position, 0))
            }
        }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let side: CGFloat = callouts ? Self.column : 4
        let pad: CGFloat = dimensions ? 26 : 6
        let w = max(1, xs.max()! - xs.min()!), h = max(1, ys.max()! - ys.min()!)
        let scale = min((size.width - side * 2 - pad * 2) / w, (size.height - pad * 2 - 20) / h)
        let mid = CGPoint(x: (xs.max()! + xs.min()!) / 2, y: (ys.max()! + ys.min()!) / 2)
        return IsoProjection(yaw: yaw, pitch: pitch, scale: scale,
                             centre: CGPoint(x: size.width / 2 - mid.x * scale, y: size.height / 2 - mid.y * scale + 4), pivot: pivot)
    }

    func draw(_ ctx: GraphicsContext, size: CGSize) {
        let v = projection(in: size)
        let W = plot.roomWidth, D = plot.roomDepth, rh = IsoProjection.roomHeight
        let sY = sin(v.yaw), cY = cos(v.yaw)
        let fine: CGFloat = callouts ? 0.6 : 0.45

        // Floor: a metre grid and the outline.
        var grid = Path()
        for x in stride(from: 1.0, to: W, by: 1) { grid.move(to: v.point(x, 0)); grid.addLine(to: v.point(x, D)) }
        for y in stride(from: 1.0, to: D, by: 1) { grid.move(to: v.point(0, y)); grid.addLine(to: v.point(W, y)) }
        ctx.stroke(grid, with: .color(ink.opacity(0.06)), lineWidth: 0.3)
        ctx.stroke(poly([v.point(0, 0), v.point(W, 0), v.point(W, D), v.point(0, D)]), with: .color(ink.opacity(0.85)), lineWidth: fine * 1.5)

        // The two far walls stand; the near ones stay open.
        let walls: [(Point2, Point2, Double)] = [
            (Point2(x: 0, y: 0), Point2(x: W, y: 0), -cY), (Point2(x: W, y: D), Point2(x: 0, y: D), cY),
            (Point2(x: 0, y: D), Point2(x: 0, y: 0), -sY), (Point2(x: W, y: 0), Point2(x: W, y: D), sY),
        ]
        for (a, b, facing) in walls where facing < 0 {
            ctx.stroke(poly([v.point(a), v.point(b), v.point(b, rh), v.point(a, rh)]), with: .color(ink.opacity(0.5)), lineWidth: fine * 0.8)
            // A skirting line and a faint panel rhythm give the walls some grain.
            var grain = Path()
            grain.move(to: v.point(a, 0.12)); grain.addLine(to: v.point(b, 0.12))
            let run = a.distance(to: b), steps = max(1, Int(run / 1.2))
            for k in 1..<steps {
                let f = Double(k) / Double(steps)
                let q = Point2(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
                grain.move(to: v.point(q, 0.12)); grain.addLine(to: v.point(q, rh))
            }
            ctx.stroke(grain, with: .color(ink.opacity(0.12)), lineWidth: 0.3)
        }

        // Where each lit head lands: a grey pool on the floor, drawn under everything.
        // One flat tone for all of them (overlaps don't stack darker), kept inside the floor.
        if !setOnly {
            var pools = Path()
            for item in plot.items where item.lamp?.isLight == true {
                let on = shot.map { RigGroups.inked(item, in: $0) } ?? true
                if on, let ring = pool(item) { pools.addPath(poly(ring.map { v.point($0) })) }
            }
            var floor = ctx
            floor.clip(to: poly([v.point(0, 0), v.point(W, 0), v.point(W, D), v.point(0, D)]))
            floor.fill(pools, with: .color(ink.opacity(0.06)), style: FillStyle(eoFill: false))
            floor.stroke(pools, with: .color(ink.opacity(0.28)), lineWidth: 0.35)
        }

        if dimensions {
            let ny = cY > 0 ? D : 0, nx = sY > 0 ? W : 0, oy = cY > 0 ? 0.7 : -0.7, ox = sY > 0 ? 0.7 : -0.7
            dimension(ctx, v.point(0, ny + oy), v.point(W, ny + oy), RigGroups.mm(W))
            dimension(ctx, v.point(nx + ox, 0), v.point(nx + ox, D), RigGroups.mm(D))
        }

        // Far things first, so near ones sit on top.
        var items: [(Double, (GraphicsContext) -> Void)] = []
        let t = plot.talent, cam = plot.camera
        items.append((v.depth(t.x, t.y), { c in box(c, v, t, w: 0.4, d: 0.3, z: 0, h: 1.75, top: nil, opacity: 1) }))
        items.append((v.depth(cam.x, cam.y), { c in camera(c, v) }))
        if !setOnly {
            for item in plot.items where item.lamp != nil {
                let on = shot.map { RigGroups.inked(item, in: $0) } ?? true
                items.append((v.depth(item.x, item.y) - 0.01, { c in lamp(c, v, item, on: on) }))
            }
        }
        for (_, paint) in items.sorted(by: { $0.0 < $1.0 }) { paint(ctx) }

        if callouts { labels(ctx, v, size: size) }
    }

    // MARK: Pieces

    private func camera(_ c: GraphicsContext, _ v: IsoProjection) {
        let cam = plot.camera
        var legs = Path()
        for (dx, dy) in [(-0.35, 0.25), (0.35, 0.25), (0.0, -0.35)] {
            legs.move(to: v.point(cam, 1.25)); legs.addLine(to: v.point(cam.x + dx, cam.y + dy))
        }
        c.stroke(legs, with: .color(ink), lineWidth: 0.7)
        box(c, v, cam, w: 0.35, d: 0.35, z: 1.25, h: 0.3, top: nil, opacity: 1)
    }

    private func lamp(_ c: GraphicsContext, _ v: IsoProjection, _ item: PlacedLamp, on: Bool) {
        guard let lamp = item.lamp else { return }
        let o = on ? 1.0 : 0.22, line = ink.opacity(o), z = IsoCanvas.height(item)
        let a = item.angle * .pi / 180
        if lamp.isGrip {
            let face = a - .pi / 2, px = -sin(face) * lamp.width / 2, py = cos(face) * lamp.width / 2
            let bl = v.point(item.x - px, item.y - py, 0.3), br = v.point(item.x + px, item.y + py, 0.3)
            let tr = v.point(item.x + px, item.y + py, 2.5), tl = v.point(item.x - px, item.y - py, 2.5)
            let f = poly([bl, br, tr, tl])
            switch lamp.kind {
            case .flag: c.fill(f, with: .color(ink.opacity(on ? 0.85 : 0.08)))
            default: c.fill(f, with: .color(paper))
            }
            if lamp.kind == .diff {
                // Diffusion reads as fine hatching, like a silk.
                var hatch = Path()
                let n = max(6, Int(lamp.width * 5))
                for k in 1..<n {
                    let s = CGFloat(k) / CGFloat(n)
                    hatch.move(to: CGPoint(x: bl.x + (br.x - bl.x) * s, y: bl.y + (br.y - bl.y) * s))
                    hatch.addLine(to: CGPoint(x: tl.x + (tr.x - tl.x) * s, y: tl.y + (tr.y - tl.y) * s))
                }
                c.stroke(hatch, with: .color(ink.opacity(0.35 * o)), lineWidth: 0.35)
            }
            c.stroke(f, with: .color(line), lineWidth: 0.8)
            // Stand legs under the frame.
            var legs = Path()
            for q in [Point2(x: item.x - px, y: item.y - py), Point2(x: item.x + px, y: item.y + py)] {
                legs.move(to: v.point(q, 0.3)); legs.addLine(to: v.point(q))
            }
            c.stroke(legs, with: .color(line), lineWidth: 0.6)
            return
        }
        let head = v.point(item.position, z)
        if on {
            // The beam's two edges, down to the edges of its pool.
            var beam = Path()
            if let ring = pool(item), ring.count >= 32 {
                for q in [ring[8], ring[24]] { beam.move(to: head); beam.addLine(to: v.point(q)) }
            } else {
                beam.move(to: head); beam.addLine(to: v.point(plot.talent, 1.5))
            }
            c.stroke(beam, with: .color(ink.opacity(0.55)), style: StrokeStyle(lineWidth: 0.4, dash: [2.5, 2]))
        }
        if z > 3.0 {
            // Rigged high: a dotted drop to the floor and a small mark where it lands, no stand.
            var drop = Path()
            drop.move(to: head); drop.addLine(to: v.point(item.position))
            c.stroke(drop, with: .color(ink.opacity(0.45 * o)), style: StrokeStyle(lineWidth: 0.4, dash: [1, 2]))
            var mark = Path()
            mark.move(to: v.point(item.x - 0.15, item.y)); mark.addLine(to: v.point(item.x + 0.15, item.y))
            mark.move(to: v.point(item.x, item.y - 0.15)); mark.addLine(to: v.point(item.x, item.y + 0.15))
            c.stroke(mark, with: .color(ink.opacity(0.5 * o)), lineWidth: 0.4)
        } else {
            var stand = Path()
            stand.move(to: head); stand.addLine(to: v.point(item.position))
            for k in [0.0, 2.1, 4.2] {
                stand.move(to: v.point(item.position)); stand.addLine(to: v.point(item.x + 0.3 * cos(k), item.y + 0.3 * sin(k)))
            }
            c.stroke(stand, with: .color(line), lineWidth: 0.7)
        }
        box(c, v, item.position, w: 0.46, d: 0.46, z: z - 0.15, h: 0.34, top: on ? ink : nil, opacity: o)
        modifier(c, v, item, z: z, a: a, opacity: o)
    }

    /// The pool a head throws on the floor, as 32 points round its edge (index 8 and 24 are the two sides).
    /// It lands on the talent's mark when the head points their way, otherwise a little way out along its aim.
    /// Practicals throw a small round pool under themselves.
    private func pool(_ item: PlacedLamp) -> [Point2]? {
        guard let lamp = item.lamp, lamp.isLight else { return nil }
        let z = IsoCanvas.height(item)
        let spread = LightMath.spread(item, in: plot)
        let centre: Point2, rx: Double, ry: Double, dir: Double
        if spread >= 300 {
            centre = item.position; rx = 0.6; ry = 0.6; dir = 0
        } else {
            let toTalent = item.position.bearing(to: plot.talent)
            let aimed = LightMath.angleBetween(toTalent, item.angle) <= 25
            let a = item.angle * .pi / 180
            let reach = max(1.2, z * 1.1)
            centre = aimed ? plot.talent : Point2(x: item.x + cos(a) * reach, y: item.y + sin(a) * reach)
            dir = aimed ? toTalent * .pi / 180 : a
            let flat = item.position.distance(to: centre), slant = (flat * flat + z * z).squareRoot()
            let half = min(80, spread / 2) * .pi / 180
            ry = min(1.3, max(0.35, slant * tan(half) * 0.6))
            // Long along the throw when the head is low, near round when it's overhead.
            let grazing = max(0.45, z / max(0.1, slant))
            rx = min(1.9, ry / grazing)
        }
        let c = cos(dir), s = sin(dir)
        return (0..<32).map { k in
            let t = Double(k) / 32 * 2 * .pi
            let u = cos(t) * rx, w = sin(t) * ry
            return Point2(x: centre.x + u * c - w * s, y: centre.y + u * s + w * c)
        }
    }

    private func modifier(_ c: GraphicsContext, _ v: IsoProjection, _ item: PlacedLamp, z: Double, a: Double, opacity o: Double) {
        let ca = cos(a), sa = sin(a), px = -sa, py = ca
        func at(_ d: Double, _ s: Double, _ h: Double) -> CGPoint { v.point(item.x + ca * d + px * s, item.y + sa * d + py * s, z + h) }
        let line = ink.opacity(o)
        switch item.modifier {
        case "Lantern", "Shade":
            let p = at(0.35, 0, 0), r = 0.32 * v.scale
            let ball = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            c.fill(ball, with: .color(paper))
            c.stroke(ball, with: .color(line), lineWidth: 0.7)
        case "Softbox", "Chimera, medium", "Dome M":
            let d = 0.75, s = 0.45
            var ribs = Path()
            for (u, w) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] {
                ribs.move(to: at(0.2, u * 0.17, w * 0.17)); ribs.addLine(to: at(d, u * s, w * s))
            }
            c.stroke(ribs, with: .color(line), lineWidth: 0.5)
            let face = poly([at(d, -s, -s), at(d, s, -s), at(d, s, s), at(d, -s, s)])
            c.fill(face, with: .color(paper))
            c.stroke(face, with: .color(line), lineWidth: 0.7)
        case "Snapgrid 40°", "Honeycrate", "8x8 full grid":
            let d = 0.32, s = 0.3
            var g = poly([at(d, -s, -s), at(d, s, -s), at(d, s, s), at(d, -s, s)])
            for k in 1..<4 {
                let t = -s + 2 * s * Double(k) / 4
                g.move(to: at(d, t, -s)); g.addLine(to: at(d, t, s))
                g.move(to: at(d, -s, t)); g.addLine(to: at(d, s, t))
            }
            c.stroke(g, with: .color(line), lineWidth: 0.45)
        default:
            break
        }
    }

    /// A box from its floor centre, faces turned towards you, the lid inked when the head is on.
    private func box(_ c: GraphicsContext, _ v: IsoProjection, _ at: Point2, w: Double, d: Double, z: Double, h: Double, top: Color?, opacity o: Double) {
        let x0 = at.x - w / 2, x1 = at.x + w / 2, y0 = at.y - d / 2, y1 = at.y + d / 2, z1 = z + h
        let sY = sin(v.yaw), cY = cos(v.yaw), line = ink.opacity(o)
        let sides: [((Double, Double), (Double, Double), Double)] = [
            ((x0, y1), (x1, y1), cY), ((x1, y0), (x0, y0), -cY), ((x1, y1), (x1, y0), sY), ((x0, y0), (x0, y1), -sY),
        ]
        for (a, b, facing) in sides where facing > 0 {
            let f = poly([v.point(a.0, a.1, z), v.point(b.0, b.1, z), v.point(b.0, b.1, z1), v.point(a.0, a.1, z1)])
            c.fill(f, with: .color(paper))
            c.stroke(f, with: .color(line), lineWidth: 0.85)
        }
        let lid = poly([v.point(x0, y0, z1), v.point(x1, y0, z1), v.point(x1, y1, z1), v.point(x0, y1, z1)])
        c.fill(lid, with: .color(top ?? paper))
        c.stroke(lid, with: .color(line), lineWidth: 0.85)
    }

    private func dimension(_ c: GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ text: String) {
        var p = Path()
        p.move(to: a); p.addLine(to: b)
        for q in [a, b] { p.move(to: CGPoint(x: q.x - 3, y: q.y + 2.5)); p.addLine(to: CGPoint(x: q.x + 3, y: q.y - 2.5)) }
        c.stroke(p, with: .color(ink.opacity(0.45)), lineWidth: 0.5)
        var g = c
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        var angle = atan2(b.y - a.y, b.x - a.x)
        if abs(angle) > .pi / 2 { angle += .pi }
        g.translateBy(x: mid.x, y: mid.y)
        g.rotate(by: .radians(angle))
        g.draw(Text(text).font(Fonts.mono(6.5, .regular)).foregroundStyle(ink.opacity(0.5)), at: CGPoint(x: 0, y: 8))
    }

    // MARK: Call-outs

    private struct Callout {
        var anchor: CGPoint
        var title: String
        var detail: String
        var y: CGFloat
    }

    /// Letters and names out to either side of the room, leaders running in to what they name.
    private func labels(_ ctx: GraphicsContext, _ v: IsoProjection, size: CGSize) {
        var all: [Callout] = []
        if !setOnly {
            for g in groups {
                guard let first = g.items.first, let lamp = g.lamp else { continue }
                let p = lamp.isGrip ? v.point(first.position, 2.5) : v.point(first.position, IsoCanvas.height(first) + 0.2)
                all.append(Callout(anchor: p, title: "\(g.letter) \(g.title.uppercased())", detail: g.short, y: p.y))
            }
        }
        let cam = v.point(plot.camera, 1.55), tal = v.point(plot.talent, 1.75)
        all.append(Callout(anchor: cam, title: "CAMERA", detail: "", y: cam.y))
        all.append(Callout(anchor: tal, title: "TALENT", detail: "", y: tal.y))

        let mid = v.point(plot.roomWidth / 2, plot.roomDepth / 2).x
        let leftX = Self.column - 6, rightX = size.width - Self.column + 6
        for left in [true, false] {
            var side = all.filter { ($0.anchor.x < mid) == left }.sorted { $0.y < $1.y }
            // Push apart so no two labels touch.
            let gap: CGFloat = 22
            for i in side.indices {
                side[i].y = max(side[i].y, 14)
                if i > 0 { side[i].y = max(side[i].y, side[i - 1].y + gap) }
            }
            if let last = side.last, last.y > size.height - 14 {
                let shift = last.y - (size.height - 14)
                for i in side.indices { side[i].y -= shift }
                for i in side.indices.reversed() where i < side.count - 1 { side[i].y = min(side[i].y, side[i + 1].y - gap) }
            }
            for c in side {
                let x = left ? leftX : rightX
                var leader = Path()
                leader.move(to: c.anchor)
                leader.addLine(to: CGPoint(x: x + (left ? 12 : -12), y: c.y))
                leader.addLine(to: CGPoint(x: x + (left ? 3 : -3), y: c.y))
                ctx.stroke(leader, with: .color(ink.opacity(0.55)), lineWidth: 0.45)
                let anchor: UnitPoint = left ? .trailing : .leading
                ctx.draw(Text(c.title).font(Fonts.mono(7, .medium)).foregroundStyle(ink), at: CGPoint(x: x, y: c.y), anchor: anchor)
                if !c.detail.isEmpty {
                    ctx.draw(Text(c.detail).font(Fonts.mono(6, .regular)).foregroundStyle(ink.opacity(0.5)),
                             at: CGPoint(x: x, y: c.y + 9), anchor: anchor)
                }
            }
        }
    }

    private func poly(_ pts: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(pts)
        p.closeSubpath()
        return p
    }
}

// MARK: Pages

/// A4 landscape header shared by both pages: what the page is, then the plot.
private struct RigHeader: View {
    let title: String
    let plot: Plot
    let line: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased()).font(Fonts.mono(10, .medium)).foregroundStyle(Palette.ink)
                Spacer()
                Text(plot.name.uppercased()).font(Fonts.mono(10, .regular)).foregroundStyle(Palette.ink.opacity(0.45))
            }
            .padding(.bottom, 10)
            Rectangle().fill(Palette.ink.opacity(0.15)).frame(height: 0.5)
            Text(line).font(Fonts.mono(9, .regular)).foregroundStyle(Palette.ink).padding(.top, 14)
        }
    }
}

private struct RigFooter: View {
    let plot: Plot
    var body: some View {
        HStack(alignment: .bottom) {
            Text("Made with Lampwerk · " + plot.updated.formatted(date: .abbreviated, time: .omitted))
                .font(Fonts.mono(7, .regular)).foregroundStyle(Palette.ink.opacity(0.45))
            Spacer()
            Image("Mark").resizable().scaledToFit().frame(height: 16).foregroundStyle(Palette.ink)
        }
    }
}

/// Page one: the whole rig drawn, every lamp inked, with the rig table beside it.
struct RigPage: View {
    let plot: Plot
    let groups: [RigGroup]
    var yaw = IsoProjection.defaultYaw
    var pitch = IsoProjection.defaultPitch
    var setOnly = false
    /// More than one look, so page two follows.
    var hasSections = false

    private var line: String {
        let room = String(format: "Room %.1f × %.1f m.", plot.roomWidth, plot.roomDepth)
        if setOnly { return room + " The set, no lamps." }
        let lamps = plot.items.filter { $0.lamp != nil }.count
        let tail = hasSections ? "Every lamp drawn; the setups follow." : "Same lamps in every setup."
        return room + " \(lamps) \(lamps == 1 ? "lamp" : "lamps") in \(groups.count) \(groups.count == 1 ? "group" : "groups"). " + tail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RigHeader(title: setOnly ? "The set" : "The rig", plot: plot, line: line)
            HStack(alignment: .center, spacing: 16) {
                Canvas { ctx, size in
                    AxoDrawing(plot: plot, groups: groups, yaw: yaw, pitch: pitch, setOnly: setOnly).draw(ctx, size: size)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !setOnly {
                    table.frame(width: 262)
                }
            }
            .frame(maxHeight: .infinity)
            RigFooter(plot: plot)
        }
        .padding(.horizontal, 40).padding(.vertical, 34)
        .frame(width: 842, height: 595)
        .background(Palette.paper)
    }

    private var table: some View {
        VStack(spacing: 0) {
            row("Group", "What", "Used for", "Rigged", header: true)
            if groups.isEmpty {
                Text("No lamps yet.").font(Fonts.mono(8, .regular)).foregroundStyle(Palette.ink.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }
            ForEach(groups) { g in
                row("\(g.letter) \(g.title)", g.what, RigGroups.usedFor(g), rigged(g))
            }
        }
    }

    /// Heights and throw, from what's on the plan.
    private func rigged(_ g: RigGroup) -> String {
        guard let first = g.items.first, let lamp = g.lamp else { return "" }
        let throwM = first.position.distance(to: plot.talent)
        if lamp.isGrip { return String(format: "Stands\n%.1f\u{00A0}m off", throwM) }
        let h = IsoCanvas.height(first)
        return String(format: "%.1f\u{00A0}m\u{00A0}high\n%.1f\u{00A0}m\u{00A0}throw", h, throwM)
    }

    private func row(_ a: String, _ b: String, _ c: String, _ d: String, header: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(a).frame(width: 48, alignment: .leading)
            Text(b).frame(width: 86, alignment: .leading)
            Text(c).frame(width: 50, alignment: .leading)
            Text(d).frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .font(Fonts.mono(7, .regular))
        .foregroundStyle(header ? Palette.ink.opacity(0.45) : Palette.ink)
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Rectangle().fill(Palette.ink.opacity(0.2)).frame(height: 0.75) }
    }
}

/// Page two: one small drawing per look. Inked = on.
struct SectionsPage: View {
    let plot: Plot
    let groups: [RigGroup]
    var yaw = IsoProjection.defaultYaw
    var pitch = IsoProjection.defaultPitch

    var body: some View {
        let sections = RigGroups.sections(plot, groups)
        VStack(alignment: .leading, spacing: 0) {
            RigHeader(title: "Light in sections", plot: plot, line: "Inked = on.")
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 22) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 0) {
                        Canvas { ctx, size in
                            AxoDrawing(plot: plot, groups: groups, yaw: yaw, pitch: pitch, shot: s.shots[0],
                                       callouts: false, dimensions: false).draw(ctx, size: size)
                        }
                        .frame(height: 220)
                        Rectangle().fill(Palette.ink.opacity(0.15)).frame(height: 0.5).padding(.top, 10)
                        HStack(spacing: 14) {
                            Text(s.shots.map { $0.title.uppercased() }.joined(separator: ", "))
                            Text(s.letters.isEmpty ? "ALL OFF" : s.letters.joined(separator: " + "))
                        }
                        .font(Fonts.mono(8, .regular)).foregroundStyle(Palette.ink.opacity(0.5))
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
            RigFooter(plot: plot)
        }
        .padding(.horizontal, 40).padding(.vertical, 34)
        .frame(width: 842, height: 595)
        .background(Palette.paper)
    }
}
