import SwiftUI

/// The top-down plan. Drag a lamp, the talent or the camera to move it, drag the handle to aim it, pinch to zoom.
/// Tap a lamp for its card; tap it again, or anywhere else, to let go. Press and hold a lamp to remove it.
struct PlanCanvas: View {
    @Binding var plot: Plot
    @Binding var selected: PlacedLamp.ID?
    @Binding var zoom: CGFloat
    @Binding var popTab: LampPop.Tab
    /// A quick lamp waiting to be dropped with the next tap on empty floor.
    var armed: Lamp?
    /// Puts a lamp (by library id) down at a point on the plan.
    var drop: (String, Point2) -> Void
    /// Opens the full settings for the picked lamp.
    var more: () -> Void
    var mode: PlanMode = .move
    /// Off while the drawer shows the lamp's full settings, so only one panel is ever open.
    var showPop = true
    /// A line for whatever just happened.
    var say: (String) -> Void = { _ in }

    /// The stroke being drawn in Sketch, in metres.
    @State private var stroke: [Point2] = []

    @State private var drag: DragState?
    @State private var hold: Task<Void, Never>?
    @GestureState private var pinch: CGFloat = 1

    private enum Target { case lamp(PlacedLamp.ID), aim(PlacedLamp.ID), talent, camera, none, sketch(PlacedLamp.ID?) }

    private struct DragState {
        var target: Target
        var offset: Point2
        var moved = false
        /// A press and hold removed the lamp, so letting go does nothing more.
        var held = false
    }

    /// Distance from a head to its aim handle, in metres.
    private static let handleReach = 1.15

