import SwiftUI
import SceneKit

/// Live, interactive turntable view of the model-fallback car (the Garage
/// hero shows this instead of a static baked image when there's no usable
/// cover photo): drag horizontally to spin it around its vertical axis: it
/// auto-rotates slowly when idle, pauses on touch, and resumes a couple of
/// seconds after the user lets go. Reuses the exact same node graph
/// (`ProceduralCarModel.node(for:paint:)`) and studio lighting
/// (`CarModelRenderer.studioEnvironment()`) as the static bake, just hosted
/// in a live `SCNView` instead of rendered once to a PNG. `CarModelRenderer`
/// itself is untouched and still used where a live `SCNView` can't be hosted
/// — the Home Screen widget and the car-switcher thumbnails.
struct SpinnableCarModelView: UIViewRepresentable {
    let profile: CarBodyProfile
    let paint: UIColor
    /// False under Reduce Motion: no unprompted continuous spin, but drag
    /// still works — that motion is user-initiated, not ambient.
    var autoRotates: Bool = true

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
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
        camera.camera?.fieldOfView = 15
        camera.camera?.wantsHDR = true
        camera.position = SCNVector3(0, 1.55, 11.3)
        camera.look(at: SCNVector3(0, 0.65, 0))
        scene.rootNode.addChildNode(camera)

        view.scene = scene
        view.pointOfView = camera

        context.coordinator.turntable = turntable
        context.coordinator.autoRotates = autoRotates
        context.coordinator.startAutoRotate()

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject {
        weak var turntable: SCNNode?
        var autoRotates = true
        private var resumeWorkItem: DispatchWorkItem?
        private var dragStartY: Float = 0

        func startAutoRotate() {
            guard autoRotates, let turntable, turntable.action(forKey: "spin") == nil else { return }
            let spin = SCNAction.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 16))
            turntable.runAction(spin, forKey: "spin")
        }

        func invalidate() {
            resumeWorkItem?.cancel()
            turntable?.removeAllActions()
            turntable = nil
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let turntable else { return }
            switch gesture.state {
            case .began:
                resumeWorkItem?.cancel()
                turntable.removeAction(forKey: "spin")
                dragStartY = turntable.presentation.eulerAngles.y
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                let width = max(gesture.view?.bounds.width ?? 1, 1)
                let delta = Float(translation.x / width) * .pi * 2.4
                turntable.eulerAngles.y = dragStartY + delta
            case .ended, .cancelled, .failed:
                scheduleResume()
            default:
                break
            }
        }

        private func scheduleResume() {
            resumeWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.startAutoRotate() }
            resumeWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
        }
    }
}
