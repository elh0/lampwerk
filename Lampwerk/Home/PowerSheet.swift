import SwiftUI

/// Where the job is and what the sparks are plugging into. Sets the volts for every draw and the size circuits are packed to.
struct PowerSheet: View {
    @Environment(PlotStore.self) private var store
    var done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Caps("Power")
                Spacer()
                Button("Done", action: done).buttonStyle(ActionButtonStyle(primary: true))
            }
            .padding(.horizontal, 16).frame(minHeight: 52)
            Rectangle().fill(Palette.rule).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Caps("Region").padding(.top, 14)
                    ForEach(LightMath.Supply.Region.allCases, id: \.self) { region in
                        Button {
                            store.supply = LightMath.Supply(region: region, circuitAmps: region.standardCircuit)
                        } label: {
                            HStack {
                                Text(region.title).font(.lwBody).foregroundStyle(Palette.text)
                                Spacer()
                                if store.supply.region == region {
                                    Image(systemName: "checkmark").font(.system(size: 13)).foregroundStyle(Palette.text)
                                }
                            }
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .background(store.supply.region == region ? Palette.p2 : Palette.p0, in: RoundedRectangle(cornerRadius: Radius.card))
                            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.rule))
                        }
                        .buttonStyle(.plain)
                    }

                    Caps("Circuit size").padding(.top, 18)
                    HStack(spacing: 4) {
                        ForEach(store.supply.region.circuits, id: \.self) { amps in
                            Chip(title: "\(Int(amps)) A", selected: store.supply.circuitAmps == amps) {
                                store.supply.circuitAmps = amps
                            }
                        }
                    }
                    Text(hint).font(.lwChip).foregroundStyle(Palette.quiet).padding(.top, 4)
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
    }

    private var hint: String {
        switch store.supply.region {
        case .uk: "13 A is a house socket, 16 A and 32 A are ceeforms, 63 A is a distro feed. Lamps are packed into circuits of this size on the sheet."
        case .us: "15 A and 20 A are wall circuits, 60 A and 100 A are bates and distro feeds. Lamps are packed into circuits of this size on the sheet."
        }
    }
}
