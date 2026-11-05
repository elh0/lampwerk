import SwiftUI

/// The top-down plan. Drag a lamp, the talent or the camera to move it, drag the handle to aim it, pinch to zoom.
/// Tap a lamp for its card; tap it again, or anywhere else, to let go. Press and hold a lamp to remove it.
struct PlanCanvas: View {
    @Binding var plot: Plot
    @Binding var selected: PlacedLamp.ID?
    @Binding var zoom: CGFloat
    @Binding var popTab: LampPop.Tab
    /// The lamp's card: a first tap only picks the lamp (so it can be dragged); a second tap opens this.
    var cardOpen: Binding<Bool> = .constant(false)
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

    private enum Target { case lamp(PlacedLamp.ID), aim(PlacedLamp.ID), talent, camera, wall(Bool), none, sketch(PlacedLamp.ID?) }

    private struct DragState {
        var target: Target
        var offset: Point2
        var moved = false
        /// Held still while a wall is dragged, so the room doesn't slide out from under your finger.
        var locked: PlanViewport?
        /// A press and hold removed the lamp, so letting go does nothing more.
        var held = false
    }

    /// Distance from a head to its aim handle, in metres.
    private static let handleReach = 1.15

    var body: some View {
        GeometryReader { geo in
            // Pinching never goes past the zoom limits mid-gesture, so the plan can't shrink to nothing.
            let v = drag?.locked ?? PlanViewport.fit(plot, in: geo.size, zoom: min(4, max(0.6, zoom * pinch)))
            Canvas { ctx, _ in
                PlanDrawing.draw(plot, in: ctx, viewport: v, options: .init(selected: selected))
                drawSelection(ctx, v)
                if mode == .move { drawWallHandles(ctx, v) }
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
            .overlay(alignment: .bottom) {
                // The card sits docked under the plan, never over the lamp, so the lamp can always be dragged
                // and the card never runs off the screen. Too wide for the screen, it scrolls sideways.
                if showPop, cardOpen.wrappedValue, let id = selected, drag?.moved != true, plot.items.contains(where: { $0.id == id }) {
                    ViewThatFits(in: .horizontal) {
                        LampPop(plot: $plot, id: id, tab: $popTab, more: more)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LampPop(plot: $plot, id: id, tab: $popTab, more: more)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 70)
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
        // The handles on the right and bottom walls resize the room.
        if mode == .move {
            let fingertip = 24 / v.scale
            if p.distance(to: Point2(x: plot.roomWidth, y: plot.roomDepth / 2)) < fingertip { return .wall(true) }
            if p.distance(to: Point2(x: plot.roomWidth / 2, y: plot.roomDepth)) < fingertip { return .wall(false) }
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
                    if case .wall = target { drag?.locked = v }
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
                case .wall(let across):
                    // Never smaller than what's in the room, never bigger than a stage.
                    let things = plot.items.map(\.position) + [plot.talent, plot.camera]
                    let at = (d.locked ?? v).metres(value.location)
                    if across {
                        let least = max(1.5, (things.map(\.x).max() ?? 0) + 0.3)
                        plot.roomWidth = (min(60, max(least, at.x)) * 4).rounded() / 4
                    } else {
                        let least = max(1.5, (things.map(\.y).max() ?? 0) + 0.3)
                        plot.roomDepth = (min(60, max(least, at.y)) * 4).rounded() / 4
                    }
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
                        if selected == id { cardOpen.wrappedValue.toggle() } else { selected = id; cardOpen.wrappedValue = false }
                    case .none, .sketch(.none):
                        if let armed { drop(armed.id, v.metres(value.startLocation)) } else { selected = nil }
                    case .talent, .camera, .wall:
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

    /// Two small grips, middle of the right wall and middle of the bottom wall: drag them to size the room.
    private func drawWallHandles(_ ctx: GraphicsContext, _ v: PlanViewport) {
        let right = v.point(x: plot.roomWidth, y: plot.roomDepth / 2)
        let bottom = v.point(x: plot.roomWidth / 2, y: plot.roomDepth)
        for (c, upright) in [(right, true), (bottom, false)] {
            let size = upright ? CGSize(width: 8, height: 30) : CGSize(width: 30, height: 8)
            let r = Path(roundedRect: CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height), cornerRadius: 4)
            ctx.fill(r, with: .color(Palette.p2))
            ctx.stroke(r, with: .color(Palette.quiet), lineWidth: 1)
        }
        if let d = drag, case .wall = d.target {
            PlanDrawing.label(String(format: "%.2g × %.2g M", plot.roomWidth, plot.roomDepth), at: CGPoint(x: right.x - 40, y: bottom.y + 18), ctx)
        }
    }
}
