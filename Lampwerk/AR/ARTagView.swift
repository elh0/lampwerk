import SwiftUI
import simd

/// Tag lamps on the floor like the Measure app: talent mark, camera, then each head.
/// Done turns the tags into this plot's layout.
struct ARTagView: View {
    let base: Plot
    var finish: (Plot?) -> Void

    @State private var model = ARTagModel()
    /// Compact height is the phone on its side: the shutter moves to the right edge like the Camera app.
    @Environment(\.verticalSizeClass) private var verticalSize
    /// A plot with a floor plan starts by picking two spots on it to line AR up with.
    @State private var liningUp: Bool

    init(base: Plot, finish: @escaping (Plot?) -> Void) {
        self.base = base
        self.finish = finish
        _liningUp = State(initialValue: base.floorPlan != nil)
    }

    var body: some View {
        if liningUp {
            LineUpView(plot: base, start: { a, b in
                model.lineUp(a, b)
                liningUp = false
            }, skip: { liningUp = false }, cancel: { finish(nil) })
            .preferredColorScheme(.dark)
        } else {
            tagging
        }
    }

    private var tagging: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ARContainer(model: model).ignoresSafeArea()
            labels
            if verticalSize == .compact {
                VStack(spacing: 0) {
                    topBar
                    hint.padding(.top, 6)
                    Spacer()
                }
                HStack(alignment: .bottom, spacing: 0) {
                    sidePanel
                    Spacer(minLength: 12)
                    VStack(spacing: 14) {
                        shutter
                        Button("Undo") { model.undo() }.buttonStyle(ActionButtonStyle())
                    }
                    .padding(.trailing, 16).padding(.bottom, 12)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                VStack(spacing: 0) {
                    topBar
                    hint.padding(.top, 10)
                    Spacer()
                    bottom
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }

    // MARK: Top

    private var topBar: some View {
        HStack {
            Button("Cancel") { finish(nil) }.buttonStyle(ActionButtonStyle())
            Spacer()
            VStack(spacing: 1) {
                Text(base.name).font(.lwTitle).foregroundStyle(Palette.text).lineLimit(1)
                Text(stepTitle).font(.lwData).foregroundStyle(Palette.quiet)
            }
            Spacer()
            Button("Done") { finish(model.plot(from: base)) }
                .buttonStyle(ActionButtonStyle(primary: true))
                .disabled(!model.canFinish)
                .opacity(model.canFinish ? 1 : 0.4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(LinearGradient(colors: [Palette.p0.opacity(0.85), Palette.p0.opacity(0)], startPoint: .top, endPoint: .bottom))
    }

    private var stepTitle: String {
        switch model.step {
        case .refA: "Line up · spot A"
        case .refB: "Line up · spot B"
        case .talent: "1 of 3 · talent mark"
        case .camera: "2 of 3 · camera"
        case .lamps: "3 of 3 · lamps (\(model.tags.count))"
        }
    }

    private var hint: some View {
        Text(model.hint)
            .font(.lwBody)
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Palette.p0.opacity(0.8), in: RoundedRectangle(cornerRadius: Radius.chip))
            .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Palette.ruleStrong))
            .animation(.easeOut(duration: 0.2), value: model.hint)
    }

    // MARK: Labels over the camera

    private var labels: some View {
        ZStack {
            if let p = model.screen["refA"] { tagLabel("A", at: p) }
            if let p = model.screen["refB"] { tagLabel("B", at: p) }
            if let p = model.screen["talent"] { tagLabel("Talent", at: p) }
            if let p = model.screen["camera"] { tagLabel("Camera", at: p) }
            ForEach(Array(model.tags.enumerated()), id: \.element.id) { n, tag in
                if let p = model.screen[tag.id.uuidString] {
                    Button {
                        model.selected = model.selected == tag.id ? nil : tag.id
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(n + 1)").font(.lwData)
                            Text(tag.name.isEmpty ? tag.role.title : tag.name).font(.lwChip)
                        }
                        .foregroundStyle(model.selected == tag.id ? Palette.p0 : Palette.text)
                        .padding(.horizontal, 8).frame(minHeight: 26)
                        .background(model.selected == tag.id ? Palette.gel : Palette.p0.opacity(0.8), in: RoundedRectangle(cornerRadius: Radius.chip))
                    }
                    .buttonStyle(.plain)
                    .position(p)
                }
            }
            if let p = model.screen["reticle"], let d = model.reticleToTalent, model.selected == nil {
                Text(String(format: "%.1f m to talent", d))
                    .font(.lwData).foregroundStyle(Palette.text)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Palette.p0.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                    .position(x: p.x, y: p.y + 30)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }

    private func tagLabel(_ text: String, at p: CGPoint) -> some View {
        Text(text.uppercased())
            .font(.lwLabel).tracking(0.9)
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Palette.p0.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
            .position(p)
            .allowsHitTesting(false)
    }

    // MARK: Bottom

    private var bottom: some View {
        VStack(spacing: 0) {
            if let id = model.selected, let i = model.tags.firstIndex(where: { $0.id == id }) {
                inspector(i)
            } else if model.step == .lamps {
                rail
            }
            HStack {
                Button("Undo") { model.undo() }
                    .buttonStyle(ActionButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                shutter
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8).padding(.bottom, 12)
        }
        .background(LinearGradient(colors: [Palette.p0.opacity(0), Palette.p0.opacity(0.92)], startPoint: .top, endPoint: .init(x: 0.5, y: 0.25)))
    }

    private var shutter: some View {
        Button { model.tag() } label: {
            ZStack {
                Circle().strokeBorder(Palette.text, lineWidth: 2.5).frame(width: 70, height: 70)
                Image(systemName: "plus").font(.system(size: 26, weight: .light)).foregroundStyle(Palette.text)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.reticle == nil)
        .opacity(model.reticle == nil ? 0.35 : 1)
        .sensoryFeedback(.impact(weight: .light), trigger: model.revision)
        .accessibilityLabel("Tag this point")
    }

    /// On its side: the selected tag or the lamp rail sits bottom left, clear of the reticle in the middle.
    @ViewBuilder private var sidePanel: some View {
        if let id = model.selected, let i = model.tags.firstIndex(where: { $0.id == id }) {
            inspector(i)
                .frame(width: 380)
                .padding(.bottom, 12)
        } else if model.step == .lamps {
            rail
                .frame(maxWidth: 360)
                .background(Palette.p0.opacity(0.75), in: RoundedRectangle(cornerRadius: Radius.panel))
                .padding(.leading, 12).padding(.bottom, 16)
        }
    }

    private var rail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(ARTagModel.rail, id: \.self) { id in
                    Chip(title: LampLibrary.lamp(id)?.shortName ?? id, selected: model.choice == id) {
                        model.choice = id
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
        }
    }

    private func inspector(_ i: Int) -> some View {
        let tag = model.tags[i]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(i + 1) · \(tag.lamp?.fullName ?? "")").font(.lwTitle).foregroundStyle(Palette.text)
                Spacer()
                if let t = model.talent {
                    let flat = simd_distance(tag.floor, t)
                    let d = (flat * flat + (tag.height - 1.5) * (tag.height - 1.5)).squareRoot()
                    Text(String(format: "%.1f m to talent", d)).font(.lwData).foregroundStyle(Palette.quiet)
                }
            }
            NameField(placeholder: tag.role.title, text: Binding(
                get: { model.tags[i].name },
                set: { model.tags[i].name = $0 }
            ))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Role.allCases, id: \.self) { role in
                        Chip(title: role.title, selected: tag.role == role) {
                            model.tags[i].role = role
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Caps("Head")
                Slider(value: Binding(
                    get: { Double(model.tags[i].height) },
                    set: { model.tags[i].height = Float($0); model.revision += 1 }
                ), in: 0.3...4.5, step: 0.05)
                .tint(Palette.text)
                Text(String(format: "%.2f m", tag.height)).font(.lwValue).foregroundStyle(Palette.text).frame(width: 64, alignment: .trailing)
            }
            HStack {
                Button("Delete") { model.delete(tag.id) }.buttonStyle(ActionButtonStyle())
                Spacer()
                Button("Close") { model.selected = nil }.buttonStyle(ActionButtonStyle())
            }
        }
        .padding(12)
        .background(Palette.p1.opacity(0.95), in: RoundedRectangle(cornerRadius: Radius.panel))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(Palette.rule))
        .padding(.horizontal, 12)
    }
}

