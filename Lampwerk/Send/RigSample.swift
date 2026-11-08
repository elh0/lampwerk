#if DEBUG
import SwiftUI

/// Debug only: launch with -rigSample to write two sample rig drawings to Documents/rig-sample, for checking the look.
@MainActor
enum RigSample {
    static func writeIfAsked() {
        guard CommandLine.arguments.contains("-rigSample") else { return }
        let out = URL.documentsDirectory.appending(path: "rig-sample", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        var window = Plot(name: "Kitchen, window key", number: 1, starter: .window, items: [])
        window.apply(.window)

        var studio = Plot(name: "Studio, top light", number: 2, starter: .threePoint, items: [])
        studio.roomWidth = 9
        studio.roomDepth = 8
        studio.apply(.threePoint)
        for x in [2.5, 4.0, 5.5, 7.0] {
            var top = Starter.place("s30", x, 1.2, .back, 5600, 60, [.close])
            top.name = "Top"
            top.height = 4.2
            studio.items.append(top)
        }

        for (plot, tag) in [(window, "window"), (studio, "studio")] {
            for setOnly in [false, true] {
                if let url = Export.rigDrawingPDF(plot, yaw: IsoProjection.defaultYaw, pitch: IsoProjection.defaultPitch, setOnly: setOnly) {
                    let dest = out.appending(path: "\(tag)-\(setOnly ? "set" : "rig").pdf")
                    try? FileManager.default.removeItem(at: dest)
                    try? FileManager.default.copyItem(at: url, to: dest)
                }
            }
        }
    }
}
#endif
