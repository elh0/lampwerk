import SceneKit
import SwiftUI

/// The camera's view of the talent, in the corner of the plan like a small field monitor: a clay stand-in
/// lit in real 3D by the plot. Every lamp that's on becomes a light where it stands, at its height, aimed
/// where it's aimed, with its beam, output, colour after gel and softness. Exposure is set for the key and
/// white balance to the key's colour, the way a camera would be. Tap to make it bigger.
struct CameraPreview: View {
    let plot: Plot
    @State private var large = false
    /// The camera's stop and ISO. Exposure is locked to these, so a brighter lamp really reads brighter.
    @AppStorage("previewStop") private var stop = 2.8
    @AppStorage("previewISO") private var iso = 800
    /// Closed, it folds down to a small CAM pill; tap that to bring it back.
    @AppStorage("previewOpen") private var open = true
    /// Pinch inside the monitor to push in on the face.
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        if open { monitor } else {
            Button { withAnimation(.snappy(duration: 0.2)) { open = true } } label: {
                HStack(spacing: 5) {
                    Image(systemName: "video").font(.system(size: 11, weight: .medium))
                    Text("CAM").font(.lwLabel)
                }
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 10).frame(minHeight: 30)
                .background(Palette.p2, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.ruleStrong))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show the camera view")
        }
    }

    @ViewBuilder private var monitor: some View {
        let width: CGFloat = large ? 250 : 144
        VStack(spacing: 0) {
            PreviewScene(plot: plot, subject: .sculpt, zoom: zoom * pinch, exposureLux: CameraPreview.exposureLux(stop: stop, iso: iso))
                .frame(width: width, height: width * 9 / 16)
                .overlay { FrameLines().stroke(Palette.text.opacity(0.55), lineWidth: 1).padding(6).allowsHitTesting(false) }
                // The 3D view ignores touches; this catches the tap so it never falls through to the plan.
                .overlay {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { withAnimation(.snappy(duration: 0.22)) { large.toggle() } }
                        .gesture(MagnifyGesture()
                            .updating($pinch) { v, s, _ in s = v.magnification }
                            .onEnded { v in zoom = min(3, max(0.6, zoom * v.magnification)) })
                }
            strip(width: width)
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.ruleStrong))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy(duration: 0.22)) { large.toggle() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camera view of the talent, lit by this plot. Tap to make it bigger.")
    }

    static let stops: [Double] = [1.4, 2, 2.8, 4, 5.6, 8, 11, 16]
    static let isos = [400, 800, 1600, 3200]

    /// Lux on the subject that gives a mid-grey exposure at this stop and ISO, at 1/48 s (180° at 24 fps).
    /// Incident meter equation, E = C·N²/(t·S), with C = 250.
    static func exposureLux(stop: Double, iso: Int) -> Double {
        250 * stop * stop / ((1.0 / 48) * Double(iso))
    }

    /// The key lamp, its number on the plot, and its lux at the talent.
    static func key(_ plot: Plot) -> (number: Int, item: PlacedLamp, lux: Double)? {
        guard let i = plot.items.firstIndex(where: { $0.role == .key && plot.isOn($0) }) else { return nil }
        return (i + 1, plot.items[i], LightMath.lux(from: plot.items[i], at: plot.talent, in: plot))
    }

    /// "KEY 01 · M18 · 307 lx · +1.4": which lamp is the key, how bright it is, and how far over or under the exposure.
    private func strip(width: CGFloat) -> some View {
        let e = CameraPreview.exposureLux(stop: stop, iso: iso)
        let key = CameraPreview.key(plot)
        let over = key.map { log2(max($0.lux, 0.01) / e) }
        let overText = over.map { String(format: "%+.1f", $0) } ?? ""
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let key {
                    Text(large ? String(format: "KEY %02d · %@ · %@ lx", key.number, key.item.lamp?.shortName ?? "", Int(key.lux).formatted()) : "KEY")
                        .foregroundStyle(Palette.quiet).lineLimit(1)
                    Text(overText).foregroundStyle(abs(over ?? 0) > 2 ? Palette.gel : Palette.text)
                } else {
                    Text("NO KEY ON").foregroundStyle(Palette.quiet)
                }
                Spacer(minLength: 0)
                Button { withAnimation(.snappy(duration: 0.2)) { open = false; large = false } } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.text)
                        .frame(width: 22, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close the camera view")
            }
            if large {
                // Tap the stop or ISO to step it; the picture and the stops figure follow.
                HStack(spacing: 10) {
                    Button(String(format: stop < 2 ? "T%.1f" : (stop.truncatingRemainder(dividingBy: 1) == 0 ? "T%.0f" : "T%.1f"), stop)) {
                        let i = CameraPreview.stops.firstIndex(of: stop) ?? 2
                        stop = CameraPreview.stops[(i + 1) % CameraPreview.stops.count]
                    }
                    Button("ISO \(iso)") {
                        let i = CameraPreview.isos.firstIndex(of: iso) ?? 1
                        iso = CameraPreview.isos[(i + 1) % CameraPreview.isos.count]
                    }
                    Spacer(minLength: 0)
                    Text("\(Int(CameraPreview.keyKelvin(plot))) K").foregroundStyle(Palette.quiet)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.text)
            }
        }
        .font(.lwLabel)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .frame(width: width, alignment: .leading)
        .background(Color(hex: 0x0A0A09))
    }

    /// The key's colour after its gel, which the camera is white-balanced to.
    static func keyKelvin(_ plot: Plot) -> Double {
        plot.items.first { $0.role == .key && plot.isOn($0) }.map(effectiveKelvin) ?? 5600
    }

    static func effectiveKelvin(_ item: PlacedLamp) -> Double {
        let shift: [String: Double] = ["¼ CTO": 64, "½ CTO": 109, "Full CTO": 159, "¼ CTB": -30, "½ CTB": -68, "Full CTB": -131]
        let k = item.cct > 0 ? item.cct : 5600
        guard let m = shift[item.gel] else { return k }
        return 1_000_000 / (1_000_000 / k + m)
    }

    /// Black-body colour (Tanner Helland's fit), in 0...1 sRGB.
    static func kelvin(_ k: Double) -> SIMD3<Double> {
        let t = max(1000, min(40000, k)) / 100
        let r = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let g = t <= 66 ? 99.4708025861 * log(t) - 161.1195681661 : 288.1221695283 * pow(t - 60, -0.0755148492)
        let b = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307)
        return SIMD3(max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b))) / 255
    }

    /// How soft a head is at the face: its kind, its modifier and any diff frame in front. 0 hard, 1 very soft.
    static func softness(_ item: PlacedLamp, _ lamp: Lamp, _ plot: Plot) -> Double {
        var w: Double
        switch lamp.kind {
        case .panel: w = 0.6
        case .tube: w = 0.5
        case .practical: w = 0.75
        default: w = 0.1
        }
        switch item.modifier {
        case "Softbox", "Chimera, medium", "Dome M": w = max(w, 0.75)
        case "Lantern", "8x8 full grid": w = max(w, 0.9)
        case "Snapgrid 40°", "Honeycrate", "Snoot", "Fresnel lens": w = min(w, 0.25)
        default: break
        }
        if LightMath.diffFrame(for: item, in: plot) != nil { w = max(w, 0.85) }
        return w
    }
}

