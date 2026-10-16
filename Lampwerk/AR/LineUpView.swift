import SwiftUI

/// Before AR on a plot with a floor plan: tap two spots on the plan that are easy to find in the room
/// (a door frame, a corner, a pillar). Tagging the same two spots in AR lines everything up.
struct LineUpView: View {
    let plot: Plot
    var start: (Point2, Point2) -> Void
    var skip: () -> Void
    var cancel: () -> Void

    @State private var a: Point2?
    @State private var b: Point2?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel", action: cancel).buttonStyle(ActionButtonStyle())
                Spacer()
                Caps("Line up with the plan")
                Spacer()
                Button("Skip", action: skip).buttonStyle(ActionButtonStyle())
            }
            .padding(.horizontal, 16).frame(minHeight: 56)
            Divider().overlay(Palette.rule)

            Text(prompt)
                .font(.lwBody).foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 12)

            GeometryReader { geo in
                let v = PlanViewport.fit(plot, in: geo.size, margin: 0.4)
                ZStack {
                    Canvas { ctx, _ in
                        var bare = plot
                        bare.items = []
                        PlanDrawing.draw(bare, in: ctx, viewport: v, options: .init(showLabels: false))
                    }
                    if let a { pin("A", at: v.point(a)) }
                    if let b { pin("B", at: v.point(b)) }
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let p = v.metres(location)
                    guard p.x > -0.5, p.y > -0.5, p.x < plot.roomWidth + 0.5, p.y < plot.roomDepth + 0.5 else { return }
                    if a == nil || b != nil { a = p; b = nil } else { b = p }
                }
            }

            HStack {
                Button("Reset") { a = nil; b = nil }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(a == nil)
                Spacer()
                Button("Start AR") { if let a, let b { start(a, b) } }
                    .buttonStyle(ActionButtonStyle(primary: true))
                    .disabled(!ready)
                    .opacity(ready ? 1 : 0.4)
            }
            .padding(.horizontal, 16).frame(minHeight: 60)
            .background(Palette.p1)
            .overlay(alignment: .top) { Divider().overlay(Palette.rule) }
        }
        .background(Palette.p0)
    }

    private var ready: Bool {
        guard let a, let b else { return false }
        return a.distance(to: b) > 0.3
    }

    private var prompt: String {
        if a == nil { return "Tap spot A on the plan: something you can find in the room, like a door frame or a corner." }
        if b == nil { return "Now spot B, as far from A as you can. The further apart, the better it lines up." }
        if !ready { return "A and B are too close. Pick spots further apart." }
        return String(format: "A to B is %.1f m on the plan. Next you'll tag the same two spots in the room.", a!.distance(to: b!))
    }

    private func pin(_ label: String, at p: CGPoint) -> some View {
        ZStack {
            Circle().fill(Palette.text).frame(width: 26, height: 26)
            Text(label).font(.lwData).foregroundStyle(Palette.p0)
        }
        .position(p)
        .allowsHitTesting(false)
    }
}
