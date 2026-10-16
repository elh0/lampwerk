import SwiftUI

/// Maps plot metres to view points.
struct PlanViewport {
    var scale: CGFloat
    var origin: CGPoint

    /// Fits the room plus a margin into a view, centred.
    static func fit(_ plot: Plot, in size: CGSize, margin: Double = 1.2, zoom: CGFloat = 1, pan: CGSize = .zero) -> PlanViewport {
        let w = plot.roomWidth + margin * 2, h = plot.roomDepth + margin * 2
        let s = min(size.width / w, size.height / h) * zoom
        let ox = (size.width - plot.roomWidth * s) / 2 + pan.width
        let oy = (size.height - plot.roomDepth * s) / 2 + pan.height
        return PlanViewport(scale: s, origin: CGPoint(x: ox, y: oy))
    }

    func point(_ p: Point2) -> CGPoint { CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale) }
    func point(x: Double, y: Double) -> CGPoint { point(Point2(x: x, y: y)) }
    func metres(_ p: CGPoint) -> Point2 { Point2(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale) }
}

/// Draws a plot top-down: grid, walls, beams, heads, camera and talent.
/// On is a gel dot and a gel beam, off is an outline with no beam, selected is a gel ring.
enum PlanDrawing {
    struct Options {
        var selected: PlacedLamp.ID?
        var showGrid = true
        var showLabels = true
        var lineWidth: CGFloat = 1
        /// Ink on paper for the gaffer sheet: no gel, beams in a faint grey.
        var paper = false
    }

    /// The few colours the plan is drawn in, for the dark screen or for paper.
    struct Ink {
        var bg = Palette.p0
        var line = Palette.text.opacity(0.9)
        var quiet = Palette.quiet
        var grid = Palette.text.opacity(0.05)
        var walls = Palette.text.opacity(0.5)
        var beam = Palette.gel.opacity(Palette.beamOpacity)
        var on = Palette.gel
        var selection = Palette.gel

        static let screen = Ink()
        static let paper = Ink(
            bg: Palette.paper, line: Palette.ink, quiet: Palette.ink.opacity(0.55), grid: Palette.ink.opacity(0.07),
            walls: Palette.ink.opacity(0.8), beam: Palette.ink.opacity(0.07), on: Palette.ink, selection: Palette.ink
        )
    }

    static func draw(_ plot: Plot, in ctx: GraphicsContext, viewport v: PlanViewport, options o: Options) {
        let ink: Ink = o.paper ? .paper : .screen
        let line = ink.line
        let stroke = StrokeStyle(lineWidth: o.lineWidth)

        if o.showGrid {
            var grid = Path()
            for x in stride(from: 1.0, to: plot.roomWidth, by: 1) {
                grid.move(to: v.point(x: x, y: 0)); grid.addLine(to: v.point(x: x, y: plot.roomDepth))
            }
            for y in stride(from: 1.0, to: plot.roomDepth, by: 1) {
                grid.move(to: v.point(x: 0, y: y)); grid.addLine(to: v.point(x: plot.roomWidth, y: y))
            }
            ctx.stroke(grid, with: .color(ink.grid), style: stroke)
        }

        // Beams under everything.
        for item in plot.items where plot.isOn(item) {
            guard let lamp = item.lamp else { continue }
            ctx.fill(beam(item, lamp, v), with: .color(ink.beam))
        }

        // Walls.
        let walls = Path(CGRect(origin: v.point(x: 0, y: 0), size: CGSize(width: plot.roomWidth * v.scale, height: plot.roomDepth * v.scale)))
        ctx.stroke(walls, with: .color(ink.walls), style: stroke)

        // Camera, pointing at the talent.
        drawCamera(plot, ctx, v, line, stroke, ink)

        // Talent.
        let t = v.point(plot.talent), tr = 0.2 * v.scale
        let head = Path(ellipseIn: CGRect(x: t.x - tr, y: t.y - tr, width: tr * 2, height: tr * 2))
        ctx.fill(head, with: .color(ink.bg))
        ctx.stroke(head, with: .color(line), style: stroke)
        if o.showLabels { label("TALENT", at: CGPoint(x: t.x, y: t.y + tr + 10), ctx, color: ink.quiet) }

        // Heads and frames.
        for item in plot.items {
            guard let lamp = item.lamp else { continue }
            drawHead(item, lamp, on: plot.isOn(item), selected: item.id == o.selected, ctx, v, line, stroke, ink)
        }

        if o.showLabels {
            for (n, item) in plot.items.enumerated() {
                // Behind the head, away from its beam and clear of its body.
                let reach = max(item.lamp?.width ?? 0.3, item.lamp?.depth ?? 0.3) / 2 + 0.35
                let a = (item.angle + 180) * .pi / 180
                let p = v.point(x: item.x + reach * cos(a), y: item.y + reach * sin(a))
                label(String(format: "%02d", n + 1) + " " + item.title.uppercased(), at: p, ctx, color: ink.quiet)
            }
        }
    }

