import SwiftUI

/// The selected lamp's full settings, opened from More on its card. What it does at the talent on one line,
/// then the few things you change; the name, spread and where the numbers come from fold away under Details.
struct Inspector: View {
    @Binding var plot: Plot
    let index: Int
    let supply: LightMath.Supply
    @Binding var selected: PlacedLamp.ID?
    /// Closes the panel and lets go of the lamp.
    var done: () -> Void = {}
    /// Opens the lamp list to change this head.
    var change: () -> Void = {}

    @State private var details = false

    private var item: PlacedLamp { plot.items[index] }

    var body: some View {
        if let lamp = item.lamp {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "%02d ", index + 1) + item.title + " · " + lamp.shortName)
                                .font(.lwTitle).foregroundStyle(Palette.text).lineLimit(1)
                            Text(summary(lamp)).font(.lwData).foregroundStyle(Palette.quiet)
                        }
                        Spacer()
                        Button("Change") { change() }.buttonStyle(ActionButtonStyle())
                        Button("Done") { done() }.buttonStyle(ActionButtonStyle(primary: true))
                    }

                    VStack(spacing: 0) {
                        if lamp.isLight {
                            pickerRow("Modifier", item.modifier == "None" ? "Bare" : item.modifier, selection: Binding(
                                get: { plot.items[index].modifier },
                                set: { plot.items[index].modifier = $0; LastModifier.set(lamp.id, $0) }
                            ), options: lamp.modifiers)
                            if LightMath.spread(item) < 300 { diffRow }
                            pickerRow("Gel", item.gel, selection: $plot.items[index].gel, options: Gels.all, last: true)
                        }
                        if lamp.kind == .diff { frameRows }
                    }
                    .padding(.horizontal, 10)
                    .background(Palette.p0, in: RoundedRectangle(cornerRadius: Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.rule))

                    if lamp.isLight, spreads(lamp).count > 1 { spreadSlider(lamp) }

                    if lamp.isLight {
                        if let range = lamp.cct, range.upperBound > range.lowerBound {
                            slider("Colour", value: $plot.items[index].cct, in: range, step: 100, text: "\(Int(item.cct)) K")
                        }
                        if lamp.isDimmable {
                            slider("Output", value: $plot.items[index].output, in: 5...100, step: 5, text: "\(Int(item.output))%")
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(Role.allCases, id: \.self) { role in
                                Chip(title: role.title, selected: item.role == role) { plot.items[index].role = role }
                            }
                        }
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

                    DisclosureGroup(isExpanded: $details) {
                        VStack(alignment: .leading, spacing: 8) {
                            NameField(placeholder: item.role.title, text: Binding(
                                get: { plot.items[index].name ?? "" },
                                set: { plot.items[index].name = $0.isEmpty ? nil : $0 }
                            ))
                            Text(meta(lamp)).font(.lwData).foregroundStyle(Palette.quiet)
                            if lamp.isLight {
                                Text("Spread " + spreadText(lamp)).font(.lwData).foregroundStyle(Palette.quiet)
                                numbers(lamp)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("Details").font(.lwButton).foregroundStyle(Palette.quiet)
                    }
                    .tint(Palette.quiet)
                    .padding(.bottom, 6)
                }
                .padding(.horizontal, 16).padding(.top, 12)
            }
            .frame(maxHeight: 330)
        }
    }

    /// "1,240 lx at talent · 2.4 m · 3.1 A", or "Off in Wide · 2.4 m" for a light that's off.
    private func summary(_ lamp: Lamp) -> String {
        let distance = String(format: "%.1f m", item.position.distance(to: plot.talent))
        guard lamp.isLight else { return lamp.group.rawValue + " · " + distance }
        guard plot.isOn(item) else { return "Off in \(plot.shot.title) · " + distance }
        let lux = Int(LightMath.lux(from: item, at: plot.talent, in: plot)).formatted()
        return "\(lux) lx at talent · \(distance) · " + String(format: "%.1f A", LightMath.amps(item, supply: supply))
    }

    /// The head's modifiers, tightest beam first, each with the beam it gives.
    private func spreads(_ lamp: Lamp) -> [(modifier: String, beam: Double)] {
        lamp.modifiers.map { ($0, Modifiers.beam[$0] ?? lamp.beam) }.sorted { $0.beam < $1.beam }
    }

    /// Slide to open or close the beam; it picks the modifier that gives that spread.
    private func spreadSlider(_ lamp: Lamp) -> some View {
        let options = spreads(lamp)
        let i = options.firstIndex { $0.modifier == item.modifier } ?? 0
        let now = options[i]
        return slider("Spread", value: Binding(
            get: { Double(i) },
            set: { v in
                let m = options[Int(v.rounded())].modifier
                plot.items[index].modifier = m
                LastModifier.set(lamp.id, m)
            }
        ), in: 0...Double(options.count - 1), step: 1,
        text: now.beam >= 300 ? "All round" : "\(Int(now.beam))°")
    }

    private func pickerRow(_ label: String, _ value: String, selection: Binding<String>, options: [String], last: Bool = false) -> some View {
        HStack {
            Text(label).font(.lwBody).foregroundStyle(Palette.quiet)
            Spacer()
            Menu {
                Picker(label, selection: selection) {
                    ForEach(options, id: \.self) { Text($0 == "None" && label == "Modifier" ? "Bare" : $0).tag($0) }
                }
            } label: { underlined(value) }
        }
        .frame(minHeight: 36)
        .overlay(alignment: .bottom) { if !last { Divider().overlay(Palette.rule) } }
    }

    private func meta(_ lamp: Lamp) -> String {
        guard lamp.isLight else { return lamp.group.rawValue }
        let beam = lamp.beam >= 300 ? "360°" : "\(Int(lamp.beam))°"
        let draw = lamp.spec?.drawW ?? lamp.watts
        let trust = lamp.isChecked ? "checked" : lamp.spec?.source == .maker ? "maker spec" : "approx"
        return "\(Int(draw).formatted()) W · \(beam) · \(trust)"
    }

    /// Where this head's numbers come from, whether a gaffer has checked them, and a way to say they're wrong.
    private func numbers(_ lamp: Lamp) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: lamp.isChecked ? "checkmark.seal.fill" : "doc.text")
                    .font(.system(size: 11))
                Text(lamp.spec?.source.title ?? "Approximate")
                Text(lamp.isChecked ? "· checked by a gaffer" : "· not yet checked by a gaffer")
                    .foregroundStyle(Palette.quiet)
            }
            .font(.lwChip).foregroundStyle(Palette.text)
            if let spec = lamp.spec {
                Text(spec.note).font(.lwChip).foregroundStyle(Palette.quiet).fixedSize(horizontal: false, vertical: true)
            }
            if let url = reportURL(lamp) {
                Link("Report a wrong number", destination: url)
                    .font(.lwChip).foregroundStyle(Palette.text).underline()
                    .frame(minHeight: 30)
            }
        }
    }

    /// An email to the studio with the head and the figures the app is using, so the fix is easy to find.
    private func reportURL(_ lamp: Lamp) -> URL? {
        let figures = lamp.spec.map { "Using: \(Int($0.lux3m)) lx at 3 m, \(Int($0.beam))°, \(Int($0.drawW)) W draw. Source: \($0.url)" }
            ?? "Using: \(Int(lamp.watts)) W, \(Int(lamp.beam))°."
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = "hello@eltio.studio"
        c.queryItems = [
            URLQueryItem(name: "subject", value: "Lampwerk: wrong number on \(lamp.fullName)"),
            URLQueryItem(name: "body", value: "\(figures)\n\nWhat it should be, and where you got it:\n"),
        ]
        return c.url
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

    private func addDiff() { plot.addDiff(before: index) }

    private func row(_ label: String, _ value: String, last: Bool = false) -> some View {
        HStack {
            Text(label).font(.lwBody).foregroundStyle(Palette.quiet)
            Spacer()
            Text(value).font(.lwValue).foregroundStyle(Palette.text)
        }
        .frame(minHeight: 30)
        .overlay(alignment: .bottom) { if !last { Divider().overlay(Palette.rule) } }
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
