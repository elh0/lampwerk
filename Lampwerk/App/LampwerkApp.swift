import SwiftUI

@main
struct LampwerkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = PlotStore()

    init() {
        Fonts.registerBundled()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .task { await FoundingTester.markIfBeta() }
        }
    }
}

/// Plots list, with the editor pushed over it. On launch the wordmark flickers on like a lamp striking.
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
                    .overlay(FlickerWordmark())
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(2.1))
                        splash = false
                    }
            }
        }
        .animation(.snappy(duration: 0.28), value: openPlot)
        .animation(.easeOut(duration: 0.35), value: splash)
    }
}

/// The wordmark stuttering on like a head warming up, then holding. Same steps as the studio site's
/// Lampwerk tile (cvflick, timings in eltio/brand/wordmark-motion/README.md); with Reduce Motion on it just shows.
struct FlickerWordmark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let mark = Image("Wordmark").resizable().scaledToFit()
            .frame(height: 36)
            .foregroundStyle(Palette.text)
        Group {
            if reduceMotion {
                mark
            } else {
                mark.keyframeAnimator(initialValue: 0.0, repeating: false) { view, opacity in
                    view.opacity(opacity)
                } keyframes: { _ in
                    KeyframeTrack {
                        // cvflick at the splash speed (cv-quick, 4 s): 0/2/3.5/5.5/7/9% of the loop.
                        CubicKeyframe(0.5, duration: 0.08)
                        CubicKeyframe(0.08, duration: 0.06)
                        CubicKeyframe(0.85, duration: 0.08)
                        CubicKeyframe(0.3, duration: 0.06)
                        CubicKeyframe(1, duration: 0.08)
                    }
                }
            }
        }
        .accessibilityLabel("Lampwerk")
    }
}

/// Lets one screen hold the phone upright (AR tagging) while the rest of the app turns to landscape.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientations: UIInterfaceOrientationMask = .allButUpsideDown

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientations
    }
}

enum Orientation {
    /// Limits the app to `mask` and turns the screen to match straight away.
    @MainActor static func lock(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.orientations = mask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
            for window in scene.windows {
                var vc = window.rootViewController
                while let v = vc {
                    v.setNeedsUpdateOfSupportedInterfaceOrientations()
                    vc = v.presentedViewController
                }
            }
        }
    }

    @MainActor static func unlock() { lock(.allButUpsideDown) }
}
