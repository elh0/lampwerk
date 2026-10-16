import SwiftUI

/// The selected lamp: what it is, what it's doing at the talent, and its settings.
struct Inspector: View {
    @Binding var plot: Plot
    let index: Int
    let supply: LightMath.Supply
    @Binding var selected: PlacedLamp.ID?

    private var item: PlacedLamp { plot.items[index] }

    var body: some View {
        if let lamp = item.lamp {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lamp.fullName).font(.lwTitle).foregroundStyle(Palette.text)
                            Text(meta(lamp)).font(.lwData).foregroundStyle(Palette.quiet)
                        }
                        Spacer()
                        Button("Close") { selected = nil }.buttonStyle(ActionButtonStyle())
                    }

                    NameField(placeholder: item.role.title, text: Binding(
                        get: { plot.items[index].name ?? "" },
                        set: { plot.items[index].name = $0.isEmpty ? nil : $0 }
                    ))

                    VStack(spacing: 0) {
                        if lamp.isLight {
                            row("At talent", plot.isOn(item) ? "\(Int(LightMath.lux(from: item, at: plot.talent, in: plot)).formatted()) lx" : "Off")
                            row("Draw", String(format: "%.1f A", LightMath.amps(item, supply: supply)))
                            cycleRow("Modifier", item.modifier, lamp.modifiers) { plot.items[index].modifier = $0 }
                            row("Spread", spreadText(lamp))
                            if lamp.isLight, LightMath.spread(item) < 300 { diffRow }
                            cycleRow("Gel", item.gel, Gels.all) { plot.items[index].gel = $0 }
                        }
                        if lamp.kind == .diff { frameRows }
                        row("Distance", String(format: "%.1f m", item.position.distance(to: plot.talent)), last: true)
                    }
                    .padding(.horizontal, 10)
                    .background(Palette.p0, in: RoundedRectangle(cornerRadius: Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.rule))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(Role.allCases, id: \.self) { role in
                                Chip(title: role.title, selected: item.role == role) { plot.items[index].role = role }
                            }
                        }
                    }

                    if lamp.isLight {
                        if let range = lamp.cct, range.upperBound > range.lowerBound {
                            slider("Colour", value: $plot.items[index].cct, in: range, step: 100, text: "\(Int(item.cct)) K")
                        }
                        slider("Output", value: $plot.items[index].output, in: 5...100, step: 5,
                               text: lamp.isDimmable ? "\(Int(item.output))%" : "Fixed")
                            .disabled(!lamp.isDimmable)
                            .opacity(lamp.isDimmable ? 1 : 0.35)
                    }

                    HStack(spacing: 6) {
                        if lamp.isLight {
                            Button(plot.isOn(item) ? "Switch off" : "Switch on") { toggle() }
                        }
                        Button("Duplicate") { duplicate() }
                        Button("Mirror") { mirror() }
                        Spacer()
                        Button("Remove") { remove() }.foregroundStyle(Palette.quiet)
                    }
                    .buttonStyle(ActionButtonStyle())
                    .padding(.bottom, 6)
                }
                .padding(.horizontal, 16).padding(.top, 12)
            }
            .frame(maxHeight: 330)
        }
    }

    private func meta(_ lamp: Lamp) -> String {
        guard lamp.isLight else { return lamp.group.rawValue }
        let beam = lamp.beam >= 300 ? "360°" : "\(Int(lamp.beam))°"
        return "\(Int(lamp.watts).formatted()) W · \(beam) · approx"
    }

    private func spreadText(_ lamp: Lamp) -> String {
        let s = LightMath.spread(item, in: plot)
        let text = s >= 300 ? "All round" : "\(Int(s))°"
        return s == lamp.beam ? text : text + " (from \(lamp.beam >= 300 ? "all round" : "\(Int(lamp.beam))°"))"
    }

    /// One tap puts a 4x4 of 216 in front of the head, square to its beam.
    /// Once it's there, the same row picks its material and size, or takes it away.
    private var diffRow: some View {
        let frame = LightMath.diffFrame(for: item, in: plot)
        return HStack {
            Text("Diff").font(.lwBody).foregroundStyle(Palette.quiet)
            Spacer()
            if let frame, let f = plot.items.firstIndex(where: { $0.id == frame.id }) {
                Menu {
                    materialPicker(f)
                    sizePicker(f)
                    Button("Remove diff", role: .destructive) { plot.items.remove(at: f) }
                } label: {
                    underlined("\(size(frame)) \(Diffusion.material(frame).name)")
                }
            } else {
                Button { addDiff() } label: { underlined("Add 216 in front") }.buttonStyle(.plain)
            }
        }
        .frame(minHeight: 30)
        .overlay(alignment: .bottom) { Divider().overlay(Palette.rule) }
    }

    /// A diff frame on its own: material, size and what it costs in stops.
    @ViewBuilder private var frameRows: some View {
        let m = Diffusion.material(item)
        menuRow("Material", m.name) { materialPicker(index) }
        menuRow("Size", size(item)) { sizePicker(index) }
        row("Loss", "About " + Diffusion.stops(m))
    }

    private func materialPicker(_ i: Int) -> some View {
        Picker("Material", selection: Binding(
            get: { Diffusion.material(plot.items[i]).name },
            set: { plot.items[i].modifier = $0 }
        )) {
            ForEach(Diffusion.materials, id: \.name) { m in
                Text("\(m.name), \(Diffusion.stops(m))").tag(m.name)
            }
        }
        .pickerStyle(.menu)
    }

    private func sizePicker(_ i: Int) -> some View {
        Picker("Size", selection: Binding(
            get: { plot.items[i].lampID },
            set: { plot.items[i].lampID = $0 }
        )) {
            ForEach(Diffusion.frames, id: \.self) { id in
                Text(LampLibrary.lamp(id).map { size(of: $0) } ?? id).tag(id)
            }
        }
        .pickerStyle(.menu)
    }

    private func size(_ frame: PlacedLamp) -> String { frame.lamp.map { size(of: $0) } ?? "" }
    private func size(of lamp: Lamp) -> String { String(lamp.name.split(separator: " ").first ?? "") }

    private func menuRow<Content: View>(_ label: String, _ value: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.lwBody).foregroundStyle(Palette.quiet)
            Spacer()
            Menu { content() } label: { underlined(value) }
        }
        .frame(minHeight: 30)
        .overlay(alignment: .bottom) { Divider().overlay(Palette.rule) }
    }

    private func underlined(_ text: String) -> some View {
        Text(text).font(.lwValue).foregroundStyle(Palette.text)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.ruleStrong).frame(height: 1).offset(y: 2)
            }
    }

    private func addDiff() {
        let reach = min(0.9, max(0.5, item.position.distance(to: plot.talent) * 0.4))
        let a = item.angle * .pi / 180
        let frame = PlacedLamp(
            lampID: "f4d", x: item.x + reach * cos(a), y: item.y + reach * sin(a),
            angle: item.angle + 90, role: .diff, cct: 0, modifier: Diffusion.standard, height: item.height
        )
        plot.items.insert(frame, at: index + 1)
    }

    private func row(_ label: String, _ value: String, last: Bool = false) -> some View {
        HStack {
            Text(label).font(.lwBody).foregroundStyle(Palette.quiet)
            Spacer()
            Text(value).font(.lwValue).foregroundStyle(Palette.text)
        }
        .frame(minHeight: 30)
        .overlay(alignment: .bottom) { if !last { Divider().overlay(Palette.rule) } }
    }

    /// Tap the value to step to the next option.
    private func cycleRow(_ label: String, _ value: String, _ options: [String], set: @escaping (String) -> Void) -> some View {
        HStack {
            Text(label).font(.lwBody).foregroundStyle(Palette.quiet)
            Spacer()
            Button {
                let i = options.firstIndex(of: value) ?? -1
                set(options[(i + 1) % options.count])
            } label: {
                Text(value).font(.lwValue).foregroundStyle(Palette.text)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Palette.ruleStrong).frame(height: 1).offset(y: 2)
                    }
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 30)
        .overlay(alignment: .bottom) { Divider().overlay(Palette.rule) }
    }

    private func slider(_ label: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, text: String) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.lwBody).foregroundStyle(Palette.quiet).frame(width: 64, alignment: .leading)
            Slider(value: value, in: range, step: step).tint(Palette.text)
            Text(text).font(.lwValue).foregroundStyle(Palette.text).frame(width: 64, alignment: .trailing)
        }
    }

    private func toggle() {
        let shot = plot.shot
        if plot.items[index].offIn.contains(shot) {
            plot.items[index].offIn.remove(shot)
        } else {
            plot.items[index].offIn.insert(shot)
        }
    }

    private func duplicate() {
        var copy = item
        copy.id = UUID()
        copy.x += 0.5
        copy.y += 0.5
        plot.items.insert(copy, at: index + 1)
        selected = copy.id
    }

    /// Reflects the lamp across the line from camera to talent.
    private func mirror() {
        var copy = item
        copy.id = UUID()
        let a = plot.camera, b = plot.talent
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return }
        let t = ((copy.x - a.x) * dx + (copy.y - a.y) * dy) / len2
        let foot = Point2(x: a.x + t * dx, y: a.y + t * dy)
        copy.x = 2 * foot.x - copy.x
        copy.y = 2 * foot.y - copy.y
        let lineAngle = atan2(dy, dx) * 180 / .pi
        copy.angle = 2 * lineAngle - copy.angle
        plot.items.insert(copy, at: index + 1)
        selected = copy.id
    }

    private func remove() {
        selected = nil
        plot.items.remove(at: index)
    }
}
