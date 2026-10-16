import SwiftUI

/// Files to send from a plot: the A4 gaffer sheet as a PDF, the plan as an image, and a plain text list.
@MainActor
enum Export {
    static func gafferSheetPDF(_ plot: Plot, supply: LightMath.Supply) -> URL? {
        let url = folder().appending(path: "\(fileName(plot))-gaffer-sheet.pdf")
        let renderer = ImageRenderer(content: GafferSheet(plot: plot, supply: supply))
        var written = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            written = true
        }
        return written ? url : nil
    }

    static func planImage(_ plot: Plot) -> URL? {
        let url = folder().appending(path: "\(fileName(plot))-plan.png")
        let renderer = ImageRenderer(content: PlanImage(plot: plot))
        renderer.scale = 2
        guard let data = renderer.uiImage?.pngData() else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// For a quick WhatsApp: one line per head, numbered as on the plan.
    static func text(_ plot: Plot, supply: LightMath.Supply) -> String {
        var lines = ["\(plot.name) · \(plot.items.count) lamps"]
        for (n, item) in plot.items.enumerated() {
            guard let lamp = item.lamp else { continue }
            var parts = [String(format: "%02d", n + 1), item.role.title, lamp.fullName]
            if item.modifier != "None" { parts.append(item.modifier.lowercased()) }
            if item.gel != "None" { parts.append(item.gel) }
            if let h = item.height { parts.append(String(format: "head %.1f m", h)) }
            parts.append(String(format: "%.1f m to talent", item.position.distance(to: plot.talent)))
            lines.append(parts.joined(separator: " · "))
        }
        let circuits = LightMath.circuits(plot, supply: supply)
        let amps = circuits.reduce(0) { $0 + $1.amps }
        if amps > 0 { lines.append(String(format: "Power: %.1f A on %d × 16 A", amps, circuits.count)) }
        lines.append("Made with Lampwerk. Figures approximate.")
        return lines.joined(separator: "\n")
    }

    private static func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "send", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func fileName(_ plot: Plot) -> String {
        let allowed = CharacterSet.alphanumerics
        let words = plot.name.lowercased().components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
        return words.isEmpty ? "plot" : words.joined(separator: "-")
    }
}

/// The plan on its own, dark, sized for a phone screen.
struct PlanImage: View {
    let plot: Plot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Lockup(height: 22)
                Spacer()
                Text(plot.name).font(.lwTitle).foregroundStyle(Palette.text)
            }
            Canvas { ctx, size in
                let v = PlanViewport.fit(plot, in: size, margin: 1)
                PlanDrawing.draw(plot, in: ctx, viewport: v, options: .init())
            }
            HStack {
                Text("\(plot.items.count) lamps").font(.lwData).foregroundStyle(Palette.quiet)
                Spacer()
                Text("Figures approximate").font(.lwData).foregroundStyle(Palette.quiet)
            }
        }
        .padding(28)
        .frame(width: 540, height: 675)
        .background(Palette.p0)
    }
}

/// A4 portrait, ink on paper, no gel. The wordmark heads it and the mark signs it.
struct GafferSheet: View {
    let plot: Plot
    let supply: LightMath.Supply

    private let ink = Palette.ink
    private var quiet: Color { Palette.ink.opacity(0.5) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Image("Wordmark").resizable().scaledToFit().frame(height: 18).foregroundStyle(ink)
                Spacer()
                Text(plot.name).font(Fonts.mono(11, .medium)).foregroundStyle(ink)
            }
            Rectangle().fill(ink).frame(height: 1)
            HStack {
                Text(plot.updated.formatted(date: .abbreviated, time: .omitted))
                Spacer()
                Text(String(format: "Room %.1f × %.1f m", plot.roomWidth, plot.roomDepth))
            }
            .font(Fonts.mono(9, .regular)).foregroundStyle(quiet)

            Canvas { ctx, size in
                let v = PlanViewport.fit(plot, in: size, margin: 0.8)
                PlanDrawing.draw(plot, in: ctx, viewport: v, options: .init(paper: true))
            }
            .frame(height: 360)

            table
            power

            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                Text("Figures approximate. Check tie-ins and generators with your spark.")
                    .font(Fonts.mono(8, .regular)).foregroundStyle(quiet)
                Spacer()
                Image("Mark").resizable().scaledToFit().frame(height: 22).foregroundStyle(ink)
            }
        }
        .padding(36)
        .frame(width: 595, height: 842)
        .background(Palette.paper)
    }

    private var table: some View {
        VStack(spacing: 0) {
            row("#", "Head", "Role", "High", "To talent", "A", header: true)
            ForEach(Array(plot.items.enumerated()), id: \.element.id) { n, item in
                let lamp = item.lamp
                let mod = item.modifier == "None" ? "" : ", " + item.modifier.lowercased()
                row(
                    String(format: "%02d", n + 1),
                    (lamp?.fullName ?? "?") + mod,
                    item.role.title,
                    item.height.map { String(format: "%.1f", $0) } ?? "–",
                    String(format: "%.1f", item.position.distance(to: plot.talent)),
                    (lamp?.isLight ?? false) ? String(format: "%.1f", LightMath.amps(item, supply: supply)) : "–"
                )
            }
        }
    }

    private var power: some View {
        let circuits = LightMath.circuits(plot, supply: supply)
        let amps = circuits.reduce(0) { $0 + $1.amps }
        return HStack {
            Text(String(format: "Full load %.1f A", amps))
            Spacer()
            Text(circuits.isEmpty ? "No circuits" : "\(circuits.count) × 16 A circuits")
        }
        .font(Fonts.mono(9, .regular)).foregroundStyle(ink)
    }

    private func row(_ a: String, _ b: String, _ c: String, _ d: String, _ e: String, _ f: String, header: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(a).frame(width: 22, alignment: .leading)
            Text(b).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            Text(c).frame(width: 60, alignment: .leading)
            Text(d).frame(width: 36, alignment: .trailing)
            Text(e).frame(width: 56, alignment: .trailing)
            Text(f).frame(width: 34, alignment: .trailing)
        }
        .font(Fonts.mono(9, .regular))
        .foregroundStyle(header ? quiet : ink)
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.ink.opacity(0.12)).frame(height: 0.5) }
    }
}
