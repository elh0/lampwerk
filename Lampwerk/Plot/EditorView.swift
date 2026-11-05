import SwiftUI

/// One plot: the plan fills the screen, with one drawer for setups, lamps and the selected lamp.
struct EditorView: View {
    @Environment(PlotStore.self) private var store
    let plotID: Plot.ID
    var close: () -> Void

    @State private var plot: Plot?
    @State private var selected: PlacedLamp.ID?
    @State private var showingLibrary = false
    @State private var zoom: CGFloat = 1
    @State private var showingAR = false
    @State private var confirmingAR = false
    @State private var showingSend = false
    /// Set when AR tagging finishes, so the send sheet follows straight after.
    @State private var sendAfterAR = false
    /// The name being typed in the rename box; nil when it's closed.
    @State private var renaming: String?
    /// Every change to the plot, for undo and redo.
    @State private var history = PlotHistory()
    /// Set while undo or redo puts an older plot back, so that doesn't count as a new change.
    @State private var restoring = false
    /// A quick lamp waiting for a tap on the plan.
    @State private var armed: Lamp?
    @State private var popTab: LampPop.Tab = .mods
    /// Where the history stood when a lamp was picked, to tell whether letting go of it saved anything.
    @State private var pickMark = 0
    @State private var toast: String?
    /// Sketch draws lamps by shape and aims them; Move drags.
    @State private var planMode: PlanMode = .sketch
    /// Top down or 3D, and which way the 3D view is turned.
    @State private var show3D = false
    @State private var yaw = IsoProjection.defaultYaw
    @State private var pitch = IsoProjection.defaultPitch
    @State private var showingSpace = false
    /// Closed, the drawer shows setups and the lamp count; open, it adds the lamps and the inspector.
    @State private var drawerOpen = false
    /// The drawer's height upright, so the plan can sit above it with the whole room in view.
    @State private var drawerHeight: CGFloat = 62
    /// Compact height means an iPhone on its side: the drawer becomes a column on the right.
    @Environment(\.verticalSizeClass) private var verticalSize

    var body: some View {
        Group {
            if let binding = Binding($plot) {
                editor(binding)
            } else {
                Palette.p0
            }
        }
        .onAppear { plot = store.plots.first { $0.id == plotID } }
        .onChange(of: plot) { old, new in
            guard let new else { return }
            store.update(new)
            if restoring { restoring = false } else if let old { history.record(old) }
            if let id = selected, !new.items.contains(where: { $0.id == id }) { selected = nil }
        }
    }

    private func editor(_ plot: Binding<Plot>) -> some View {
        sheets(layout(plot), plot)
    }

    private func layout(_ plot: Binding<Plot>) -> some View {
        let wide = verticalSize == .compact
        return VStack(spacing: 0) {
            topBar(plot)
            ZStack(alignment: wide ? .topTrailing : .bottom) {
                plan(plot)
                    // Keep the plan clear of the drawer: above it upright, beside it on its side.
                    .padding(.bottom, wide ? 0 : drawerHeight)
                    .padding(.trailing, wide && drawerOpen ? 360 : 0)
                drawer(plot, wide: wide)
            }
        }
        .background(Palette.p0)
        .animation(.snappy(duration: 0.25), value: drawerOpen)
        .animation(.snappy(duration: 0.25), value: selected)
        .onChange(of: selected) { old, new in
            if new != nil, old == nil { pickMark = history.count }
            if old != nil, new == nil, history.count != pickMark, self.plot?.items.contains(where: { $0.id == old }) == true { say("Saved") }
            if new != nil { armed = nil }
        }
    }

