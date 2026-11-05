import SwiftUI
import UniformTypeIdentifiers

/// The heads a gaffer reaches for most, one tap away under the plan.
enum QuickLamps {
    static let ids = ["a600", "a1200", "m18", "forza", "s60", "s30", "gem", "titan", "helios", "china", "f8d", "floppy"]
    static var all: [Lamp] { ids.compactMap(LampLibrary.lamp) }

    /// What you'd most likely swap a head for: the same group first, then other heads of the same sort. Six at most.
    static func swaps(for lamp: Lamp) -> [Lamp] {
        let pool = all + LampLibrary.all.filter { !ids.contains($0.id) }
        let same = pool.filter { $0.group == lamp.group }
        let rest = pool.filter { $0.group != lamp.group && $0.isGrip == lamp.isGrip }
        var out: [Lamp] = []
        for l in same + rest where !out.contains(where: { $0.id == l.id }) { out.append(l) }
        return Array(out.prefix(6))
    }

    /// One line under the name on a chip.
    static func detail(_ lamp: Lamp) -> String {
        lamp.isGrip ? "frame" : "\(Int(lamp.watts)) W"
    }
}

/// Each head comes back the way you last rigged it: a 600 you always put a softbox on arrives with a softbox.
enum LastModifier {
    private static let key = "lastModifier"

    static func get(_ lampID: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: String])?[lampID]
    }

    static func set(_ lampID: String, _ modifier: String) {
        var all = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
        all[lampID] = modifier
        UserDefaults.standard.set(all, forKey: key)
    }
}

extension PlacedLamp {
    /// Swaps the head, keeping where it stands, its aim and its setups. A modifier the new head can't take goes.
    mutating func swapHead(to lamp: Lamp) {
        let wasGrip = self.lamp?.isGrip ?? false
        lampID = lamp.id
        Sketch.Shape.remember(lamp)
        if !lamp.modifiers.contains(modifier) { modifier = LastModifier.get(lamp.id) ?? lamp.modifiers[0] }
        if let range = lamp.cct { cct = min(range.upperBound, max(range.lowerBound, cct)) }
        if lamp.isGrip != wasGrip {
            angle += lamp.isGrip ? 90 : -90
            role = lamp.isGrip ? .diff : .fill
        }
    }
}

/// The row of quick lamps. Tap one to drop it with your next tap on the plan, or press and drag it straight on.
/// With a lamp picked, tapping one swaps it in.
struct QuickRow: View {
    let picked: Lamp?
    let armed: Lamp?
    var tap: (Lamp) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(QuickLamps.all) { lamp in
                    let on = picked.map { $0.id == lamp.id } ?? (armed?.id == lamp.id)
                    Button { tap(lamp) } label: { chip(lamp, on: on) }
                        .buttonStyle(.plain)
                        .draggable(lamp.id) { chip(lamp, on: true) }
                        .accessibilityLabel(picked == nil ? "Drop a \(lamp.shortName)" : "Swap for a \(lamp.shortName)")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ lamp: Lamp, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(lamp.shortName).font(.lwButton).foregroundStyle(Palette.text).lineLimit(1)
            Text(QuickLamps.detail(lamp)).font(.lwData).foregroundStyle(Palette.quiet)
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 64, minHeight: 46, alignment: .leading)
        .background(Palette.p0, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(on ? Palette.gel : Palette.rule, lineWidth: on ? 1.5 : 1))
    }
}

/// The small card over a tapped lamp, the only thing a tap opens: on or off, its modifier, swap the head,
/// remove, and More for everything else. One row, so it never covers the plan.
struct LampPop: View {
    enum Tab { case mods, swap }

    @Binding var plot: Plot
    let id: PlacedLamp.ID
    @Binding var tab: Tab
    var more: () -> Void
    /// In 3D: raise and lower the head through stand heights.
    var showHeight = false

