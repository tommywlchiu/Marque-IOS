import SwiftUI
import UIKit

/// The Garage hero for a car with studio renders (`CarRenderLibrary`): a
/// turntable of pre-rendered frames. Shows the resting still immediately,
/// then — once every frame is downloaded — drag horizontally to spin, with a
/// slow auto-rotate when idle that pauses on touch and resumes a couple of
/// seconds after release. Same gesture rules as `SpinnableCarModelView`: only
/// a mostly-horizontal drag is claimed, so vertical swipes still scroll.
struct RenderedCarSpinView: UIViewRepresentable {
    let still: UIImage
    let frames: [UIImage]?
    /// False under Reduce Motion: no ambient spin; dragging still works.
    var autoRotates: Bool = true

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(image: still)
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        context.coordinator.imageView = view
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        let coordinator = context.coordinator
        coordinator.autoRotates = autoRotates
        if let frames, coordinator.frames.count != frames.count {
            coordinator.frames = frames
            coordinator.show(coordinator.index)
            coordinator.startAutoRotate()
        } else if coordinator.frames.isEmpty {
            view.image = still
        }
        if !autoRotates { coordinator.stopAutoRotate() }
    }

    static func dismantleUIView(_ view: UIImageView, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var imageView: UIImageView?
        var frames: [UIImage] = []
        var index = 0
        var autoRotates = true
        private var timer: Timer?
        private var resumeWorkItem: DispatchWorkItem?
        private var dragStartIndex = 0

        func show(_ i: Int) {
            guard !frames.isEmpty else { return }
            index = ((i % frames.count) + frames.count) % frames.count
            imageView?.image = frames[index]
        }

        func startAutoRotate() {
            guard autoRotates, timer == nil, !frames.isEmpty else { return }
            // One full turn in ~18 s, like the live SceneKit model.
            timer = Timer.scheduledTimer(withTimeInterval: 18.0 / Double(frames.count), repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.show((self?.index ?? 0) + 1) }
            }
        }

        func stopAutoRotate() {
            timer?.invalidate()
            timer = nil
        }

        func invalidate() {
            resumeWorkItem?.cancel()
            stopAutoRotate()
        }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer, !frames.isEmpty else { return false }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y)
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                resumeWorkItem?.cancel()
                stopAutoRotate()
                dragStartIndex = index
            case .changed:
                // A drag across the full width turns the car about one and a
                // third times — the same feel as the SceneKit spin.
                let width = max(gesture.view?.bounds.width ?? 1, 1)
                let steps = Int((gesture.translation(in: gesture.view).x / width) * CGFloat(frames.count) * 1.2)
                show(dragStartIndex - steps)
            case .ended, .cancelled, .failed:
                resumeWorkItem?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.startAutoRotate() }
                resumeWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
            default:
                break
            }
        }
    }
}