    /// The plan with the live readout over it, undo and redo in thumb reach, and a line for whatever just happened.
    private func plan(_ plot: Binding<Plot>) -> some View {
        ZStack(alignment: .top) {
            if show3D {
                IsoCanvas(
                    plot: plot, selected: $selected, zoom: $zoom, popTab: $popTab, yaw: $yaw, pitch: $pitch, armed: armed,
                    drop: { id, at in drop(id, at: at, plot) },
                    more: { drawerOpen = true },
                    showPop: !drawerOpen,
                    say: say
                )
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.94)), removal: .opacity))
            } else {
                PlanCanvas(
                    plot: plot, selected: $selected, zoom: $zoom, popTab: $popTab, armed: armed,
                    drop: { id, at in drop(id, at: at, plot) },
                    more: { drawerOpen = true },
                    mode: planMode,
                    showPop: !drawerOpen,
                    say: say
                )
                .transition(.opacity)
            }
            HStack(alignment: .top) {
                Readout(plot: plot.wrappedValue, supply: store.supply)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 8) {
                    if !show3D { modeSwitch }
                    if zoom != 1 || (show3D && (yaw != IsoProjection.defaultYaw || pitch != IsoProjection.defaultPitch)) {
                        Button("Fit") {
                            withAnimation(.snappy) {
                                zoom = 1
                                yaw = IsoProjection.defaultYaw
                                pitch = IsoProjection.defaultPitch
                            }
                        }
                        .buttonStyle(ActionButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 12).padding(.top, 8)
            if let line = armed.map({ "Tap the plan to drop a \($0.shortName)" }) ?? toast {
                Text(line)
                    .font(.lwButton).foregroundStyle(armed == nil ? Palette.text : Palette.p0)
                    .padding(.horizontal, 12).frame(minHeight: 34)
                    .background(armed == nil ? Palette.p2 : Palette.gel, in: RoundedRectangle(cornerRadius: Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.rule))
                    .padding(.top, 48)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 8) {
                roundButton("arrow.uturn.backward", "Undo", enabled: history.canUndo) { step(back: true, plot) }
                roundButton("arrow.uturn.forward", "Redo", enabled: history.canRedo) { step(back: false, plot) }
            }
            .padding(12)
        }
        .overlay(alignment: .bottomTrailing) { viewSwitch.padding(12) }
        .animation(.snappy(duration: 0.35), value: show3D)
        .animation(.snappy(duration: 0.2), value: toast)
        .animation(.snappy(duration: 0.2), value: armed?.id)
        .task(id: toast) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            toast = nil
        }
    }

    private func roundButton(_ icon: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.text)
                .frame(width: 46, height: 46)
                .background(Palette.p2, in: Circle())
                .overlay(Circle().strokeBorder(Palette.ruleStrong))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private func say(_ line: String) { toast = line }

    /// Top down or 3D, bottom right of the plan.
    private var viewSwitch: some View {
        HStack(spacing: 2) {
            ForEach([false, true], id: \.self) { is3D in
                Button {
                    show3D = is3D
                    zoom = 1
                } label: {
                    Text(is3D ? "3D" : "Top").font(.lwButton)
                        .foregroundStyle(show3D == is3D ? Palette.p0 : Palette.quiet)
                        .padding(.horizontal, 14).frame(minHeight: 40)
                        .background(show3D == is3D ? Palette.gel : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Palette.p2, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.ruleStrong))
    }

    /// Sketch or Move, top right of the plan.
    private var modeSwitch: some View {
        HStack(spacing: 2) {
            ForEach([PlanMode.sketch, .move], id: \.self) { mode in
                Button { planMode = mode } label: {
                    Text(mode == .sketch ? "Sketch" : "Move").font(.lwButton)
                        .foregroundStyle(planMode == mode ? Palette.p0 : Palette.quiet)
                        .padding(.horizontal, 14).frame(minHeight: 36)
                        .background(planMode == mode ? Palette.gel : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Palette.p2, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.ruleStrong))
    }

    private func step(back: Bool, _ plot: Binding<Plot>) {
        let current = plot.wrappedValue
        guard let next = back ? history.undo(current) : history.redo(current) else { return }
        restoring = next != current
        selected = nil
        plot.wrappedValue = next
        say(back ? "Undone" : "Redone")
    }

    /// The editor's sheets and covers, shared by both layouts.
    private func sheets(_ content: some View, _ plot: Binding<Plot>) -> some View {
        content.sheet(isPresented: $showingLibrary) {
            LibrarySheet { lamp in
                add(lamp, to: plot)
                showingLibrary = false
            }
            .readableWidth()
            .presentationDetents([.medium, .large])
            .presentationBackground(Palette.p1)
        }
        .alert("Rename plot", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Scene or place", text: Binding(get: { renaming ?? "" }, set: { renaming = $0 }))
            Button("Save") {
                let name = (renaming ?? "").trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { plot.wrappedValue.name = name }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Tag this plot in AR?", isPresented: $confirmingAR, titleVisibility: .visible) {
            Button("Tag in AR") { showingAR = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your tags replace the lamps on this plan.")
        }
        .fullScreenCover(isPresented: $showingAR, onDismiss: {
            if sendAfterAR {
                sendAfterAR = false
                showingSend = true
            }
        }) {
            ARTagView(base: plot.wrappedValue) { tagged in
                if let tagged {
                    selected = nil
                    zoom = 1
                    plot.wrappedValue = tagged
                    sendAfterAR = true
                }
                showingAR = false
            }
        }
        .sheet(isPresented: $showingSpace) {
            SpaceSheet(plot: plot) { showingSpace = false }
                .readableWidth()
                .presentationDetents([.medium, .large])
                .presentationBackground(Palette.p1)
        }
        .sheet(isPresented: $showingSend) {
            SendSheet(
                plot: plot,
                supply: store.supply,
                backToPlan: { showingSend = false },
                allPlots: {
                    showingSend = false
                    close()
                },
                yaw: yaw,
                pitch: pitch
            )
            .readableWidth()
            .presentationDetents([.medium, .large])
            .presentationBackground(Palette.p1)
        }
    }

    /// Back, the plot's name and size, Add (a lamp, or the whole room in AR) and Send.
    private func topBar(_ binding: Binding<Plot>) -> some View {
        let plot = binding.wrappedValue
        return HStack(spacing: 10) {
            Button(action: close) {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.text)
                    .frame(width: 34, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("All plots")
            VStack(alignment: .leading, spacing: 1) {
                Button { renaming = plot.name } label: {
                    Text(plot.name).font(.lwTitle).foregroundStyle(Palette.text).lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rename \(plot.name)")
                Button { showingSpace = true } label: {
                    HStack(spacing: 4) {
                        Text(String(format: "%.1f × %.1f m", plot.roomWidth, plot.roomDepth))
                        if plot.floorPlan != nil { Text("· plan") }
                        Image(systemName: "chevron.down").font(.system(size: 9))
                    }
                    .font(.lwData).foregroundStyle(Palette.quiet)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Space size and floor plan")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("Add a lamp", systemImage: "plus") { showingLibrary = true }
                Button("Tag the room in AR", systemImage: "arkit") {
                    if plot.items.isEmpty { showingAR = true } else { confirmingAR = true }
                }
                if !plot.items.isEmpty {
                    Divider()
                    Button("Remove all lamps", systemImage: "trash", role: .destructive) { clearAll(binding) }
                }
            } label: {
                Text("Add")
                    .font(.lwButton).foregroundStyle(Palette.text)
                    .padding(.horizontal, 12).frame(minHeight: 34)
                    .background(Palette.p2, in: RoundedRectangle(cornerRadius: Radius.chip))
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Palette.rule))
            }
            Button("Send") { showingSend = true }
                .buttonStyle(ActionButtonStyle(primary: true))
        }
        .padding(.leading, 6).padding(.trailing, 16)
        .frame(minHeight: 52)
        .background(Palette.p1)
        .overlay(alignment: .bottom) { Divider().overlay(Palette.rule) }
    }

    /// One drawer under the plan, or down the right on its side. Closed: setups and the lamp count.
    /// Open: every lamp as a chip and the selected lamp's settings. Tap or drag the handle.
    private func drawer(_ plot: Binding<Plot>, wide: Bool) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: Radius.panel,
            bottomLeadingRadius: wide ? Radius.panel : 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: wide ? 0 : Radius.panel
        )
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                Button {
                    drawerOpen.toggle()
                    if !drawerOpen { selected = nil }
                } label: {
                    Capsule().fill(Palette.ruleStrong).frame(width: 36, height: 4)
                        .frame(maxWidth: .infinity, minHeight: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(drawerOpen ? "Close lamps" : "Open lamps")
                // With a lamp's settings open, the quick row steps aside; Swap on its card does the same job.
                if !(drawerOpen && selected != nil) {
                    QuickRow(picked: picked(plot.wrappedValue), armed: armed) { lamp in quick(lamp, plot) }
                        .padding(.bottom, 8)
                }
                HStack(spacing: 4) {
                    ForEach(Shot.allCases, id: \.self) { shot in
                        Chip(title: shot.title, selected: plot.wrappedValue.shot == shot) {
                            plot.wrappedValue.shot = shot
                        }
                    }
                    Spacer(minLength: 8)
                    lampsMenu(plot)
                }
                .padding(.horizontal, 16).padding(.bottom, 6)
            }
            // Only the handle and the setup row drag, so the lamp chips and sliders keep their own gestures.
            .gesture(DragGesture(minimumDistance: 12).onEnded { drag in
                let pull = wide ? -drag.translation.width : -drag.translation.height
                if pull > 30 { drawerOpen = true }
                if pull < -30 {
                    drawerOpen = false
                    selected = nil
                }
            })
            if drawerOpen {
                Rectangle().fill(Palette.rule).frame(height: 1)
                if plot.wrappedValue.items.isEmpty {
                    hint("No lamps yet. Tap Add to place one, or tag the room in AR.")
                } else {
                    rail(plot)
                    if selected == nil {
                        hint("Tap a lamp to change it. Press and hold one to remove it.")
                    }
                    inspector(plot)
                }
                if wide { Spacer(minLength: 0) }
            }
        }
        .frame(width: wide ? 360 : nil)
        .frame(maxWidth: wide ? nil : .infinity)
        .frame(maxHeight: wide && drawerOpen ? .infinity : nil, alignment: .top)
        .background(Palette.p1, in: shape)
        .overlay { shape.stroke(Palette.rule, lineWidth: 1) }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { drawerHeight = $0 }
        .padding(.top, wide && drawerOpen ? 8 : 0)
        .frame(maxHeight: .infinity, alignment: wide && drawerOpen ? .top : .bottom)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.lwBody).foregroundStyle(Palette.quiet)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
    }

    /// Every lamp on the plan as a numbered chip; tap to select.
    private func rail(_ plot: Binding<Plot>) -> some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(plot.wrappedValue.items.enumerated()), id: \.element.id) { n, item in
                        RailChip(number: n + 1, item: item, on: plot.wrappedValue.isOn(item), selected: item.id == selected) {
                            selected = selected == item.id ? nil : item.id
                        }
                        .contextMenu {
                            Button("Remove", systemImage: "minus.circle", role: .destructive) {
                                plot.wrappedValue.items.removeAll { $0.id == item.id }
                                if selected == item.id { selected = nil }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
            // Fade the edges so a cut-off chip reads as "scroll for more".
            .mask {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                    .init(color: .black, location: 0.9), .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
            }
            Rectangle().fill(Palette.rule).frame(height: 1)
        }
    }

    @ViewBuilder private func inspector(_ plot: Binding<Plot>) -> some View {
        if let id = selected, let i = plot.wrappedValue.items.firstIndex(where: { $0.id == id }) {
            Inspector(plot: plot, index: i, supply: store.supply, selected: $selected) {
                selected = nil
                drawerOpen = false
            }
        }
    }

    /// Lamp count, with all on, all off and remove all.
    private func lampsMenu(_ plot: Binding<Plot>) -> some View {
        let on = plot.wrappedValue.lightsOn.count
        return Menu {
            Button("Turn all on", systemImage: "lightbulb") { setAll(on: true, plot) }
            Button("Turn all off", systemImage: "lightbulb.slash") { setAll(on: false, plot) }
            Divider()
            Button("Remove all lamps", systemImage: "trash", role: .destructive) { clearAll(plot) }
                .disabled(plot.wrappedValue.items.isEmpty)
        } label: {
            HStack(spacing: 6) {
                Text("\(plot.wrappedValue.items.count) lamps · \(on) on").font(.lwData)
                Image(systemName: "ellipsis.circle").font(.system(size: 15))
            }
            .foregroundStyle(Palette.text)
            .frame(minHeight: 40)
        }
    }

    /// Every light in the current setup on or off at once. Grip frames are left alone.
    private func setAll(on: Bool, _ plot: Binding<Plot>) {
        let shot = plot.wrappedValue.shot
        for i in plot.wrappedValue.items.indices where plot.wrappedValue.items[i].lamp?.isLight == true {
            if on { plot.wrappedValue.items[i].offIn.remove(shot) } else { plot.wrappedValue.items[i].offIn.insert(shot) }
        }
    }

    /// Empties the plan. Undo brings it all back.
    private func clearAll(_ plot: Binding<Plot>) {
        let n = plot.wrappedValue.items.count
        selected = nil
        plot.wrappedValue.items = []
        say("Removed \(n) lamps · Undo bottom left")
    }

    private func picked(_ plot: Plot) -> Lamp? {
        plot.items.first { $0.id == selected }?.lamp
    }

    /// A quick lamp: swaps the picked lamp's head, or waits for a tap on the plan. Tap it again to put it back.
    private func quick(_ lamp: Lamp, _ plot: Binding<Plot>) {
        if let id = selected, let i = plot.wrappedValue.items.firstIndex(where: { $0.id == id }) {
            if plot.wrappedValue.items[i].lampID != lamp.id {
                plot.wrappedValue.items[i].swapHead(to: lamp)
                say("Swapped to \(lamp.shortName)")
            }
        } else {
            armed = armed?.id == lamp.id ? nil : lamp
        }
    }

    /// Puts a lamp down where you tapped or let go, on the 25 cm grid and clear of the walls, aimed at the talent.
    private func drop(_ id: String, at p: Point2, _ plot: Binding<Plot>) {
        guard let lamp = LampLibrary.lamp(id) else { return }
        let r = plot.wrappedValue
        let g = { (v: Double) in (v * 4).rounded() / 4 }
        let at = Point2(x: min(r.roomWidth - 0.3, max(0.3, g(p.x))), y: min(r.roomDepth - 0.3, max(0.3, g(p.y))))
        plot.wrappedValue.items.append(newItem(lamp, at: at, in: r))
        Sketch.Shape.remember(lamp)
        armed = nil
        say("Dropped \(lamp.shortName)")
    }

    private func newItem(_ lamp: Lamp, at p: Point2, in plot: Plot) -> PlacedLamp {
        var item = Starter.place(lamp.id, p.x, p.y, lamp.isLight ? .key : .diff, nil, nil, [])
        let aim = p.bearing(to: plot.talent)
        item.angle = lamp.isGrip ? aim + 90 : aim
        if plot.items.contains(where: { $0.role == .key }) && lamp.isLight { item.role = .fill }
        if let m = LastModifier.get(lamp.id), lamp.modifiers.contains(m) { item.modifier = m }
        return item
    }

    /// Drops a new lamp up and to the left of the talent, aimed at them, and selects it.
    private func add(_ lamp: Lamp, to plot: Binding<Plot>) {
        let t = plot.wrappedValue.talent
        let step = Double(plot.wrappedValue.items.count % 5) * 0.4
        let x = max(0.3, t.x - 1.6 + step), y = max(0.3, t.y - 1.6)
        let item = newItem(lamp, at: Point2(x: x, y: y), in: plot.wrappedValue)
        plot.wrappedValue.items.append(item)
        selected = item.id
    }
}

/// Key at talent, key to fill, and load against the circuits, on one line. Ink only.
struct Readout: View {
    let plot: Plot
    let supply: LightMath.Supply

    var body: some View {
        let load = LightMath.load(plot, supply: supply)
        let capacity = Double(max(1, LightMath.circuits(plot, supply: supply).count)) * supply.circuitAmps
        let key = Int(LightMath.keyLux(plot))
        HStack(spacing: 10) {
            Text("\(key.formatted()) lx").contentTransition(.numericText())
            Text(LightMath.ratioText(plot)).foregroundStyle(Palette.quiet)
            Text(String(format: "%.1f/%.0f A", load.amps, capacity)).contentTransition(.numericText())
        }
        .font(.lwData).foregroundStyle(Palette.text).lineLimit(1)
        .padding(.horizontal, 10).frame(minHeight: 30)
        .background(Palette.p1.opacity(0.9), in: RoundedRectangle(cornerRadius: Radius.chip))
        .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Palette.rule))
        .animation(.easeOut(duration: 0.4), value: load.amps)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Key \(key) lux, ratio \(LightMath.ratioText(plot)), load \(String(format: "%.1f", load.amps)) of \(Int(capacity)) amps")
    }
}

struct RailChip: View {
    let number: Int
    let item: PlacedLamp
    let on: Bool
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(on ? Palette.gel : .clear)
                    .strokeBorder(on ? Palette.gel : Palette.quiet, lineWidth: 1)
                    .frame(width: 7, height: 7)
                Text(String(format: "%02d", number)).font(.lwData)
                Text(item.lamp?.shortName ?? "?").font(.lwChip)
            }
            .foregroundStyle(selected ? Palette.text : Palette.quiet)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(selected ? Palette.p2 : Palette.p0, in: RoundedRectangle(cornerRadius: Radius.chip))
            .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Palette.rule))
            .overlay(alignment: .leading) {
                if selected { Rectangle().fill(Palette.gel).frame(width: 2).padding(.vertical, 1) }
            }
        }
        .buttonStyle(.plain)
    }
}
