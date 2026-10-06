import SwiftUI
import SceneKit

/// Live, interactive turntable view of the model-fallback car (the Garage
/// hero shows this instead of a static baked image when there's no usable
/// cover photo): it rests at a three-quarter angle on a glossy floor, and a
/// horizontal drag spins it around its vertical axis. Reuses the exact same node graph
/// (`ProceduralCarModel.node(for:paint:)`) and studio lighting
/// (`CarModelRenderer.studioEnvironment()`) as the static bake, just hosted
/// in a live `SCNView` instead of rendered once to a PNG. `CarModelRenderer`
/// itself is untouched and still used where a live `SCNView` can't be hosted
/// — the Home Screen widget and the car-switcher thumbnails.
struct SpinnableCarModelView: UIViewRepresentable {
    let profile: CarBodyProfile
    let paint: UIColor

    func makeUIView(context: Context) -> FloorFadeView {
        let view = FloorFadeView()
        view.groundRadius = Float(profile.length) / 2
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.isUserInteractionEnabled = true
        view.allowsCameraControl = false

        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scene.lightingEnvironment.contents = CarModelRenderer.studioEnvironment()
        scene.lightingEnvironment.intensity = 2.2

        let car = ProceduralCarModel.node(for: profile, paint: paint)
        car.position = SCNVector3(-Float(profile.length) / 2, 0, 0)
        let turntable = SCNNode()
        turntable.addChildNode(car)
        turntable.addChildNode(Self.reflection(of: car))
        turntable.eulerAngles.y = 0.6
        scene.rootNode.addChildNode(turntable)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 1600
        key.eulerAngles = SCNVector3(-1.0, 0.5, 0)
        scene.rootNode.addChildNode(key)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 200
        scene.rootNode.addChildNode(fill)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        // Fit the car's full length across the view's width, so it never
        // clips when the spin turns it side-on (a pickup is ~1m longer than
        // a hatchback, so this can't be one fixed angle).
        camera.camera?.projectionDirection = .horizontal
        let visibleWidth = Double(profile.length) * 1.18
        camera.camera?.fieldOfView = 2 * atan(visibleWidth / 2 / 11.3) * 180 / .pi
        camera.camera?.wantsHDR = true
        camera.position = SCNVector3(0, 1.55, 11.3)
        camera.look(at: SCNVector3(0, 0.65, 0))
        scene.rootNode.addChildNode(camera)

        view.scene = scene
        view.pointOfView = camera

        context.coordinator.turntable = turntable

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: FloorFadeView, context: Context) {}

    /// The car mirrored under the floor, darkened rather than made
    /// translucent (a translucent copy would show its insides). Geometry is
    /// copied so darkening it can't touch the real car's shared materials.
    private static func reflection(of car: SCNNode) -> SCNNode {
        let mirror = car.clone()
        mirror.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry?.copy() as? SCNGeometry else { return }
            geometry.materials = geometry.materials.map { material in
                let copy = material.copy() as! SCNMaterial
                copy.multiply.contents = UIColor(white: 0.18, alpha: 1)
                return copy
            }
            node.geometry = geometry
        }
        mirror.scale = SCNVector3(1, -1, 1)
        return mirror
    }

    /// Fades the view out below the floor, so the mirrored car reads as a
    /// reflection on a glossy floor that falls away from the car.
    final class FloorFadeView: SCNView {
        /// Radius of the car's footprint: the floor point nearest the camera,
        /// whichever way the car faces, is where the fade starts.
        var groundRadius: Float = 2.4
        private let fade = CAGradientLayer()

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.height > 0 else { return }
            let start = CGFloat(projectPoint(SCNVector3(0, 0, groundRadius)).y)
            let end = CGFloat(projectPoint(SCNVector3(0, -0.9, groundRadius)).y)
            // Full strength down to the floor, then the reflection drops to
            // half and fades out.
            let black = UIColor.black.cgColor
            fade.colors = [black, black, UIColor.black.withAlphaComponent(0.5).cgColor, UIColor.clear.cgColor]
            fade.locations = [0, start, start + 1, end].map { NSNumber(value: Double($0 / bounds.height)) }
            fade.frame = bounds
            layer.mask = fade
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var turntable: SCNNode?
        private var dragStartY: Float = 0

        /// Only a mostly-horizontal drag spins the car; a vertical one is
        /// left to the enclosing ScrollView, so swiping on the hero still
        /// scrolls the Garage.
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y)
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let turntable else { return }
            switch gesture.state {
            case .began:
                dragStartY = turntable.eulerAngles.y
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                let width = max(gesture.view?.bounds.width ?? 1, 1)
                let delta = Float(translation.x / width) * .pi * 2.4
                turntable.eulerAngles.y = dragStartY + delta
            default:
                break
            }
        }
    }
}