    var body: some View {
        if let i = plot.items.firstIndex(where: { $0.id == id }), let lamp = plot.items[i].lamp {
            let item = plot.items[i]
            HStack(spacing: 4) {
                Text(String(format: "%02d ", i + 1) + lamp.shortName)
                    .font(.lwButton).foregroundStyle(Palette.text).lineLimit(1).padding(.horizontal, 6)
                if lamp.isLight {
                    button(plot.isOn(item) ? "On" : "Off", lit: plot.isOn(item)) {
                        if plot.isOn(item) { plot.items[i].offIn.insert(plot.shot) } else { plot.items[i].offIn.remove(plot.shot) }
                    }
                }
                if showHeight && lamp.isLight {
                    let z = IsoCanvas.height(item)
                    Menu {
                        ForEach(IsoCanvas.stands.reversed(), id: \.self) { h in
                            Button(String(format: "%.1f m", h)) { plot.items[i].height = h }
                        }
                    } label: { label(String(format: "%.1f m", z)) }
                }
                if lamp.modifiers.count > 1 {
                    Menu {
                        Picker(lamp.kind == .diff ? "Diff" : "Modifier", selection: Binding(
                            get: { plot.items[i].modifier },
                            set: { plot.items[i].modifier = $0; LastModifier.set(lamp.id, $0) }
                        )) {
                            ForEach(lamp.modifiers, id: \.self) { m in Text(m == "None" ? "Bare" : m).tag(m) }
                        }
                    } label: { label(item.modifier == "None" ? "Bare" : short(item.modifier)) }
                }
                Menu {
                    ForEach(QuickLamps.swaps(for: lamp).filter { $0.id != lamp.id }) { l in
                        Button(l.fullName) { plot.items[i].swapHead(to: l) }
                    }
                } label: { label("Swap") }
                Button { plot.items.remove(at: i) } label: {
                    Image(systemName: "trash").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.text)
                        .frame(width: 36, height: 36)
                        .background(Palette.p3, in: RoundedRectangle(cornerRadius: Radius.chip))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove")
                button("More") { more() }
            }
            .padding(4)
            .background(Palette.p2, in: RoundedRectangle(cornerRadius: Radius.panel))
            .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(Palette.ruleStrong))
            .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
            .fixedSize()
        }
    }

    /// "Chimera, medium" reads "Chimera" on the card; the full name is in the menu.
    private func short(_ m: String) -> String { String(m.split(separator: ",").first ?? Substring(m)) }

    private func label(_ title: String) -> some View {
        HStack(spacing: 3) {
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
        }
        .font(.lwButton).foregroundStyle(Palette.text)
        .padding(.horizontal, 10).frame(minHeight: 36)
        .background(Palette.p3, in: RoundedRectangle(cornerRadius: Radius.chip))
    }

    private func button(_ title: String, lit: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.lwButton)
                .foregroundStyle(lit ? Palette.p0 : Palette.text)
                .padding(.horizontal, 10).frame(minHeight: 36)
                .background(lit ? Palette.gel : Palette.p3, in: RoundedRectangle(cornerRadius: Radius.chip))
        }
        .buttonStyle(.plain)
    }
}

/// Undo and redo for everything on the plot. Changes that land close together, like every step of a drag, count as one.
struct PlotHistory {
    private(set) var past: [Plot] = []
    private(set) var future: [Plot] = []
    private var lastEdit = Date.distantPast

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    var count: Int { past.count }

    mutating func record(_ old: Plot) {
        let now = Date()
        if now.timeIntervalSince(lastEdit) > 0.6 {
            past.append(old)
            if past.count > 100 { past.removeFirst() }
            future.removeAll()
        }
        lastEdit = now
    }

    mutating func undo(_ current: Plot) -> Plot? {
        guard let p = past.popLast() else { return nil }
        future.append(current)
        lastEdit = .distantPast
        return p
    }

    mutating func redo(_ current: Plot) -> Plot? {
        guard let f = future.popLast() else { return nil }
        past.append(current)
        lastEdit = .distantPast
        return f
    }
}