/// Frame corners and a centre cross, like a monitor's guides.
private struct FrameLines: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let l: CGFloat = 10
        for (x, y, dx, dy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX, r.minY, -1.0, 1.0), (r.minX, r.maxY, 1.0, -1.0), (r.maxX, r.maxY, -1.0, -1.0)] {
            p.move(to: CGPoint(x: x + dx * l, y: y)); p.addLine(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x, y: y + dy * l))
        }
        p.move(to: CGPoint(x: r.midX - 3, y: r.midY)); p.addLine(to: CGPoint(x: r.midX + 3, y: r.midY))
        p.move(to: CGPoint(x: r.midX, y: r.midY - 3)); p.addLine(to: CGPoint(x: r.midX, y: r.midY + 3))
        return p
    }
}

/// The SceneKit view. It only redraws when the plot changes, at most about 20 times a second while you drag.
private struct PreviewScene: UIViewRepresentable {
    let plot: Plot
    let subject: StandIn.Style
    var zoom: CGFloat = 1
    var exposureLux: Double = 120

    func makeCoordinator() -> PreviewRig { PreviewRig() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        // Capped at 20 frames a second: smooth enough while dragging, light on the battery.
        view.preferredFramesPerSecond = 20
        view.rendersContinuously = true
        view.isUserInteractionEnabled = false
        view.isJitteringEnabled = false
        context.coordinator.setSubject(subject)
        context.coordinator.zoom = Double(zoom)
        context.coordinator.exposureLux = exposureLux
        context.coordinator.update(plot, view: view)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.setSubject(subject)
        context.coordinator.zoom = Double(zoom)
        context.coordinator.exposureLux = exposureLux
        context.coordinator.update(plot, view: view)
    }
}

