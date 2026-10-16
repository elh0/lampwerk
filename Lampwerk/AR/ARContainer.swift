import SwiftUI
import simd

#if targetEnvironment(simulator)

/// The simulator has no camera. Shows a note so the rest of the screen can still be checked.
struct ARContainer: View {
    let model: ARTagModel

    var body: some View {
        Text("AR tagging needs an iPhone")
            .font(.lwBody).foregroundStyle(Palette.quiet)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.p0)
    }
}

#else

import ARKit
import Combine
import RealityKit

/// The camera with tracking, the floor reticle and the placed markers, drawn with RealityKit.
/// On phones with LiDAR the room mesh is shown as a wireframe so you can see what's been scanned.
struct ARContainer: UIViewRepresentable {
    let model: ARTagModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        context.coordinator.attach(view)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {}

    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        coordinator.updates?.cancel()
        view.session.pause()
    }

    @MainActor
    final class Coordinator: NSObject {
        let model: ARTagModel
        weak var view: ARView?
        var updates: Cancellable?

        private let root = AnchorEntity(world: .zero)
        private let markers = Entity()
        private let reticle = Entity()
        private var builtRevision = -1
        private var builtSelection: UUID?
        private var frame = 0

        init(model: ARTagModel) { self.model = model }

        func attach(_ view: ARView) {
            self.view = view

            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal]
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                config.sceneReconstruction = .mesh
                view.debugOptions.insert(.showSceneUnderstanding)
            }
            view.session.run(config)

            root.addChild(markers)
            root.addChild(reticle)
            view.scene.addAnchor(root)
            buildReticle()

            let coaching = ARCoachingOverlayView()
            coaching.session = view.session
            coaching.goal = .horizontalPlane
            coaching.activatesAutomatically = true
            coaching.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(coaching)
            NSLayoutConstraint.activate([
                coaching.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                coaching.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                coaching.topAnchor.constraint(equalTo: view.topAnchor),
                coaching.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])

            updates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }

        // MARK: Every frame

        private func tick() {
            guard let view, view.bounds.width > 0 else { return }
            frame += 1

            let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            if let hit = view.raycast(from: center, allowing: .estimatedPlane, alignment: .horizontal).first {
                let p = hit.worldTransform.columns.3
                let floor = SIMD2<Float>(p.x, p.z)
                if model.reticle.map({ simd_distance($0, floor) > 0.005 }) ?? true { model.reticle = floor }
                if model.refA == nil, model.talent == nil, abs(model.floorY - p.y) > 0.005 { model.floorY = p.y }
                if !model.trackingReady { model.trackingReady = true }
                reticle.isEnabled = true
                reticle.position = SIMD3(p.x, (model.refA == nil && model.talent == nil ? p.y : model.floorY) + 0.003, p.z)
            } else {
                if model.reticle != nil { model.reticle = nil }
                reticle.isEnabled = false
            }

            if model.revision != builtRevision || model.selected != builtSelection { rebuild() }
            if frame % 2 == 0 { project(view) }
        }

        /// Screen positions for the SwiftUI labels. Anything behind the phone is left out.
        private func project(_ view: ARView) {
            let cam = view.cameraTransform
            let camPos = cam.translation
            let forward = -SIMD3<Float>(cam.matrix.columns.2.x, cam.matrix.columns.2.y, cam.matrix.columns.2.z)
            func screen(_ p: SIMD3<Float>) -> CGPoint? {
                guard simd_dot(p - camPos, forward) > 0.15 else { return nil }
                return view.project(p)
            }
            let y = model.floorY
            var s: [String: CGPoint] = [:]
            if let a = model.refA, let p = screen([a.x, y + 0.25, a.y]) { s["refA"] = p }
            if let b = model.refB, let p = screen([b.x, y + 0.25, b.y]) { s["refB"] = p }
            if let t = model.talent, let p = screen([t.x, y + 1.95, t.y]) { s["talent"] = p }
            if let c = model.camera, let p = screen([c.x, y + 1.7, c.y]) { s["camera"] = p }
            for tag in model.tags {
                let top = tag.height + headSize(tag).y / 2 + 0.22
                if let p = screen([tag.floor.x, y + top, tag.floor.y]) { s[tag.id.uuidString] = p }
            }
            if let r = model.reticle, let p = screen([r.x, y, r.y]) { s["reticle"] = p }
            model.screen = s
        }

        // MARK: Markers

        private func rebuild() {
            builtRevision = model.revision
            builtSelection = model.selected
            for child in Array(markers.children) { child.removeFromParent() }
            let y = model.floorY

            for ref in [model.refA, model.refB].compactMap({ $0 }) {
                let at = SIMD3<Float>(ref.x, y, ref.y)
                markers.addChild(disc(0.3, .white, 0.5, at: at))
                markers.addChild(box([0.01, 0.2, 0.01], .white, 0.8, at: at + [0, 0.1, 0]))
            }

            if let t = model.talent {
                let at = SIMD3<Float>(t.x, y, t.y)
                markers.addChild(disc(0.5, .white, 0.3, at: at))
                markers.addChild(disc(0.08, .white, 1, at: at + [0, 0.001, 0]))
                markers.addChild(box([0.012, 1.55, 0.012], .white, 0.35, at: at + [0, 0.775, 0]))
                let head = ModelEntity(mesh: .generateSphere(radius: 0.1), materials: [Self.unlit(.white, 0.45)])
                head.position = at + [0, 1.68, 0]
                markers.addChild(head)
            }

            if let c = model.camera, let t = model.talent {
                let at = SIMD3<Float>(c.x, y, c.y)
                markers.addChild(disc(0.4, .white, 0.22, at: at))
                markers.addChild(box([0.025, 1.3, 0.025], .white, 0.8, at: at + [0, 0.65, 0]))
                let body = box([0.18, 0.16, 0.3], .white, 0.9, at: at + [0, 1.38, 0])
                body.orientation = Self.yaw(from: c, to: t)
                markers.addChild(body)
            }

            for tag in model.tags { markers.addChild(lampMarker(tag, floorY: y)) }
        }

        private func lampMarker(_ tag: ARTagModel.Tag, floorY y: Float) -> Entity {
            let group = Entity()
            let at = SIMD3<Float>(tag.floor.x, y, tag.floor.y)
            let selected = tag.id == model.selected
            let gel = UIColor(red: 1, green: 0.76, blue: 0.10, alpha: 1)
            let lit = tag.lamp?.isLight ?? false

            group.addChild(disc(0.55, selected ? gel : .white, selected ? 0.55 : 0.22, at: at))
            let size = headSize(tag)
            let poleTop = max(0.1, tag.height - size.y / 2)
            group.addChild(box([0.022, poleTop, 0.022], .white, 0.85, at: at + [0, poleTop / 2, 0]))

            let headColor: UIColor
            let headAlpha: CGFloat
            switch tag.lamp?.kind {
            case .flag?: headColor = UIColor(white: 0.04, alpha: 1); headAlpha = 0.95
            case .bounce?, .diff?: headColor = .white; headAlpha = 0.4
            default: headColor = lit ? gel : .white; headAlpha = 1
            }
            let head = box([size.x, size.y, 0.07], headColor, headAlpha, at: at + [0, tag.height, 0])
            if let t = model.talent { head.orientation = Self.yaw(from: tag.floor, to: t) }
            group.addChild(head)

            // A thin line of light from the head to the talent's face.
            if lit, let t = model.talent {
                let from = at + [0, tag.height, 0]
                let to = SIMD3<Float>(t.x, y + 1.5, t.y)
                let length = simd_distance(from, to)
                if length > 0.2 {
                    let beam = ModelEntity(mesh: .generateBox(size: [0.008, 0.008, length]), materials: [Self.unlit(gel, 0.6)])
                    beam.look(at: to, from: (from + to) / 2, relativeTo: nil)
                    group.addChild(beam)
                }
            }
            return group
        }

        /// Width and height of the head as drawn. Tubes stand upright; frames are square-ish.
        private func headSize(_ tag: ARTagModel.Tag) -> SIMD2<Float> {
            guard let lamp = tag.lamp else { return [0.4, 0.3] }
            let w = Float(lamp.width), d = Float(lamp.depth)
            switch lamp.kind {
            case .tube: return [0.05, w]
            case .bounce, .diff: return [w, w]
            case .flag: return [w, w * 0.66]
            case .practical: return [max(0.25, w), max(0.25, w)]
            default: return [w, max(0.2, d)]
            }
        }

        private func buildReticle() {
            reticle.addChild(disc(0.22, .white, 0.28, at: .zero))
            reticle.addChild(disc(0.035, .white, 1, at: [0, 0.001, 0]))
        }

        // MARK: Pieces

        private func disc(_ diameter: Float, _ color: UIColor, _ alpha: CGFloat, at p: SIMD3<Float>) -> ModelEntity {
            let e = ModelEntity(mesh: .generatePlane(width: diameter, depth: diameter, cornerRadius: diameter / 2), materials: [Self.unlit(color, alpha)])
            e.position = p
            return e
        }

        private func box(_ size: SIMD3<Float>, _ color: UIColor, _ alpha: CGFloat, at p: SIMD3<Float>) -> ModelEntity {
            let e = ModelEntity(mesh: .generateBox(size: size), materials: [Self.unlit(color, alpha)])
            e.position = p
            return e
        }

        static func unlit(_ color: UIColor, _ alpha: CGFloat) -> UnlitMaterial {
            var m = UnlitMaterial(color: color)
            if alpha < 1 { m.blending = .transparent(opacity: .init(floatLiteral: Float(alpha))) }
            return m
        }

        /// Turns an entity about the vertical so its +z faces from one floor point to another.
        static func yaw(from a: SIMD2<Float>, to b: SIMD2<Float>) -> simd_quatf {
            let d = b - a
            return simd_quatf(angle: atan2(d.x, d.y), axis: [0, 1, 0])
        }
    }
}

#endif
