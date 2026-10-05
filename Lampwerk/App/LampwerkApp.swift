import SwiftUI

@main
struct LampwerkApp: App {
    @State private var store = PlotStore()

    init() {
        Fonts.registerBundled()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}

/// Plots list, with the editor pushed over it. A short splash of the lockup on launch.
struct RootView: View {
    @Environment(PlotStore.self) private var store
    @State private var openPlot: Plot.ID?
    @State private var splash = true

    var body: some View {
        ZStack {
            Palette.p0.ignoresSafeArea()

            if let id = openPlot, store.plots.contains(where: { $0.id == id }) {
                EditorView(plotID: id) { openPlot = nil }
                    .transition(.move(edge: .trailing))
            } else {
                HomeView { openPlot = $0 }
                    .transition(.opacity)
            }

            if splash {
                Palette.p0.ignoresSafeArea()
                    .overlay(Lockup(height: 54))
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(0.9))
                        splash = false
                    }
            }
        }
        .animation(.snappy(duration: 0.28), value: openPlot)
        .animation(.easeOut(duration: 0.35), value: splash)
    }
}