    var body: some View {
        GeometryReader { geo in
            let v = PlanViewport.fit(plot, in: geo.size, zoom: zoom * pinch)
            Canvas { ctx, _ in
                PlanDrawing.draw(plot, in: ctx, viewport: v, options: .init(selected: selected))
                drawSelection(ctx, v)
                if stroke.count > 1 {
                    var path = Path()
                    path.addLines(stroke.map { v.point($0) })
                    ctx.stroke(path, with: .color(Palette.gel), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(v))
            .dropDestination(for: String.self) { ids, location in
                guard let id = ids.first, LampLibrary.lamp(id) != nil else { return false }
                drop(id, v.metres(location))
                return true
            }
            .overlay(alignment: .topLeading) {
                if showPop, let id = selected, drag?.moved != true, let item = plot.items.first(where: { $0.id == id }) {
                    let c = v.point(item.position)
                    LampPop(plot: $plot, id: id, tab: $popTab, more: more)
                        .alignmentGuide(.leading) { d in d.width / 2 }
                        .alignmentGuide(.top) { d in d.height + 30 }
                        .offset(x: min(max(c.x, 170), max(170, geo.size.width - 170)), y: max(c.y, 140))
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topLeading) {
                // While you draw, what the stroke will become before you lift your finger.
                if let last = stroke.last {
                    let p = v.point(last)
                    Text(reading.label(from: strokeFrom) ?? "Keep going: close the shape")
                        .font(.lwButton)
                        .foregroundStyle(reading.label(from: strokeFrom) == nil ? Palette.quiet : Palette.p0)
                        .padding(.horizontal, 10).frame(minHeight: 30)
                        .background(reading.label(from: strokeFrom) == nil ? Palette.p2 : Palette.gel, in: RoundedRectangle(cornerRadius: Radius.card))
                        .fixedSize()
                        .alignmentGuide(.leading) { d in d.width / 2 }
                        .alignmentGuide(.top) { d in d.height + 34 }
                        .offset(x: min(max(p.x, 90), max(90, geo.size.width - 90)), y: p.y)
                        .allowsHitTesting(false)
                }
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in zoom = min(4, max(0.6, zoom * value.magnification)) }
            )
            .accessibilityLabel("Lighting plan. Drag lamps, the talent or the camera to move, drag the handle to aim, pinch to zoom.")
        }
    }

    private var strokeFrom: PlacedLamp? {
        if let d = drag, case .sketch(let id?) = d.target { return plot.items.first { $0.id == id } }
        return nil
    }

    private var reading: Sketch.Reading { Sketch.read(stroke, from: strokeFrom, talent: plot.talent) }

    /// A finished stroke: aim the lamp it came out of, or turn the shape into a lamp.
    private func finishSketch() {
        let from = strokeFrom
        switch reading {
        case .tap:
            break
        case .aim(let a):
            guard let from, let i = plot.items.firstIndex(where: { $0.id == from.id }) else { break }
            let aim = a ?? from.position.bearing(to: plot.talent)
            plot.items[i].angle = (from.lamp?.isGrip ?? false) ? aim + 90 : aim
            say("Aimed \(from.lamp?.shortName ?? "it")" + (a == nil ? " at talent" : ""))
        case .shape(let shape, let centre):
            drop(shape.lamp.id, centre)
        case .unclear:
            say("Didn't catch that. Try a circle, triangle, box or line")
        }
        stroke = []
    }

    /// The aim handle and the measured line to the talent for the selected lamp.
    private func drawSelection(_ ctx: GraphicsContext, _ v: PlanViewport) {
        guard let item = plot.items.first(where: { $0.id == selected }) else { return }
        let c = v.point(item.position)
        let h = v.point(handle(item))
        var line = Path(); line.move(to: c); line.addLine(to: h)
        ctx.stroke(line, with: .color(Palette.quiet), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        let r: CGFloat = 6
        let dot = Path(ellipseIn: CGRect(x: h.x - r, y: h.y - r, width: r * 2, height: r * 2))
        ctx.fill(dot, with: .color(Palette.p0))
        ctx.stroke(dot, with: .color(Palette.text), lineWidth: 1)

        let t = v.point(plot.talent)
        var measure = Path(); measure.move(to: c); measure.addLine(to: t)
        ctx.stroke(measure, with: .color(Palette.quiet), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
        let mid = CGPoint(x: (c.x + t.x) / 2 + 8, y: (c.y + t.y) / 2 - 8)
        PlanDrawing.label(String(format: "%.1f M", item.position.distance(to: plot.talent)), at: mid, ctx)
    }

    private func handle(_ item: PlacedLamp) -> Point2 {
        let a = item.angle * .pi / 180
        return Point2(x: item.x + Self.handleReach * cos(a), y: item.y + Self.handleReach * sin(a))
    }

    private func hitTest(_ p: Point2, _ v: PlanViewport) -> Target {
        // Never smaller than a fingertip.
        let reach = max(0.5, 22 / v.scale)
        if let item = plot.items.first(where: { $0.id == selected }), handle(item).distance(to: p) < reach * 0.8 {
            return .aim(item.id)
        }
        // Whatever is nearest the finger, so a lamp tagged close to the talent or camera doesn't hide them.
        var candidates: [(Target, Double)] = plot.items.map { (.lamp($0.id), $0.position.distance(to: p)) }
        candidates.append((.talent, plot.talent.distance(to: p)))
        candidates.append((.camera, plot.camera.distance(to: p)))
        let nearest = candidates.filter { $0.1 < reach }.min { $0.1 < $1.1 }
        return nearest?.0 ?? .none
    }

    private func inRoom(_ p: Point2) -> Point2 {
        Point2(x: min(plot.roomWidth - 0.3, max(0.3, p.x)), y: min(plot.roomDepth - 0.3, max(0.3, p.y)))
    }

    private func dragGesture(_ v: PlanViewport) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let p = v.metres(value.location)
                if drag == nil {
                    let start = v.metres(value.startLocation)
                    var target = hitTest(start, v)
                    var offset = Point2(x: 0, y: 0)
                    if mode == .sketch {
                        if case .lamp(let id) = target { target = .sketch(id) }
                        if case .none = target { target = .sketch(nil) }
                    }
                    switch target {
                    case .lamp(let id):
                        if let item = plot.items.first(where: { $0.id == id }) {
                            offset = Point2(x: item.x - start.x, y: item.y - start.y)
                        }
                    case .talent:
                        offset = Point2(x: plot.talent.x - start.x, y: plot.talent.y - start.y)
                    case .camera:
                        offset = Point2(x: plot.camera.x - start.x, y: plot.camera.y - start.y)
                    default: break
                    }
                    drag = DragState(target: target, offset: offset)
                    switch target {
                    case .lamp(let id), .sketch(let id?): holdToRemove(id)
                    default: break
                    }
                }
                guard var d = drag, !d.held else { return }
                if !d.moved, hypot(value.translation.width, value.translation.height) > 4 { d.moved = true; hold?.cancel() }
                drag = d
                guard d.moved else { return }

                switch d.target {
                case .lamp(let id):
                    guard let i = plot.items.firstIndex(where: { $0.id == id }) else { return }
                    selected = id
                    plot.items[i].x = p.x + d.offset.x
                    plot.items[i].y = p.y + d.offset.y
                case .aim(let id):
                    guard let i = plot.items.firstIndex(where: { $0.id == id }) else { return }
                    plot.items[i].angle = plot.items[i].position.bearing(to: p)
                case .talent:
                    plot.talent = inRoom(Point2(x: p.x + d.offset.x, y: p.y + d.offset.y))
                case .camera:
                    plot.camera = inRoom(Point2(x: p.x + d.offset.x, y: p.y + d.offset.y))
                case .sketch:
                    if stroke.isEmpty { stroke = [v.metres(value.startLocation)] }
                    stroke.append(p)
                case .none:
                    break
                }
            }
            .onEnded { value in
                hold?.cancel()
                if let d = drag, d.moved, case .sketch = d.target { finishSketch() }
                if let d = drag, !d.moved, !d.held {
                    switch d.target {
                    case .lamp(let id), .sketch(let id?):
                        selected = selected == id ? nil : id
                    case .none, .sketch(.none):
                        if let armed { drop(armed.id, v.metres(value.startLocation)) } else { selected = nil }
                    case .talent, .camera:
                        selected = nil
                    case .aim:
                        break
                    }
                }
                drag = nil
                stroke = []
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
