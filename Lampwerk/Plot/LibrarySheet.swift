import SwiftUI

/// The lamp library: search, browse by group, tap to drop on the plan.
struct LibrarySheet: View {
    var pick: (Lamp) -> Void
    @State private var query = ""
    @State private var group: Lamp.Group?

    private var lamps: [Lamp] {
        LampLibrary.all.filter { lamp in
            (group == nil || lamp.group == group)
                && (query.isEmpty || "\(lamp.fullName) \(lamp.group.rawValue)".localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Caps("Lamps")
                Spacer()
                Text("(\(lamps.count))").font(.lwData).foregroundStyle(Palette.quiet)
            }
            .padding(.horizontal, 16).frame(minHeight: 52)
            Divider().overlay(Palette.rule)

            TextField("Search", text: $query)
                .font(.lwBody).foregroundStyle(Palette.text)
                .padding(.horizontal, 12).frame(height: 40)
                .background(Palette.p0, in: RoundedRectangle(cornerRadius: Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.rule))
                .padding(.horizontal, 16).padding(.top, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    Chip(title: "All", selected: group == nil) { group = nil }
                    ForEach(Lamp.Group.allCases, id: \.self) { g in
                        Chip(title: g.rawValue, selected: group == g) { group = g }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
            Divider().overlay(Palette.rule)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(lamps) { lamp in
                        Button { pick(lamp) } label: { LibraryRow(lamp: lamp) }
                            .buttonStyle(.plain)
                        Divider().overlay(Palette.rule)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct LibraryRow: View {
    let lamp: Lamp

    var body: some View {
        HStack(spacing: 14) {
            Canvas { ctx, size in
                let item = PlacedLamp(lampID: lamp.id, x: 0, y: 0, angle: 0, role: .key, cct: 5600, modifier: "None")
                let s = min(size.width, size.height) / max(0.4, lamp.width * 1.6)
                let v = PlanViewport(scale: s, origin: CGPoint(x: size.width / 2, y: size.height / 2))
                PlanDrawing.drawHead(item, lamp, on: lamp.isLight, selected: false, ctx, v, Palette.text.opacity(0.9), StrokeStyle(lineWidth: 1))
            }
            .frame(width: 40, height: 40)
            .background(Palette.p0, in: RoundedRectangle(cornerRadius: Radius.chip))

            VStack(alignment: .leading, spacing: 2) {
                Text(lamp.fullName).font(.lwTitle).foregroundStyle(Palette.text)
                Text(lamp.group.rawValue).font(.lwData).foregroundStyle(Palette.quiet)
            }
            Spacer()
            if lamp.isLight {
                Text(String(format: "%@ W · %.1f A", Int(lamp.spec?.drawW ?? lamp.watts).formatted(), LightMath.amps(lamp)))
                    .font(.lwData).foregroundStyle(Palette.quiet)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