/// Holds the scene: the stand-in on the mark, a camera on the plot's camera line, and one light per lamp.
final class PreviewRig {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private var standIn = StandIn.node()
    /// Pinch zoom from the monitor: 1 is the medium close-up.
    var zoom = 1.0
    /// Lux that exposes clay at mid-grey; set from the monitor's stop and ISO.
    var exposureLux = 120.0
    private var subject = StandIn.Style.planes
    private let rig = SCNNode()
    private var last = Date.distantPast
    private var pending: Plot?
    private var scheduled = false

    /// Eye height on the mark, metres.
    private static let eyes = 1.6
    /// The stand-in's eyes sit this far above its neck base.
    private static let eyesAboveNeck = 0.2
    /// Height of the frame: a medium close-up, head and shoulders.
    private static let frameHeight = 0.46
    private static let fovDegrees: CGFloat = 21

    init() {
        scene.background.contents = UIColor.black
        scene.fogColor = UIColor.black
        scene.fogStartDistance = 3
        scene.fogEndDistance = 9

        // The stand-in's neck base sits so its eyes land at eye height.
        standIn.position = SCNVector3(0, Float(Self.eyes - Self.eyesAboveNeck), 0)
        scene.rootNode.addChildNode(standIn)

        // A dark clay floor far below, fading into the fog, for when the view opens out.
        let floor = SCNFloor()
        floor.reflectivity = 0
        let fm = SCNMaterial()
        fm.lightingModel = .physicallyBased
        fm.diffuse.contents = UIColor(white: 0.2, alpha: 1)
        fm.roughness.contents = 0.95
        floor.materials = [fm]
        scene.rootNode.addChildNode(SCNNode(geometry: floor))

        let camera = SCNCamera()
        // A 50 mm on Super 35: about 21° top to bottom.
        camera.projectionDirection = .vertical
        camera.fieldOfView = Self.fovDegrees
        camera.zNear = 0.05
        camera.zFar = 60
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = 0
        camera.whitePoint = 1.2
        camera.bloomIntensity = 0
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 12
        ambient.color = UIColor.white
        let a = SCNNode()
        a.light = ambient
        scene.rootNode.addChildNode(a)

        scene.rootNode.addChildNode(rig)
    }

    /// Swaps the stand-in, keeping where it stands and which way it faces.
    func setSubject(_ style: StandIn.Style) {
        guard style != subject else { return }
        subject = style
        let next = StandIn.node(style)
        next.position = standIn.position
        next.eulerAngles = standIn.eulerAngles
        standIn.removeFromParentNode()
        standIn = next
        scene.rootNode.addChildNode(next)
    }

