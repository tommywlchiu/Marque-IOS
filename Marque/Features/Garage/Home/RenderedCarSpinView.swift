import SwiftUI
import UIKit

/// The Garage hero for a car with studio renders (`CarRenderLibrary`): a
/// turntable of pre-rendered frames standing on a glossy floor. Shows the
/// resting still immediately and stays put; once every frame is downloaded,
/// drag horizontally to spin it. Only a mostly-horizontal drag is claimed
/// (same rule as `SpinnableCarModelView`), so vertical swipes still scroll.
struct RenderedCarSpinView: UIViewRepresentable {
    let still: UIImage
    let frames: [UIImage]?

    func makeUIView(context: Context) -> StageView {
        let view = StageView()
        view.show(still)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        context.coordinator.stage = view
        return view
    }

    func updateUIView(_ view: StageView, context: Context) {
        let coordinator = context.coordinator
        if let frames, coordinator.frames.count != frames.count {
            coordinator.frames = frames
            coordinator.show(coordinator.index)
        } else if coordinator.frames.isEmpty {
            view.show(still)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// The car, a soft contact shadow under it, and its reflection: the same
    /// frame mirrored below and fading out, updated with every frame shown.
    final class StageView: UIView {
        /// Reflection height as a fraction of the car's height.
        private static let reflectionFraction: CGFloat = 0.42

        /// Where a frame's tyres touch the floor: a line through the lowest
        /// opaque point in its left half and in its right half, in fractions
        /// of the image's size. Every frame shares one crop box, so the
        /// contact moves as the car turns — and in a three-quarter view the
        /// far wheel sits higher than the near one — so a single mirror line
        /// at the image's edge would float the reflection below the tyres.
        struct FloorLine {
            var left = CGPoint(x: 0, y: 1)
            var right = CGPoint(x: 1, y: 1)

            func y(at x: CGFloat) -> CGFloat {
                guard right.x > left.x else { return max(left.y, right.y) }
                return left.y + (right.y - left.y) * (x - left.x) / (right.x - left.x)
            }
        }

        private let carView = UIImageView()
        private let reflectionClip = UIView()
        private let reflectionView = UIImageView()
        private let reflectionFade = CAGradientLayer()
        private let shadow = CAGradientLayer()
        private var floorLines: [ObjectIdentifier: FloorLine] = [:]
        private var floorLine = FloorLine()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = true
            shadow.type = .radial
            shadow.colors = [UIColor.black.withAlphaComponent(0.55).cgColor, UIColor.clear.cgColor]
            shadow.startPoint = CGPoint(x: 0.5, y: 0.5)
            shadow.endPoint = CGPoint(x: 1, y: 1)
            layer.addSublayer(shadow)

            reflectionClip.clipsToBounds = true
            reflectionView.layer.anchorPoint = .zero
            reflectionView.alpha = 0.3
            reflectionClip.addSubview(reflectionView)
            reflectionFade.colors = [UIColor.black.cgColor, UIColor.clear.cgColor]
            reflectionClip.layer.mask = reflectionFade
            addSubview(reflectionClip)
            addSubview(carView)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func show(_ image: UIImage) {
            carView.image = image
            reflectionView.image = image
            let id = ObjectIdentifier(image)
            let line = floorLines[id] ?? Self.floorLine(of: image)
            floorLines[id] = line
            floorLine = line
            setNeedsLayout()
        }

        /// Reads the tyre contact points from a small alpha-only copy of the
        /// frame (cheap enough to do once per frame).
        private static func floorLine(of image: UIImage) -> FloorLine {
            guard let cg = image.cgImage else { return FloorLine() }
            let width = 96
            let height = max(1, Int(CGFloat(cg.height) * CGFloat(width) / CGFloat(cg.width)))
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
                  let data = context.data else { return FloorLine() }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            let alpha = data.bindMemory(to: UInt8.self, capacity: width * height)
            // Each column's lowest mostly-opaque point, in fractions of the
            // image (bitmap memory runs top row first).
            var bottoms: [CGPoint] = []
            for col in 0..<width {
                for row in stride(from: height - 1, through: 0, by: -1) where alpha[row * width + col] > 128 {
                    bottoms.append(CGPoint(x: (CGFloat(col) + 0.5) / CGFloat(width), y: CGFloat(row + 1) / CGFloat(height)))
                    break
                }
            }
            // The floor is the car's supporting line: the underside of its
            // convex hull. Its widest edge runs from tyre to tyre.
            var hull: [CGPoint] = []
            for p in bottoms {
                while hull.count >= 2 {
                    let o = hull[hull.count - 2], q = hull[hull.count - 1]
                    // y grows downward; keep only turns that bulge down.
                    guard (q.x - o.x) * (p.y - o.y) - (q.y - o.y) * (p.x - o.x) >= 0 else { break }
                    hull.removeLast()
                }
                hull.append(p)
            }
            guard let first = hull.first else { return FloorLine() }
            guard hull.count >= 2 else { return FloorLine(left: first, right: first) }
            let widest = (1..<hull.count).max { hull[$0].x - hull[$0 - 1].x < hull[$1].x - hull[$1 - 1].x }!
            return FloorLine(left: hull[widest - 1], right: hull[widest])
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let image = carView.image, image.size.width > 0, image.size.height > 0 else { return }
            // Fit the car plus its reflection inside our bounds, car on top.
            let r = Self.reflectionFraction
            let scale = min(bounds.width / image.size.width, bounds.height / (image.size.height * (1 + r)))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let car = CGRect(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height * (1 + r)) / 2,
                width: size.width, height: size.height
            )
            // The contact line in our coordinates: y = a + b·x.
            let left = CGPoint(x: car.minX + floorLine.left.x * size.width, y: car.minY + floorLine.left.y * size.height)
            let b = floorLine.right.x > floorLine.left.x
                ? (floorLine.right.y - floorLine.left.y) * size.height / ((floorLine.right.x - floorLine.left.x) * size.width)
                : 0
            let a = left.y - b * left.x
            let top = min(a + b * car.minX, a + b * car.maxX)
            let clip = CGRect(x: car.minX, y: top, width: car.width, height: size.height * r)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            carView.frame = car
            reflectionClip.frame = clip
            // Each column mirrored about its own point on the contact line
            // (x' = x, y' = 2(a + b·x) − y): a reflection that keeps verticals
            // vertical, mapped from the image's own coordinates into the clip.
            reflectionView.transform = .identity
            reflectionView.bounds = CGRect(origin: .zero, size: size)
            reflectionView.layer.position = .zero
            reflectionView.transform = CGAffineTransform(
                a: 1, b: 2 * b, c: 0, d: -1,
                tx: car.minX - clip.minX,
                ty: 2 * a + 2 * b * car.minX - car.minY - clip.minY
            )
            reflectionFade.frame = reflectionClip.bounds
            let midY = a + b * car.midX
            shadow.frame = CGRect(x: car.minX + car.width * 0.06, y: midY - car.height * 0.07,
                                  width: car.width * 0.88, height: car.height * 0.14)
            CATransaction.commit()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var stage: StageView?
        var frames: [UIImage] = []
        var index = 0
        private var dragStartIndex = 0

        func show(_ i: Int) {
            guard !frames.isEmpty else { return }
            index = ((i % frames.count) + frames.count) % frames.count
            stage?.show(frames[index])
        }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer, !frames.isEmpty else { return false }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y)
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                dragStartIndex = index
            case .changed:
                // A drag across the full width turns the car about one and a
                // third times — the same feel as the SceneKit spin.
                let width = max(gesture.view?.bounds.width ?? 1, 1)
                let steps = Int((gesture.translation(in: gesture.view).x / width) * CGFloat(frames.count) * 1.2)
                show(dragStartIndex - steps)
            default:
                break
            }
        }
    }
}
