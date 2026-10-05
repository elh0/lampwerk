import Foundation
import Observation

/// Plots saved on the phone as JSON in Documents. No account, works offline.
@MainActor
@Observable
final class PlotStore {
    var plots: [Plot] = []
    var supply: LightMath.Supply = .uk

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
    func create(name: String, starter: Starter) -> Plot {
        let number = (plots.map(\.number).max() ?? 0) + 1
        let plot = Plot(name: name.isEmpty ? "Untitled" : name, number: number, starter: starter, items: starter.items())
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
