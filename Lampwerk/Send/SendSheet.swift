import SwiftUI

/// Send a plot: gaffer sheet, plan image or a text list through the share sheet,
/// plus the ways back out (to the plan, or to all plots).
struct SendSheet: View {
    @Binding var plot: Plot
    let supply: LightMath.Supply
    var backToPlan: () -> Void
    var allPlots: () -> Void

    @State private var pdf: URL?
    @State private var image: URL?
    @State private var preparing = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Caps("Send plot")
                Spacer()
                Button("Close", action: backToPlan).buttonStyle(ActionButtonStyle())
            }
            .padding(.horizontal, 16).frame(minHeight: 52)
            Divider().overlay(Palette.rule)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 14) {
                        PlanThumbnail(plot: plot).frame(width: 84, height: 84)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plot.name).font(.lwTitle).foregroundStyle(Palette.text)
                            Text("\(plot.items.count) lamps · saved on this phone").font(.lwData).foregroundStyle(Palette.quiet)
                        }
                    }
                    .padding(.vertical, 14)

                    names

                    Caps("Send as").padding(.top, 18).padding(.bottom, 2)
                    Divider().overlay(Palette.rule)
                    option("Gaffer sheet", "A4 PDF: plan, gear list, heights and power.", url: pdf)
                    option("Plan image", "The plan as a picture, good for WhatsApp.", url: image)
                    textOption
                    liveLink
                }
                .padding(.horizontal, 16)
            }

            HStack {
                Button("All plots", action: allPlots).buttonStyle(ActionButtonStyle())
                Spacer()
                Button("Back to plan", action: backToPlan).buttonStyle(ActionButtonStyle(primary: true))
            }
            .padding(.horizontal, 16).frame(minHeight: 60)
            .overlay(alignment: .top) { Divider().overlay(Palette.rule) }
        }
        .background(Palette.p1)
        // Remake the files whenever a name changes, once typing settles.
        .task(id: plot) {
            preparing = true
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            pdf = Export.gafferSheetPDF(plot, supply: supply)
            image = Export.planImage(plot)
            preparing = false
        }
    }

    /// Names go out on the sheet, the image and the list, so they're checked here first.
    private var names: some View {
        VStack(alignment: .leading, spacing: 8) {
            Caps("Check the names").padding(.top, 4)
            NameField(placeholder: "Scene or place", text: Binding(
                get: { plot.name },
                set: { plot.name = $0 }
            ))
            ForEach(Array(plot.items.enumerated()), id: \.element.id) { n, item in
                HStack(spacing: 10) {
                    Text(String(format: "%02d", n + 1)).font(.lwData).foregroundStyle(Palette.quiet).frame(width: 22, alignment: .leading)
                    NameField(placeholder: item.role.title, text: Binding(
                        get: { plot.items[n].name ?? "" },
                        set: { plot.items[n].name = $0.isEmpty ? nil : $0 }
                    ))
                    Text(item.lamp?.shortName ?? "").font(.lwChip).foregroundStyle(Palette.quiet).frame(width: 74, alignment: .trailing).lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func option(_ title: String, _ detail: String, url: URL?) -> some View {
        if let url, !preparing {
            ShareLink(item: url, subject: Text(plot.name), message: Text(plot.name)) {
                row(title, detail, trailing: "Send")
            }
            .buttonStyle(.plain)
        } else {
            row(title, preparing ? "Preparing…" : "Couldn't make this file. Try again.", trailing: "")
        }
    }

    private var textOption: some View {
        ShareLink(item: Export.text(plot, supply: supply)) {
            row("Text list", "One line per lamp, numbered as on the plan.", trailing: "Send")
        }
        .buttonStyle(.plain)
    }

    private var liveLink: some View {
        row("Live link", "A web link the gaffer or DP opens with no app, updating as you plot. Coming with Pro.", trailing: "Soon")
            .opacity(0.6)
    }

    private func row(_ title: String, _ detail: String, trailing: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.lwBody).foregroundStyle(Palette.text)
                Text(detail).font(.lwChip).foregroundStyle(Palette.quiet).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !trailing.isEmpty { Caps(trailing) }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Divider().overlay(Palette.rule) }
    }
}
