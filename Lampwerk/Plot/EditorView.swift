import SwiftUI

/// One plot: setups along the top, the plan with a live readout, lamps and the inspector below.
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

    var body: some View {
        Group {
            if let binding = Binding($plot) {
                editor(binding)
            } else {
                Palette.p0
            }
        }
        .onAppear { plot = store.plots.first { $0.id == plotID } }
        .onChange(of: plot) { _, new in if let new { store.update(new) } }
    }

    private func editor(_ plot: Binding<Plot>) -> some View {
        VStack(spacing: 0) {
            topBar(plot.wrappedValue)
            shots(plot)
            ZStack(alignment: .top) {
                PlanCanvas(plot: plot, selected: $selected, zoom: $zoom)
                Readout(plot: plot.wrappedValue, supply: store.supply)
                    .padding(.horizontal, 12).padding(.top, 8)
                if zoom != 1 {
                    Button("Fit") { withAnimation(.snappy) { zoom = 1 } }
                        .buttonStyle(ActionButtonStyle())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 16).padding(.top, 66)
                }
            }
            .frame(maxHeight: .infinity)
            .clipped()
            bottom(plot)
        }
        .background(Palette.p0)
        .sheet(isPresented: $showingLibrary) {
            LibrarySheet { lamp in
                add(lamp, to: plot)
                showingLibrary = false
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Palette.p1)
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
        .sheet(isPresented: $showingSend) {
            SendSheet(
                plot: plot.wrappedValue,
                supply: store.supply,
                backToPlan: { showingSend = false },
                allPlots: {
                    showingSend = false
                    close()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(Palette.p1)
        }
    }

    private func topBar(_ plot: Plot) -> some View {
        HStack(spacing: 12) {
            Button("Plots", action: close).buttonStyle(ActionButtonStyle())
            VStack(spacing: 1) {
                Text(plot.name).font(.lwTitle).foregroundStyle(Palette.text).lineLimit(1)
                Text(String(format: "%.1f × %.1f m", plot.roomWidth, plot.roomDepth))
                    .font(.lwData).foregroundStyle(Palette.quiet)
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                Button("AR") {
                    if plot.items.isEmpty { showingAR = true } else { confirmingAR = true }
                }
                .buttonStyle(ActionButtonStyle())
                Button("Send") { showingSend = true }
                    .buttonStyle(ActionButtonStyle(primary: true))
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .background(Palette.p1)
        .overlay(alignment: .bottom) { Divider().overlay(Palette.rule) }
    }

    private func shots(_ plot: Binding<Plot>) -> some View {
        HStack(spacing: 4) {
            ForEach(Shot.allCases, id: \.self) { shot in
                Chip(title: shot.title, selected: plot.wrappedValue.shot == shot) {
                    plot.wrappedValue.shot = shot
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Palette.p1)
        .overlay(alignment: .bottom) { Divider().overlay(Palette.rule) }
    }

    private func bottom(_ plot: Binding<Plot>) -> some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(plot.wrappedValue.items.enumerated()), id: \.element.id) { n, item in
                        RailChip(number: n + 1, item: item, on: plot.wrappedValue.isOn(item), selected: item.id == selected) {
                            selected = selected == item.id ? nil : item.id
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
            Divider().overlay(Palette.rule)

            if let id = selected, let i = plot.wrappedValue.items.firstIndex(where: { $0.id == id }) {
                Inspector(plot: plot, index: i, supply: store.supply, selected: $selected)
            }

            HStack {
                let on = plot.wrappedValue.lightsOn.count
                Text("\(plot.wrappedValue.items.count) items · \(on) on").font(.lwData).foregroundStyle(Palette.quiet)
                Spacer()
                Button("Add lamp") { showingLibrary = true }.buttonStyle(ActionButtonStyle(primary: true))
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
        }
        .background(Palette.p1)
        .overlay(alignment: .top) { Divider().overlay(Palette.rule) }
        .animation(.snappy(duration: 0.25), value: selected)
    }

    /// Drops a new lamp up and to the left of the talent, aimed at them, and selects it.
    private func add(_ lamp: Lamp, to plot: Binding<Plot>) {
        let t = plot.wrappedValue.talent
        let step = Double(plot.wrappedValue.items.count % 5) * 0.4
        let x = max(0.3, t.x - 1.6 + step), y = max(0.3, t.y - 1.6)
        var item = Starter.place(lamp.id, x, y, lamp.isLight ? .key : .fill, nil, nil, [])
        let aim = Point2(x: x, y: y).bearing(to: t)
        item.angle = lamp.isGrip ? aim + 90 : aim
        if plot.wrappedValue.items.contains(where: { $0.role == .key }) && lamp.isLight { item.role = .fill }
        plot.wrappedValue.items.append(item)
        selected = item.id
    }
}

/// Key at talent, key to fill, load against the circuits. Ink only.
struct Readout: View {
    let plot: Plot
    let supply: LightMath.Supply

    var body: some View {
        let load = LightMath.load(plot, supply: supply)
        let capacity = Double(max(1, LightMath.circuits(plot, supply: supply).count)) * LightMath.circuitAmps
        HStack(spacing: 6) {
            cell("Key") {
                Text("\(Int(LightMath.keyLux(plot)).formatted()) lx")
                    .contentTransition(.numericText())
            }
            cell("Ratio") { Text(LightMath.ratioText(plot)) }
            cell("Load") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "%.1f of %.0f A", load.amps, capacity)).contentTransition(.numericText())
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.p3)
                            Capsule().fill(Palette.text).frame(width: geo.size.width * min(1, load.amps / capacity))
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
        .animation(.easeOut(duration: 0.4), value: load.amps)
        .allowsHitTesting(false)
    }

    private func cell<V: View>(_ title: String, @ViewBuilder _ value: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Caps(title)
            value().font(.lwReadout).foregroundStyle(Palette.text).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Palette.p1.opacity(0.9), in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.rule))
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
