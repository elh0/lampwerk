import Foundation
import Observation

/// Plots saved on the phone as JSON in Documents. No account, works offline.
@MainActor
@Observable
final class PlotStore {
    var plots: [Plot] = []
    /// Region and circuit size, kept between launches.
    var supply: LightMath.Supply = PlotStore.savedSupply() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(supply), forKey: Self.supplyKey) }
    }

    private static let supplyKey = "power.supply"

    private static func savedSupply() -> LightMath.Supply {
        guard let data = UserDefaults.standard.data(forKey: supplyKey),
              let s = try? JSONDecoder().decode(LightMath.Supply.self, from: data) else { return .uk }
        return s
    }

    private let url = URL.documentsDirectory.appending(path: "plots.json")

    init() {
        load()
        if plots.isEmpty {
            plots = [
                Plot(name: "Int. kitchen, night", number: 3, starter: .window, items: Starter.window.items()),
                Plot(name: "Int. office, interview", number: 2, starter: .threePoint, items: Starter.threePoint.items()),
                Plot(name: "Ext. car, dusk", number: 1, starter: .car, items: Starter.car.items()),
            ]
            save()
        }
    }

    @discardableResult
    func create(name: String, starter: Starter, width: Double = 6, depth: Double = 8.4) -> Plot {
        let number = (plots.map(\.number).max() ?? 0) + 1
        var plot = Plot(name: name.isEmpty ? "Untitled" : name, number: number, starter: starter, items: starter.items())
        // Starters are drawn for a 6 × 8.4 m room; keep the setup centred in the chosen size.
        let dx = (width - plot.roomWidth) / 2, dy = (depth - plot.roomDepth) / 2
        plot.roomWidth = width
        plot.roomDepth = depth
        plot.talent = Point2(x: plot.talent.x + dx, y: plot.talent.y + dy)
        plot.camera = Point2(x: plot.camera.x + dx, y: min(depth - 0.4, plot.camera.y + dy))
        for i in plot.items.indices {
            plot.items[i].x += dx
            plot.items[i].y += dy
        }
        plots.insert(plot, at: 0)
        save()
        return plot
    }

    func update(_ plot: Plot) {
        guard let i = plots.firstIndex(where: { $0.id == plot.id }) else { return }
        var p = plot
        p.updated = Date()
        plots[i] = p
        saveSoon()
    }

    /// A copy at the top of the list, e.g. to try another setup on the same scene.
    func duplicate(_ plot: Plot) {
        var copy = plot
        copy.id = UUID()
        copy.name = plot.name + " (copy)"
        copy.number = (plots.map(\.number).max() ?? 0) + 1
        copy.updated = Date()
        plots.insert(copy, at: 0)
        save()
    }

    func delete(_ plot: Plot) {
        plots.removeAll { $0.id == plot.id }
        save()
    }

    private var pendingSave: Task<Void, Never>?

    /// Edits arrive on every drag step; write once things settle.
    private func saveSoon() {
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        plots = (try? JSONDecoder().decode([Plot].self, from: data)) ?? []
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(plots)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Lampwerk: couldn't save plots: \(error)")
        }
    }
}