    /// Takes the newest plot; rebuilds at most about 20 times a second so dragging stays smooth.
    func update(_ plot: Plot, view: SCNView) {
        pending = plot
        let gap = Date().timeIntervalSince(last)
        if gap >= 0.05 {
            apply(view)
        } else if !scheduled {
            scheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + (0.05 - gap)) { [weak self, weak view] in
                guard let self, let view else { return }
                self.scheduled = false
                self.apply(view)
            }
        }
    }

    private func apply(_ view: SCNView) {
        guard let plot = pending else { return }
        pending = nil
        last = Date()
        build(plot)
        view.setNeedsDisplay()
    }

    private func world(_ p: Point2, _ t: Point2, height: Double) -> SCNVector3 {
        // The plan's x runs right and its y down the screen, which is +z in a y-up scene seen from above.
        SCNVector3(Float(p.x - t.x), Float(height), Float(p.y - t.y))
    }

    private func build(_ plot: Plot) {
        let t = plot.talent
        rig.childNodes.forEach { $0.removeFromParentNode() }

        // Talent faces the camera; the camera sits on its real line to the talent, pulled in for the framing.
        let toCam = SIMD2(plot.camera.x - t.x, plot.camera.y - t.y)
        let dist = max(0.3, simd_length(toCam))
        let dir = toCam / dist
        standIn.eulerAngles.y = Float(atan2(dir.x, dir.y))
        let fov = Double(Self.fovDegrees) * .pi / 180
        let back = Self.frameHeight / max(0.6, zoom) / 2 / tan(fov / 2)
        cameraNode.position = SCNVector3(Float(dir.x * back), Float(Self.eyes - 0.05), Float(dir.y * back))
        cameraNode.look(at: SCNVector3(0, Float(Self.eyes - 0.04), 0))

        let wb = CameraPreview.kelvin(CameraPreview.keyKelvin(plot))

        for item in plot.items {
            guard let lamp = item.lamp else { continue }
            var lux = 0.0
            var softness = 0.9
            var spread = 300.0
            if lamp.isLight {
                guard plot.isOn(item) else { continue }
                lux = LightMath.lux(from: item, at: t, in: plot)
                softness = CameraPreview.softness(item, lamp, plot)
                spread = LightMath.spread(item, in: plot)
            } else if lamp.kind == .bounce {
                let key = plot.items.filter { plot.isOn($0) && $0.role == .key }.reduce(0) { $0 + LightMath.lux(from: $1, at: t, in: plot) }
                lux = key * 0.45 * min(1, lamp.width / 1.2) / max(1, pow(item.position.distance(to: t), 2) / 2)
            }
            guard lux > 0 else { continue }

            let light = SCNLight()
            // Lux at the talent already allows for distance, beam and losses, so the light itself doesn't fall off.
            light.attenuationFalloffExponent = 0
            light.intensity = CGFloat(70 * lux / exposureLux)
            var rgb = lamp.isLight ? CameraPreview.kelvin(CameraPreview.effectiveKelvin(item)) / wb : SIMD3(1, 1, 1)
            if item.gel == "¼ Plus green" { rgb *= SIMD3(0.92, 1, 0.92) }
            let top = max(rgb.x, rgb.y, rgb.z, 1)
            light.color = UIColor(red: CGFloat(rgb.x / top), green: CGFloat(rgb.y / top), blue: CGFloat(rgb.z / top), alpha: 1)
            light.intensity *= CGFloat(top)

            let node = SCNNode()
            let height = lamp.isLight ? IsoCanvas.height(item) : Self.eyes
            node.position = world(item.position, t, height: height)

            if spread >= 300 || !lamp.isLight {
                light.type = .omni
            } else {
                light.type = .spot
                // Aimed where the lamp points, at head height, as far out as the talent.
                let a = item.angle * .pi / 180
                let reach = item.position.distance(to: t)
                let aim = Point2(x: item.x + cos(a) * reach, y: item.y + sin(a) * reach)
                node.look(at: world(aim, t, height: Self.eyes))
                // Wide enough to reach the talent even when it's only spill.
                let off = LightMath.angleBetween(item.position.bearing(to: t), item.angle)
                let outer = min(170, max(spread, off * 2 + 12))
                light.spotOuterAngle = CGFloat(outer)
                light.spotInnerAngle = CGFloat(outer * (softness > 0.5 ? 0.45 : 0.85))
            }
            // Soft sources throw soft shadows; hard ones cut.
            light.castsShadow = true
            light.shadowMapSize = CGSize(width: 1024, height: 1024)
            light.shadowRadius = CGFloat(1.5 + softness * 14)
            light.shadowSampleCount = softness > 0.5 ? 16 : 4
            light.shadowColor = UIColor(white: 0, alpha: 0.92)
            light.shadowBias = 0.02
            node.light = light
            rig.addChildNode(node)
        }
    }
}
