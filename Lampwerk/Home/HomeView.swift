import SwiftUI

/// The plots on this phone, newest first.
struct HomeView: View {
    @Environment(PlotStore.self) private var store
    var open: (Plot.ID) -> Void
    @State private var showingNew = false
    @State private var beta = false
    @State private var offerClaim = false
    @AppStorage(FoundingTester.dismissedKey) private var cardDismissed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Lockup()
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            Divider().overlay(Palette.rule)
            HStack {
                Caps("Plots")
                Spacer()
                Text("(\(store.plots.count))").font(.lwData).foregroundStyle(Palette.quiet)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            Divider().overlay(Palette.rule)

            ScrollView {
                LazyVStack(spacing: 8) {
                    if offerClaim {
                        FoundingClaimCard()
                    } else if beta && !cardDismissed {
                        FoundingTesterCard { withAnimation { cardDismissed = true } }
                    }
                    ForEach(store.plots) { plot in
                        Button { open(plot.id) } label: { PlotRow(plot: plot) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(plot) }
                                Button("Delete", systemImage: "trash", role: .destructive) { store.delete(plot) }
                            }
                    }
                }
                .padding(12)
            }

            HStack {
                if beta && cardDismissed {
                    // The card folds away into the footer; tap to see it again.
                    Button("Founding tester") { withAnimation { cardDismissed = false } }
                        .font(.lwBody).foregroundStyle(Palette.quiet)
                } else {
                    Text("Saved on this phone").font(.lwBody).foregroundStyle(Palette.quiet)
                }
                Spacer()
                Button("New plot") { showingNew = true }.buttonStyle(ActionButtonStyle(primary: true))
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .background(Palette.p1)
            .overlay(alignment: .top) { Divider().overlay(Palette.rule) }
        }
        .background(Palette.p0)
        .task {
            beta = await FoundingTester.isBetaBuild()
            offerClaim = await FoundingTester.shouldOfferClaim()
        }
        .sheet(isPresented: $showingNew) {
            NewPlotSheet { name, starter, width, depth in
                let plot = store.create(name: name, starter: starter, width: width, depth: depth)
                showingNew = false
                open(plot.id)
            }
            .presentationDetents([.large])
            .presentationBackground(Palette.p1)
        }
    }
}

struct PlotRow: View {
    let plot: Plot

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(String(format: "%02d", plot.number))
                .font(.lwData).foregroundStyle(Palette.quiet)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(plot.name).font(.lwTitle).foregroundStyle(Palette.text).lineLimit(1)
                Text("\(plot.items.count) lamps · \(plot.starter.title)")
                    .font(.lwData).foregroundStyle(Palette.quiet)
            }
            Spacer(minLength: 0)
            PlanThumbnail(plot: plot).frame(width: 56, height: 56)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.p1, in: RoundedRectangle(cornerRadius: Radius.panel))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(Palette.rule))
        .contentShape(Rectangle())
    }
}

/// Name the scene, pick a starting setup. No account.
struct NewPlotSheet: View {
    var create: (String, Starter, Double, Double) -> Void
    @State private var name = "Int. bedroom, day"
    @State private var starter: Starter = .threePoint
    @State private var width = 6.0
    @State private var depth = 8.4

    var body: some View {
        VStack(spacing: 0) {
            HStack { Caps("New plot"); Spacer() }
                .padding(.horizontal, 16).frame(minHeight: 52)
            Divider().overlay(Palette.rule)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Caps("Scene").padding(.top, 14)
                    TextField("Scene", text: $name)
                        .font(.lwBody).foregroundStyle(Palette.text)
                        .padding(.horizontal, 12).frame(height: 40)
                        .background(Palette.p0, in: RoundedRectangle(cornerRadius: Radius.card))
                        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.rule))
                    Caps("Size of the space").padding(.top, 18)
                    SizeRow(label: "Width", value: $width)
                    SizeRow(label: "Depth", value: $depth)
                    Text("You can add the location's floor plan once it's made: tap the size under the plot's name.")
                        .font(.lwChip).foregroundStyle(Palette.quiet)
                    Caps("Start with").padding(.top, 18)
                    ForEach(Starter.allCases) { s in
                        Button { starter = s } label: {
                            HStack(spacing: 14) {
                                PlanThumbnail(plot: Plot(name: "", number: 0, starter: s, items: s.items()))
                                    .frame(width: 52, height: 52)
                                Text(s.title).font(.lwBody).foregroundStyle(Palette.text)
                                Spacer()
                                Circle()
                                    .fill(s == starter ? Palette.gel : .clear)
                                    .strokeBorder(s == starter ? Palette.gel : Palette.quiet, lineWidth: 1)
                                    .frame(width: 10, height: 10)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Palette.rule)
                    }
                }
                .padding(.horizontal, 16)
            }
            HStack {
                Text("No account needed").font(.lwBody).foregroundStyle(Palette.quiet)
                Spacer()
                Button("Create") { create(name, starter, width, depth) }.buttonStyle(ActionButtonStyle(primary: true))
            }
            .padding(.horizontal, 16).frame(minHeight: 56)
            .overlay(alignment: .top) { Divider().overlay(Palette.rule) }
        }
    }
}