    static func beam(_ item: PlacedLamp, _ lamp: Lamp, _ v: PlanViewport) -> Path {
        let c = v.point(item.position)
        if lamp.beam >= 300 {
            let r = LightMath.glowRadius(lamp, output: item.output) * v.scale
            return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        let len = LightMath.beamLength(lamp, output: item.output) * v.scale
        let half = min(lamp.beam, 170) / 2
        var p = Path()
        p.move(to: c)
        p.addArc(center: c, radius: len, startAngle: .degrees(item.angle - half), endAngle: .degrees(item.angle + half), clockwise: false)
        p.closeSubpath()
        return p
    }

    /// Simple top-down shapes for now; real drawn heads with generic twins are still to do.
    static func drawHead(_ item: PlacedLamp, _ lamp: Lamp, on: Bool, selected: Bool, _ ctx: GraphicsContext, _ v: PlanViewport, _ line: Color, _ stroke: StrokeStyle, _ ink: Ink = .screen) {
        var g = ctx
        let c = v.point(item.position)
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .degrees(item.angle))
        let s = v.scale
        let w = lamp.width * s, h = lamp.depth * s
        var body = Path()
        var dotX: CGFloat = 0

        switch lamp.kind {
        case .panel:
            body.addRect(CGRect(x: -h / 2, y: -w / 2, width: h, height: w))
            body.move(to: CGPoint(x: h / 2, y: -w / 2)); body.addLine(to: CGPoint(x: h / 2, y: w / 2))
        case .point:
            body.addRect(CGRect(x: -w / 2, y: -h / 2, width: w * 0.62, height: h))
            body.move(to: CGPoint(x: w * 0.12, y: -h * 0.42))
            body.addLine(to: CGPoint(x: w / 2, y: -h * 0.62)); body.addLine(to: CGPoint(x: w / 2, y: h * 0.62))
            body.addLine(to: CGPoint(x: w * 0.12, y: h * 0.42)); body.closeSubpath()
            dotX = -w * 0.2
        case .fresnel:
            body.addRect(CGRect(x: -w / 2, y: -h / 2, width: w * 0.8, height: h))
            body.move(to: CGPoint(x: w * 0.3, y: -h * 0.5)); body.addLine(to: CGPoint(x: w * 0.52, y: -h * 0.74))
            body.move(to: CGPoint(x: w * 0.3, y: h * 0.5)); body.addLine(to: CGPoint(x: w * 0.52, y: h * 0.74))
            dotX = -w * 0.1
        case .tube:
            body.addRect(CGRect(x: -0.05 * s, y: -w / 2, width: 0.1 * s, height: w))
        case .practical:
            let r = max(w / 2, 0.12 * s)
            body.addEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
        case .bounce, .diff, .flag:
            // A frame seen edge-on: a bar along its width.
            body.addRect(CGRect(x: -w / 2, y: -h / 2, width: w, height: max(h, 0.06 * s)))
        }

        if lamp.isGrip {
            let fill: Color = lamp.kind == .flag ? line : ink.bg
            g.fill(body, with: .color(fill))
            g.stroke(body, with: .color(line), style: lamp.kind == .diff ? StrokeStyle(lineWidth: stroke.lineWidth, dash: [3, 2]) : stroke)
        } else {
            g.fill(body, with: .color(ink.bg))
            g.stroke(body, with: .color(line), style: stroke)
            let dr = (lamp.kind == .tube ? 0.07 : min(0.09, max(0.06, lamp.depth * 0.22))) * s
            let dot = Path(ellipseIn: CGRect(x: dotX - dr, y: -dr, width: dr * 2, height: dr * 2))
            if on {
                g.fill(dot, with: .color(ink.on))
            } else {
                g.fill(dot, with: .color(ink.bg))
                g.stroke(dot, with: .color(line), style: StrokeStyle(lineWidth: 0.8))
            }
        }

        if selected {
            let r = max(0.34, lamp.width * 0.66) * s
            g.stroke(Path(ellipseIn: CGRect(x: dotX - r, y: -r, width: r * 2, height: r * 2)), with: .color(ink.selection), style: StrokeStyle(lineWidth: 1.2))
        }
    }

    static func drawCamera(_ plot: Plot, _ ctx: GraphicsContext, _ v: PlanViewport, _ line: Color, _ stroke: StrokeStyle, _ ink: Ink = .screen) {
        var g = ctx
        let c = v.point(plot.camera)
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .degrees(plot.camera.bearing(to: plot.talent)))
        let s = v.scale
        var lines = Path()
        lines.move(to: CGPoint(x: 0.2 * s, y: -0.1 * s)); lines.addLine(to: CGPoint(x: 1.3 * s, y: -0.55 * s))
        lines.move(to: CGPoint(x: 0.2 * s, y: 0.1 * s)); lines.addLine(to: CGPoint(x: 1.3 * s, y: 0.55 * s))
        g.stroke(lines, with: .color(ink.quiet), style: StrokeStyle(lineWidth: stroke.lineWidth, dash: [2, 4]))
        let body = Path(CGRect(x: -0.3 * s, y: -0.18 * s, width: 0.5 * s, height: 0.36 * s))
        g.fill(body, with: .color(ink.bg))
        g.stroke(body, with: .color(line), style: stroke)
    }

    static func label(_ text: String, at p: CGPoint, _ ctx: GraphicsContext, color: Color = Palette.quiet) {
        ctx.draw(Text(text).font(Fonts.mono(10, .regular)).foregroundStyle(color), at: p)
    }
}

/// Small static plan for lists.
struct PlanThumbnail: View {
    let plot: Plot
    var body: some View {
        Canvas { ctx, size in
            let v = PlanViewport.fit(plot, in: size, margin: 0.6)
            PlanDrawing.draw(plot, in: ctx, viewport: v, options: .init(showGrid: false, showLabels: false, lineWidth: 0.6))
        }
        .background(Palette.p0, in: RoundedRectangle(cornerRadius: Radius.chip))
        .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Palette.rule))
    }
}
