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
    /// Where the plates sit in each frame, if the car has them.
    var plates: CarRenderLibrary.PlateTrack? = nil
    /// The owner's plate; blank draws a plain plate (which still covers the
    /// placeholder text some models ship with). Private: the Garage only.
    var plateText: String = ""

    func makeUIView(context: Context) -> StageView {
        let view = StageView()
        view.plateText = plateText
        view.show(still, plates: plates?.frames.first)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        context.coordinator.stage = view
        return view
    }

    func updateUIView(_ view: StageView, context: Context) {
        let coordinator = context.coordinator
        view.plateText = plateText
        let platesChanged = coordinator.plates != plates
        coordinator.plates = plates
        if let frames, coordinator.frames.count != frames.count {
            coordinator.frames = frames
            coordinator.show(coordinator.index)
        } else if coordinator.frames.isEmpty {
            view.show(still, plates: plates?.frames.first)
        } else if platesChanged {
            coordinator.show(coordinator.index)
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
        private var plateLayers: [String: CALayer] = [:]
        private var placements: [String: CarRenderLibrary.PlateTrack.Placement] = [:]
        var plateText = "" {
            didSet { if plateText != oldValue { plateLayers.values.forEach { $0.removeFromSuperlayer() }; plateLayers = [:]; setNeedsLayout() } }
        }
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

        func show(_ image: UIImage, plates: [String: CarRenderLibrary.PlateTrack.Placement]? = nil) {
            placements = plates ?? [:]
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
            layoutPlates(in: car)
            CATransaction.commit()
        }

        /// Each visible plate: the plate artwork mapped onto its quad in this
        /// frame with a perspective transform, dimmed as it turns away.
        private func layoutPlates(in car: CGRect) {
            for (side, layer) in plateLayers where placements[side] == nil { layer.isHidden = true }
            for (side, placement) in placements where placement.quad.count == 4 {
                let quad = placement.quad.map { CGPoint(x: car.minX + $0[0] * car.width, y: car.minY + $0[1] * car.height) }
                let width = hypot(quad[1].x - quad[0].x, quad[1].y - quad[0].y)
                let height = hypot(quad[3].x - quad[0].x, quad[3].y - quad[0].y)
                guard width > 2, height > 1 else { plateLayers[side]?.isHidden = true; continue }
                let layer = plateLayers[side] ?? makePlateLayer(side: side, aspect: width / height)
                layer.isHidden = false
                layer.transform = CATransform3DIdentity
                layer.bounds = CGRect(origin: .zero, size: Self.plateArtSize)
                layer.position = .zero
                layer.transform = Self.transform(from: Self.plateArtSize, to: quad)
                layer.sublayers?.first?.opacity = Float(0.08 + (1 - placement.facing) * 0.45)
            }
        }

        private static let plateArtSize = CGSize(width: 300, height: 150)

        private func makePlateLayer(side: String, aspect: CGFloat) -> CALayer {
            let layer = CALayer()
            layer.anchorPoint = .zero
            layer.allowsEdgeAntialiasing = true
            layer.contents = LicensePlateArt.image(text: plateText, aspect: aspect).cgImage
            layer.contentsGravity = .resize
            let shade = CALayer()
            shade.backgroundColor = UIColor.black.cgColor
            shade.frame = CGRect(origin: .zero, size: Self.plateArtSize)
            layer.addSublayer(shade)
            self.layer.insertSublayer(layer, above: carView.layer)
            plateLayers[side] = layer
            return layer
        }

        /// The projective transform taking a size×size rect (origin at the
        /// layer's anchor) onto `quad` — top-left, top-right, bottom-right,
        /// bottom-left (Heckbert's square-to-quad mapping, scaled to `size`).
        static func transform(from size: CGSize, to quad: [CGPoint]) -> CATransform3D {
            let (p0, p1, p2, p3) = (quad[0], quad[1], quad[2], quad[3])
            let dx1 = p1.x - p2.x, dx2 = p3.x - p2.x, dx3 = p0.x - p1.x + p2.x - p3.x
            let dy1 = p1.y - p2.y, dy2 = p3.y - p2.y, dy3 = p0.y - p1.y + p2.y - p3.y
            let den = dx1 * dy2 - dx2 * dy1
            let g = den == 0 ? 0 : (dx3 * dy2 - dx2 * dy3) / den
            let h = den == 0 ? 0 : (dx1 * dy3 - dx3 * dy1) / den
            let a = p1.x - p0.x + g * p1.x, b = p3.x - p0.x + h * p3.x
            let d = p1.y - p0.y + g * p1.y, e = p3.y - p0.y + h * p3.y
            var t = CATransform3DIdentity
            t.m11 = a / size.width; t.m12 = d / size.width; t.m14 = g / size.width
            t.m21 = b / size.height; t.m22 = e / size.height; t.m24 = h / size.height
            t.m41 = p0.x; t.m42 = p0.y; t.m44 = 1
            return t
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var stage: StageView?
        var frames: [UIImage] = []
        var index = 0
        private var dragStartIndex = 0

        var plates: CarRenderLibrary.PlateTrack?

        func show(_ i: Int) {
            guard !frames.isEmpty else { return }
            index = ((i % frames.count) + frames.count) % frames.count
            stage?.show(frames[index], plates: plates.flatMap { index < $0.frames.count ? $0.frames[index] : nil })
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

/// A plain US-style plate: white, a thin navy border and the owner's
/// characters in navy, drawn at the plate's own aspect (some models' plate
/// recesses are European-width).
enum LicensePlateArt {
    static func image(text: String, aspect: CGFloat) -> UIImage {
        let height: CGFloat = 150
        let size = CGSize(width: max(height * min(max(aspect, 1.6), 5), 1), height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(white: 0.93, alpha: 1).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()
            let navy = UIColor(red: 0.08, green: 0.16, blue: 0.42, alpha: 1)
            navy.setStroke()
            let border = UIBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), cornerRadius: 9)
            border.lineWidth = 5
            border.stroke()
            let characters = text.uppercased().trimmingCharacters(in: .whitespaces)
            guard !characters.isEmpty else { return }
            var fontSize: CGFloat = 92
            var attributes: [NSAttributedString.Key: Any] = [:]
            var textSize = CGSize.zero
            repeat {
                attributes = [.font: UIFont.systemFont(ofSize: fontSize, weight: .heavy), .foregroundColor: navy]
                textSize = (characters as NSString).size(withAttributes: attributes)
                fontSize -= 4
            } while textSize.width > size.width * 0.86 && fontSize > 20
            (characters as NSString).draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                                          withAttributes: attributes)
        }
    }
}
