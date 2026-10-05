import SwiftUI

/// The top-down plan. Drag a lamp to move it, drag the handle to aim it, tap to select, pinch to zoom.
struct PlanCanvas: View {
    @Binding var plot: Plot
    @Binding var selected: PlacedLamp.ID?
    @Binding var zoom: CGFloat

    @State private var drag: DragState?
    @GestureState private var pinch: CGFloat = 1

    private enum Target { case lamp(PlacedLamp.ID), aim(PlacedLamp.ID), talent, none }

    private struct DragState {
        var target: Target
        var offset: Point2
        var moved = false
    }

    /// Distance from a head to its aim handle, in metres.
    private static let handleReach = 1.15

    var body: some View {
        GeometryReader { geo in
            let v = PlanViewport.fit(plot, in: geo.size, zoom: zoom * pinch)
            Canvas { ctx, _ in
                PlanDrawing.draw(plot, in: ctx, viewport: v, options: .init(selected: selected))
                drawSelection(ctx, v)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(v))
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in zoom = min(4, max(0.6, zoom * value.magnification)) }
            )
            .accessibilityLabel("Lighting plan. Drag lamps to move, drag the handle to aim, pinch to zoom.")
        }
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
        let nearest = plot.items
            .map { ($0.id, $0.position.distance(to: p)) }
            .filter { $0.1 < reach }
            .min { $0.1 < $1.1 }
        if let nearest { return .lamp(nearest.0) }
        if plot.talent.distance(to: p) < reach { return .talent }
        return .none
    }

    private func dragGesture(_ v: PlanViewport) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let p = v.metres(value.location)
                if drag == nil {
                    let start = v.metres(value.startLocation)
                    let target = hitTest(start, v)
                    var offset = Point2(x: 0, y: 0)
                    switch target {
                    case .lamp(let id):
                        if let item = plot.items.first(where: { $0.id == id }) {
                            offset = Point2(x: item.x - start.x, y: item.y - start.y)
                        }
                    case .talent:
                        offset = Point2(x: plot.talent.x - start.x, y: plot.talent.y - start.y)
                    default: break
                    }
                    drag = DragState(target: target, offset: offset)
                }
                guard var d = drag else { return }
                if !d.moved, hypot(value.translation.width, value.translation.height) > 4 { d.moved = true }
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
                    plot.talent = Point2(
                        x: min(plot.roomWidth - 0.3, max(0.3, p.x + d.offset.x)),
                        y: min(plot.roomDepth - 0.3, max(0.3, p.y + d.offset.y))
                    )
                case .none:
                    break
                }
            }
            .onEnded { _ in
                if let d = drag, !d.moved {
                    switch d.target {
                    case .lamp(let id): selected = selected == id ? nil : id
                    case .none: selected = nil
                    default: break
                    }
                }
                drag = nil
            }
    }
}
