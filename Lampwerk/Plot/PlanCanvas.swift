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
    /// Opens the lamp list to change the picked lamp's head.
    var change: () -> Void = {}
    /// Lamps boxed together by dragging across empty floor; the editor's Delete takes them all.
    @Binding var group: Set<PlacedLamp.ID>
    /// How far the plan has been dragged from centre. One finger on empty floor pans; press and hold, then drag, boxes.
    @Binding var pan: CGSize
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
    @State private var boxHold: Task<Void, Never>?
    @State private var livePan: CGSize = .zero
    /// Lamps boxed together by dragging across empty floor, plus the talent and camera if the box took them in.
    @State private var groupTalent = false
    @State private var groupCamera = false
    /// The box being dragged out, in metres.
    @State private var lasso: (Point2, Point2)?
    @GestureState private var pinch: CGFloat = 1

    private enum Wall { case left, right, top, bottom }
    private enum Target { case lamp(PlacedLamp.ID), aim(PlacedLamp.ID), talent, camera, wall(Wall), none, sketch(PlacedLamp.ID?) }

    private struct DragState {
        var target: Target
        var offset: Point2
        var moved = false
        /// Held still while a wall is dragged, so the room doesn't slide out from under your finger.
        var locked: PlanViewport?
        /// Where everything in the group stood when the drag began.
        var starts: [PlacedLamp.ID: Point2] = [:]
        var startTalent = Point2(x: 0, y: 0)
        var startCamera = Point2(x: 0, y: 0)
        var from = Point2(x: 0, y: 0)
        /// A press held still on empty floor turns the drag into a box.
        var boxing = false
        /// A press and hold removed the lamp, so letting go does nothing more.
        var held = false
    }

    /// Distance from a head to its aim handle, in metres.
    private static let handleReach = 1.15

    var body: some View {
        GeometryReader { geo in
            // Pinching never goes past the zoom limits mid-gesture, so the plan can't shrink to nothing.
            let v = drag?.locked ?? PlanViewport.fit(plot, in: geo.size, zoom: min(4, max(0.6, zoom * pinch)),
                                                          pan: CGSize(width: pan.width + livePan.width, height: pan.height + livePan.height))
            Canvas { ctx, size in
                drawOutsideGrid(ctx, v, size)
                PlanDrawing.draw(plot, in: ctx, viewport: v, options: .init(selected: selected))
                drawSelection(ctx, v)
                if mode == .move { drawWallHandles(ctx, v) }
                drawGroup(ctx, v)
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
                        LampPop(plot: $plot, id: id, tab: $popTab, more: more, change: change)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LampPop(plot: $plot, id: id, tab: $popTab, more: more, change: change)
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
        let reach = max(0.5, 30 / v.scale)
        if let item = plot.items.first(where: { $0.id == selected }), handle(item).distance(to: p) < reach * 0.8 {
            return .aim(item.id)
        }
        // A grip in the middle of each wall resizes the room from that side.
        if mode == .move {
            let fingertip = 24 / v.scale
            for (wall, at) in wallGrips() where p.distance(to: at) < fingertip { return .wall(wall) }
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
                    if !isGrouped(target) { clearGroup() } else {
                        drag?.from = start
                        drag?.starts = Dictionary(uniqueKeysWithValues: plot.items.filter { group.contains($0.id) }.map { ($0.id, $0.position) })
                        drag?.startTalent = plot.talent
                        drag?.startCamera = plot.camera
                    }
                    switch target {
                    case .lamp(let id), .sketch(let id?): if group.isEmpty { holdToRemove(id) }
                    case .none where mode == .move && armed == nil: holdToBox()
                    default: break
                    }
                }
                guard var d = drag, !d.held else { return }
                if !d.moved, hypot(value.translation.width, value.translation.height) > 4 { d.moved = true; hold?.cancel(); boxHold?.cancel() }
                drag = d
                guard d.moved else { return }

                // Something in the group: everything boxed moves together.
                if !group.isEmpty || groupTalent || groupCamera, isGrouped(d.target) {
                    let dx = p.x - d.from.x, dy = p.y - d.from.y
                    for (id, s) in d.starts {
                        if let i = plot.items.firstIndex(where: { $0.id == id }) {
                            plot.items[i].x = s.x + dx
                            plot.items[i].y = s.y + dy
                        }
                    }
                    if groupTalent { plot.talent = inRoom(Point2(x: d.startTalent.x + dx, y: d.startTalent.y + dy)) }
                    if groupCamera { plot.camera = inRoom(Point2(x: d.startCamera.x + dx, y: d.startCamera.y + dy)) }
                    return
                }

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
                case .wall(let wall):
                    // Never smaller than what's in the room, never bigger than a stage. The left and top walls
                    // move the room's corner, so everything shifts to keep its place on screen.
                    let things = plot.items.map(\.position) + [plot.talent, plot.camera]
                    let at = (d.locked ?? v).metres(value.location)
                    let q = { (x: Double) in (x * 4).rounded() / 4 }
                    switch wall {
                    case .right:
                        let least = max(1.5, (things.map(\.x).max() ?? 0) + 0.3)
                        plot.roomWidth = q(min(60, max(least, at.x)))
                    case .bottom:
                        let least = max(1.5, (things.map(\.y).max() ?? 0) + 0.3)
                        plot.roomDepth = q(min(60, max(least, at.y)))
                    case .left:
                        let most = min(plot.roomWidth - 1.5, (things.map(\.x).min() ?? 0) - 0.3)
                        let shift = q(max(plot.roomWidth - 60, min(most, at.x)))
                        guard shift != 0 else { break }
                        shiftRoom(dx: shift, dy: 0)
                        drag?.locked?.origin.x += shift * (d.locked?.scale ?? v.scale)
                    case .top:
                        let most = min(plot.roomDepth - 1.5, (things.map(\.y).min() ?? 0) - 0.3)
                        let shift = q(max(plot.roomDepth - 60, min(most, at.y)))
                        guard shift != 0 else { break }
                        shiftRoom(dx: 0, dy: shift)
                        drag?.locked?.origin.y += shift * (d.locked?.scale ?? v.scale)
                    }
                case .sketch:
                    if stroke.isEmpty { stroke = [v.metres(value.startLocation)] }
                    stroke.append(p)
                case .none:
                    // Held first: box lamps together. Straight away: move around the plan.
                    if d.boxing { lasso = ((d.locked ?? v).metres(value.startLocation), (d.locked ?? v).metres(value.location)) }
                    else if mode == .move { livePan = value.translation }
                }
            }
            .onEnded { value in
                hold?.cancel()
                boxHold?.cancel()
                if livePan != .zero {
                    pan = CGSize(width: pan.width + livePan.width, height: pan.height + livePan.height)
                    livePan = .zero
                }
                if let box = lasso { finishLasso(box) }
                if let d = drag, d.moved, case .sketch = d.target { finishSketch() }
                if let d = drag, !d.moved, !d.held {
                    switch d.target {
                    case .lamp(let id), .sketch(let id?):
                        if selected == id { cardOpen.wrappedValue.toggle() } else { selected = id; cardOpen.wrappedValue = false }
                    case .none, .sketch(.none):
                        if let armed { drop(armed.id, v.metres(value.startLocation)) } else { selected = nil; clearGroup() }
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

    /// The middle of each wall, where its grip sits.
    private func wallGrips() -> [(Wall, Point2)] {
        let w = plot.roomWidth, d = plot.roomDepth
        return [(.right, Point2(x: w, y: d / 2)), (.bottom, Point2(x: w / 2, y: d)),
                (.left, Point2(x: 0, y: d / 2)), (.top, Point2(x: w / 2, y: 0))]
    }

    /// Moves the room's top-left corner by (dx, dy) metres, keeping everything where it stands.
    private func shiftRoom(dx: Double, dy: Double) {
        plot.roomWidth -= dx
        plot.roomDepth -= dy
        for i in plot.items.indices {
            plot.items[i].x -= dx
            plot.items[i].y -= dy
        }
        plot.talent = Point2(x: plot.talent.x - dx, y: plot.talent.y - dy)
        plot.camera = Point2(x: plot.camera.x - dx, y: plot.camera.y - dy)
    }

    /// A small grip in the middle of each wall: drag it to size the room from that side.
    private func drawWallHandles(_ ctx: GraphicsContext, _ v: PlanViewport) {
        for (wall, at) in wallGrips() {
            let c = v.point(at)
            let upright = wall == .left || wall == .right
            let size = upright ? CGSize(width: 8, height: 30) : CGSize(width: 30, height: 8)
            let r = Path(roundedRect: CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height), cornerRadius: 4)
            ctx.fill(r, with: .color(Palette.p2))
            ctx.stroke(r, with: .color(Palette.quiet), lineWidth: 1)
        }
        if let d = drag, case .wall = d.target {
            let c = v.point(x: plot.roomWidth / 2, y: plot.roomDepth)
            PlanDrawing.label(String(format: "%.2g × %.2g M", plot.roomWidth, plot.roomDepth), at: CGPoint(x: c.x, y: c.y + 20), ctx)
        }
    }

    /// A very faint metre grid beyond the walls, so lamps dragged outside still read against distance.
    private func drawOutsideGrid(_ ctx: GraphicsContext, _ v: PlanViewport, _ size: CGSize) {
        let tl = v.metres(.zero), br = v.metres(CGPoint(x: size.width, y: size.height))
        var grid = Path()
        for x in stride(from: tl.x.rounded(.down), through: br.x, by: 1) {
            grid.move(to: v.point(x: x, y: tl.y)); grid.addLine(to: v.point(x: x, y: br.y))
        }
        for y in stride(from: tl.y.rounded(.down), through: br.y, by: 1) {
            grid.move(to: v.point(x: tl.x, y: y)); grid.addLine(to: v.point(x: br.x, y: y))
        }
        ctx.stroke(grid, with: .color(Palette.text.opacity(0.025)), lineWidth: 1)
    }

    private func isGrouped(_ t: Target) -> Bool {
        switch t {
        case .lamp(let id): return group.contains(id)
        case .talent: return groupTalent
        case .camera: return groupCamera
        default: return false
        }
    }

    private func clearGroup() {
        group = []
        groupTalent = false
        groupCamera = false
    }

    /// Whatever the box took in becomes the group. One lamp is just a pick.
    private func finishLasso(_ box: (Point2, Point2)) {
        lasso = nil
        let minX = min(box.0.x, box.1.x), maxX = max(box.0.x, box.1.x)
        let minY = min(box.0.y, box.1.y), maxY = max(box.0.y, box.1.y)
        func inside(_ p: Point2) -> Bool { p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY }
        let ids = plot.items.filter { inside($0.position) }.map(\.id)
        let t = inside(plot.talent), c = inside(plot.camera)
        if ids.count == 1 && !t && !c {
            selected = ids[0]
            return
        }
        selected = nil
        group = Set(ids)
        groupTalent = t
        groupCamera = c
        let n = ids.count + (t ? 1 : 0) + (c ? 1 : 0)
        if n > 0 { say("\(n) picked · drag any of them to move together") }
    }

    /// The box while you drag it, and a ring on everything in the group.
    private func drawGroup(_ ctx: GraphicsContext, _ v: PlanViewport) {
        if let box = lasso {
            let a = v.point(box.0), b = v.point(box.1)
            let r = Path(CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)))
            ctx.fill(r, with: .color(Palette.gel.opacity(0.06)))
            ctx.stroke(r, with: .color(Palette.gel), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        var rings: [Point2] = plot.items.filter { group.contains($0.id) }.map(\.position)
        if groupTalent { rings.append(plot.talent) }
        if groupCamera { rings.append(plot.camera) }
        for p in rings {
            let c = v.point(p), r: CGFloat = 18
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Palette.gel), lineWidth: 1.2)
        }
    }

    /// Hold still on empty floor for a moment, then drag, to box lamps together. The plan holds still meanwhile.
    private func holdToBox() {
        boxHold?.cancel()
        boxHold = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, var d = drag, !d.moved else { return }
            d.boxing = true
            drag = d
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            say("Drag to box lamps together")
        }
    }
}
