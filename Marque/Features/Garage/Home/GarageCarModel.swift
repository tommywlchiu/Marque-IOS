import SceneKit
import UIKit

// The Garage hero's stand-in for a car with no usable photo: a stylized
// "clay model" built in code (no external assets), painted in the car's
// color and rendered on-device once per model/color. A short list of
// recognizable makes/models (e.g. Tesla Model 3) get a hand-tuned shape;
// everything else falls back to its generic body-style shape.

/// Side-profile dimensions (meters) for one body style. The car runs along +x
/// from the nose at x = 0; y is up; the shapes are extruded across z.
struct CarBodyProfile {
    var length: CGFloat = 4.8, width: CGFloat = 1.84
    var clearance: CGFloat = 0.17, wheelRadius: CGFloat = 0.36
    var frontAxle: CGFloat = 0.98, rearAxle: CGFloat = 3.78
    var noseHeight: CGFloat = 0.64, belt: CGFloat = 0.96, cowlX: CGFloat = 1.72
    var roofFrontX: CGFloat = 2.32, roofRearX: CGFloat = 3.28, roofHeight: CGFloat = 1.43
    var rearGlassBaseX: CGFloat = 3.98, deckHeight: CGFloat = 1.0, tailHeight: CGFloat = 0.98
    var hasRoof = true
    var hasBed = false
    /// False for a grille-less front fascia (most EVs).
    var hasGrille = true
    /// True for a full-width LED light bar instead of two boxed taillights.
    var hasTailLightBar = false

    /// The profile for a car: a hand-tuned shape for a short list of
    /// recognizable makes/models when there's a match, else the generic
    /// body-style shape. `modelKey(make:model:bodyStyle:)` is the matching
    /// identity — keep the two in sync.
    static func forCar(make: String, model: String, bodyStyle: String) -> CarBodyProfile {
        knownModels[normalizedKey(make: make, model: model)]?() ?? forBodyStyle(bodyStyle)
    }

    /// Cache/identity key for a car's rendered model: the known model's id
    /// when recognized (so e.g. a Tesla Model 3 gets its own render, distinct
    /// from a generic sedan), else the normalized body style.
    static func modelKey(make: String, model: String, bodyStyle: String) -> String {
        let key = normalizedKey(make: make, model: model)
        return knownModels[key] != nil ? key : CarModelRenderer.normalizedStyle(bodyStyle)
    }

    /// Lowercased, alphanumerics-only, so "Tesla"/"Model 3" matches
    /// "tesla"/"model3" regardless of spacing or punctuation.
    private static func normalizedKey(make: String, model: String) -> String {
        (make + " " + model).lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static let knownModels: [String: () -> CarBodyProfile] = [
        normalizedKey(make: "Tesla", model: "Model 3"): teslaModel3,
    ]

    /// Low, smooth EV fastback: closed nose (no grille), a glass roof panel
    /// (no painted roof band — `hasRoof = false` already renders the
    /// greenhouse's dark glass material all the way across the top, which is
    /// exactly what a glass-roof car looks like from the side), and a
    /// full-width light bar instead of boxed taillights.
    ///
    /// Dimensions below marked "spec" are the real 2019 Model 3's own
    /// figures (length/width/height/wheelbase/ground clearance/front+rear
    /// overhang — Tesla's published numbers, cross-checked against
    /// carexpert.com.au / evspecifications.com / carsguide.com.au, all
    /// agreeing). This is still a stylized 2D-profile extrusion, not the
    /// manufacturer's surface data, so it reads as a Model 3, not a replica —
    /// the only way to get the literal car is an on-device 3D scan of it
    /// (Object Capture), which this isn't. Everything marked "styling" is
    /// this renderer's own judgment, not a sourced figure.
    private static func teslaModel3() -> CarBodyProfile {
        var p = CarBodyProfile()
        p.length = 4.694; p.width = 1.849                 // spec
        p.clearance = 0.138                                // spec (ground clearance)
        p.wheelRadius = 0.33                               // styling (~18" wheel + tire)
        p.frontAxle = 0.868                                // spec (front overhang)
        p.rearAxle = p.length - 0.977                      // spec (rear overhang)
        // 0.58, not lower: SceneKit's shape tessellator renders a fully
        // empty (zero-geometry) body below ~0.53 here — a sharp cliff, not a
        // gradual degradation — verified by bisection in a standalone
        // harness. 0.58 clears it with margin and still reads as a
        // noticeably lower, sleeker nose than the sedan default (0.64).
        p.noseHeight = 0.58                                // styling, clamped by the cliff above
        p.belt = 0.93; p.cowlX = 1.55                      // styling
        p.roofFrontX = 2.05; p.roofRearX = 3.55            // styling
        p.roofHeight = 1.40                                // spec-anchored: total height 1.443
        p.rearGlassBaseX = 3.82; p.deckHeight = 0.92; p.tailHeight = 0.9  // styling
        p.hasRoof = false
        p.hasGrille = false
        p.hasTailLightBar = true
        return p
    }

    static func forBodyStyle(_ style: String) -> CarBodyProfile {
        var p = CarBodyProfile()
        switch style.lowercased() {
        case "coupe":
            p.length = 4.6; p.rearAxle = 3.62; p.noseHeight = 0.58; p.belt = 0.92
            p.roofFrontX = 2.25; p.roofRearX = 2.95; p.roofHeight = 1.32
            p.rearGlassBaseX = 3.95; p.deckHeight = 0.96; p.tailHeight = 0.95
        case "convertible":
            p.length = 4.6; p.rearAxle = 3.62; p.noseHeight = 0.58; p.belt = 0.92
            p.roofFrontX = 2.05; p.roofRearX = 2.1; p.roofHeight = 1.18
            p.rearGlassBaseX = 2.18; p.deckHeight = 0.96; p.tailHeight = 0.95; p.hasRoof = false
        case "hatchback":
            p.length = 4.25; p.frontAxle = 0.9; p.rearAxle = 3.5; p.cowlX = 1.55
            p.roofFrontX = 2.1; p.roofRearX = 3.75; p.roofHeight = 1.46
            p.rearGlassBaseX = 4.17; p.deckHeight = 1.0; p.tailHeight = 1.0
        case "wagon":
            p.roofRearX = 4.42; p.rearGlassBaseX = 4.74; p.deckHeight = 1.0; p.tailHeight = 1.0
        case "suv", "crossover":
            p.length = 4.75; p.width = 1.92; p.clearance = 0.25; p.wheelRadius = 0.42
            p.frontAxle = 0.98; p.rearAxle = 3.82; p.noseHeight = 0.86; p.belt = 1.14
            p.cowlX = 1.6; p.roofFrontX = 2.12; p.roofRearX = 4.3; p.roofHeight = 1.74
            p.rearGlassBaseX = 4.66; p.deckHeight = 1.15; p.tailHeight = 1.14
        case "pickup":
            p.length = 5.6; p.width = 1.98; p.clearance = 0.28; p.wheelRadius = 0.44
            p.frontAxle = 1.02; p.rearAxle = 4.55; p.noseHeight = 0.98; p.belt = 1.18
            p.cowlX = 1.7; p.roofFrontX = 2.2; p.roofRearX = 3.25; p.roofHeight = 1.88
            p.rearGlassBaseX = 3.32; p.deckHeight = 1.18; p.tailHeight = 1.18; p.hasBed = true
        case "van", "minivan":
            p.length = 5.05; p.width = 1.96; p.clearance = 0.2; p.wheelRadius = 0.38
            p.frontAxle = 0.95; p.rearAxle = 4.0; p.noseHeight = 0.78; p.belt = 1.08
            p.cowlX = 1.2; p.roofFrontX = 1.85; p.roofRearX = 4.72; p.roofHeight = 1.8
            p.rearGlassBaseX = 4.98; p.deckHeight = 1.1; p.tailHeight = 1.1
        default:  // sedan: a three-box shape — flatter, higher hood, upright
            // cabin with a long roof, and a distinct high trunk deck, so it
            // doesn't read as a coupe/fastback.
            p.noseHeight = 0.74; p.belt = 0.98; p.cowlX = 1.62
            p.roofFrontX = 2.22; p.roofRearX = 3.42; p.roofHeight = 1.44
            p.rearGlassBaseX = 3.98; p.deckHeight = 1.03; p.tailHeight = 1.01
        }
        return p
    }

    // Nose -> hood -> cowl -> beltline -> deck -> tail: the visible top/side
    // silhouette only (no wheel arches / underbody — CarBodyMesh opens those
    // itself via `archLift`, evaluated per spine sample). Sampled rather than
    // built as a CGPath (the old flat-extrusion approach) since CarBodyMesh
    // sweeps a true 3D cross-section along these points. The long near-flat
    // cowl -> rear-glass-base run is still sampled at a regular interval,
    // not jumped in one line: it's long enough to contain an axle position,
    // and a localized per-x effect like the arch lift needs nearby ring
    // samples or it linearly interpolates into a long diagonal ramp instead
    // of a notch — found by rendering and visually inspecting a first attempt
    // that skipped this (see the SCNShape zero-geometry pitfall's sibling:
    // always render and look, never trust the math alone).
    var sideSilhouette: [CGPoint] {
        let L = length, c = clearance, deckY = max(belt, deckHeight - 0.02)
        var pts: [CGPoint] = [CGPoint(x: 0.14, y: c + 0.07)]
        CarBodyMesh.sampleQuad(pts[0], CGPoint(x: -0.01, y: c + 0.1), CGPoint(x: 0.0, y: noseHeight - 0.14), steps: 10, into: &pts)
        CarBodyMesh.sampleQuad(pts.last!, CGPoint(x: 0.02, y: noseHeight + 0.04), CGPoint(x: 0.32, y: noseHeight + 0.05), steps: 8, into: &pts)
        CarBodyMesh.sampleQuad(pts.last!, CGPoint(x: cowlX - 0.45, y: belt - 0.01), CGPoint(x: cowlX, y: belt), steps: 14, into: &pts)
        let cabinRunStart = pts.last!
        let cabinSteps = max(1, Int((rearGlassBaseX - cabinRunStart.x) / 0.12))
        for i in 1...cabinSteps {
            let t = CGFloat(i) / CGFloat(cabinSteps)
            pts.append(CGPoint(x: cabinRunStart.x + (rearGlassBaseX - cabinRunStart.x) * t,
                                y: cabinRunStart.y + (deckY - cabinRunStart.y) * t))
        }
        if rearGlassBaseX < L - 0.3 {
            CarBodyMesh.sampleQuad(pts.last!, CGPoint(x: (rearGlassBaseX + L) / 2, y: deckHeight + 0.03), CGPoint(x: L - 0.12, y: deckHeight), steps: 10, into: &pts)
            CarBodyMesh.sampleQuad(pts.last!, CGPoint(x: L, y: deckHeight), CGPoint(x: L, y: tailHeight - 0.22), steps: 8, into: &pts)
        } else {
            CarBodyMesh.sampleQuad(pts.last!, CGPoint(x: L + 0.01, y: deckY), CGPoint(x: L, y: tailHeight - 0.22), steps: 10, into: &pts)
        }
        CarBodyMesh.sampleQuad(pts.last!, CGPoint(x: L + 0.02, y: c + 0.09), CGPoint(x: L - 0.1, y: c + 0.07), steps: 10, into: &pts)
        return pts
    }

    // Glass: windshield, side windows and rear window as one shape above the beltline.
    var greenhousePath: CGPath {
        let path = CGMutablePath()
        let baseY = max(belt, deckHeight - 0.02) - 0.02
        path.move(to: CGPoint(x: cowlX, y: belt - 0.02))
        path.addQuadCurve(to: CGPoint(x: roofFrontX, y: roofHeight), control: CGPoint(x: roofFrontX - 0.16, y: roofHeight))
        path.addQuadCurve(to: CGPoint(x: roofRearX, y: roofHeight), control: CGPoint(x: (roofFrontX + roofRearX) / 2, y: roofHeight + 0.03))
        path.addQuadCurve(to: CGPoint(x: rearGlassBaseX, y: baseY), control: CGPoint(x: min(roofRearX + 0.3, rearGlassBaseX), y: roofHeight))
        path.closeSubpath()
        return path
    }

    // Painted roof panel: a thin band along the top of the greenhouse.
    var roofPath: CGPath {
        let path = CGMutablePath()
        let n = 24
        let x0 = roofFrontX - 0.14, x1 = min(roofRearX + 0.18, rearGlassBaseX - 0.05)
        var top: [CGPoint] = []
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n)
            let edge = min(t, 1 - t)
            let drop = edge < 0.12 ? (0.12 - edge) * 0.8 : 0
            top.append(CGPoint(x: x0 + (x1 - x0) * t, y: roofHeight + 0.02 + 0.03 * sin(t * .pi) - drop))
        }
        path.move(to: top[0])
        top.dropFirst().forEach { path.addLine(to: $0) }
        top.reversed().forEach { path.addLine(to: CGPoint(x: $0.x, y: $0.y - 0.05)) }
        path.closeSubpath()
        return path
    }
}

// MARK: - Domed-cross-section body mesh
//
// A true 3D compound-curved body, not a flat extrusion: at every point along
// `CarBodyProfile.sideSilhouette`, instead of a flat line straight across the
// width, we sweep a cross-section that's full height at the centerline
// (z = 0, matching the tuned silhouette exactly) and domes downward toward
// the sides — like a real fender/roof's rounded shoulder. Width also varies
// along the body's length (narrow at the nose/tail tips, full width through
// the cabin) via `widthFactor`, and each cross-section opens a wheel-arch gap
// above the axles via `archLift`. A hand-built `SCNGeometry` (explicit
// positions, smooth per-vertex normals, triangle indices) rather than
// `SCNShape` — sidesteps the SCNShape zero-geometry cliff entirely, as a side
// benefit. Every cross-section is a closed loop (dome arc + two floor
// corners, not a single collapsed centerline point) — an earlier version
// that collapsed both side walls to one point per spine sample went
// degenerate wherever the half-width was small (nose/tail), producing a
// self-intersecting "hook" visible from the side and a bowtie-shaped
// silhouette head-on; found only by rendering multiple camera angles and
// looking at the actual pixels, not by inspecting the math.
enum CarBodyMesh {
    static func quadPoint(_ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint, _ t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let x = mt * mt * p0.x + 2 * mt * t * c.x + t * t * p1.x
        let y = mt * mt * p0.y + 2 * mt * t * c.y + t * t * p1.y
        return CGPoint(x: x, y: y)
    }

    static func sampleQuad(_ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint, steps: Int, into out: inout [CGPoint]) {
        for i in 1...steps { out.append(quadPoint(p0, c, p1, CGFloat(i) / CGFloat(steps))) }
    }

    private static func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = max(0, min(1, (x - a) / max(b - a, 0.0001)))
        return t * t * (3 - 2 * t)
    }

    /// 0...1 fraction of full half-width at this point along the body's
    /// length. Seen from above a car is a rounded rectangle — nearly full
    /// width right up to the bumpers, with rounded corners — not a pointed
    /// hull: a long taper left the headlights, taillights and grille (which
    /// sit near the outer corners) floating in the air past the body.
    /// The body's half-width at x — trim pieces (lights, bar) are placed
    /// against this so they sit on the surface instead of floating past it.
    static func halfWidth(at x: CGFloat, _ p: CarBodyProfile) -> CGFloat {
        (p.width / 2) * widthFactor(x: x, length: p.length)
    }

    private static func widthFactor(x: CGFloat, length: CGFloat) -> CGFloat {
        func corner(_ d: CGFloat, radius: CGFloat, minimum: CGFloat) -> CGFloat {
            let t = max(0, min(1, d / radius))
            return minimum + (1 - minimum) * sqrt(1 - (1 - t) * (1 - t))
        }
        return min(corner(x, radius: 0.55, minimum: 0.7), corner(length - x, radius: 0.45, minimum: 0.75))
    }

    /// How far the cross-section domes downward (in meters) at the full
    /// half-width edge, relative to the centerline silhouette height.
    private static func dropAmount(y: CGFloat, p: CarBodyProfile) -> CGFloat {
        let bulgeY = p.clearance + 0.3
        if y < bulgeY {
            // Lower body (doors/rocker area): modest shoulder taper.
            return 0.05
        } else {
            // Hood/deck/greenhouse-base area: a bit more dome, like a
            // crowned hood or a rounded decklid.
            return 0.07
        }
    }

    /// How far (in meters, above `clearance`) to lift the cross-section's
    /// outer edges and floor at this x, to open a wheel-arch gap above each
    /// axle — the same semicircle (centered at wheel height, radius
    /// wheelRadius + 0.07) the old flat extrusion cut as a notch into its 2D
    /// profile, just evaluated as a lift instead of a path cut.
    private static func archLift(x: CGFloat, p: CarBodyProfile) -> CGFloat {
        let c = p.clearance, cy = p.wheelRadius, r = p.wheelRadius + 0.07
        let dxMax = sqrt(max(0, r * r - (cy - c) * (cy - c)))
        var lift: CGFloat = 0
        for axle in [p.frontAxle, p.rearAxle] {
            let ddx = x - axle
            guard abs(ddx) < dxMax else { continue }
            let ceiling = cy + sqrt(max(0, r * r - ddx * ddx))
            lift = max(lift, ceiling - c)
        }
        return lift
    }

    static func lowerBody(_ p: CarBodyProfile, ringSamples: Int = 19) -> SCNGeometry {
        let spine = p.sideSilhouette
        let m = spine.count

        var positions: [SCNVector3] = []
        var topRingIndex: [[Int32]] = []  // [spineIndex][ringJ] -> vertex index, top dome arc
        var bottomLeftIndex: [Int32] = [] // [spineIndex] -> vertex index, floor corner at z = -hw
        var bottomRightIndex: [Int32] = [] // [spineIndex] -> vertex index, floor corner at z = +hw

        // bottomLeft/Right sit directly under the arc's own edges (same z as
        // ring[0]/ring[last]), so every side wall is a true vertical strip —
        // no point collapses onto another spine index's geometry.
        for i in 0..<m {
            let pt = spine[i]
            let hw = (p.width / 2) * widthFactor(x: pt.x, length: p.length)
            let drop = dropAmount(y: pt.y, p: p)
            let lift = archLift(x: pt.x, p: p)
            var ring: [Int32] = []
            for j in 0..<ringSamples {
                let s = -1 + 2 * CGFloat(j) / CGFloat(ringSamples - 1)  // -1...1
                let z = s * hw
                // Lift blends in toward the edges (s*s) and leaves the
                // centerline (s=0, the hood/beltline silhouette) untouched —
                // only the outer edges open up for the wheel arch.
                let y = max(pt.y - drop * (s * s), p.clearance + lift * (s * s))
                positions.append(SCNVector3(Float(pt.x), Float(y), Float(z)))
                ring.append(Int32(positions.count - 1))
            }
            topRingIndex.append(ring)
            let floorY = p.clearance + lift
            positions.append(SCNVector3(Float(pt.x), Float(floorY), Float(-hw)))
            bottomLeftIndex.append(Int32(positions.count - 1))
            positions.append(SCNVector3(Float(pt.x), Float(floorY), Float(hw)))
            bottomRightIndex.append(Int32(positions.count - 1))
        }

        var indices: [Int32] = []
        func quad(_ a: Int32, _ b: Int32, _ c: Int32, _ d: Int32) {
            indices.append(contentsOf: [a, b, c, a, c, d])
        }

        // Top dome surface between consecutive spine rings.
        for i in 0..<(m - 1) {
            for j in 0..<(ringSamples - 1) {
                let a = topRingIndex[i][j], b = topRingIndex[i][j + 1]
                let c = topRingIndex[i + 1][j + 1], d = topRingIndex[i + 1][j]
                quad(a, b, c, d)
            }
        }
        // Side walls: top ring edge (j=0 and j=last) down to its own floor corner.
        for i in 0..<(m - 1) {
            let aTop0 = topRingIndex[i][0], bTop0 = topRingIndex[i + 1][0]
            quad(aTop0, bottomLeftIndex[i], bottomLeftIndex[i + 1], bTop0)
            let lastJ = ringSamples - 1
            let aTopL = topRingIndex[i][lastJ], bTopL = topRingIndex[i + 1][lastJ]
            quad(bottomRightIndex[i], aTopL, bTopL, bottomRightIndex[i + 1])
        }
        // Flat floor between the two side walls — never seen from this
        // hero's camera angles, but a proper (non-degenerate) loft quad.
        for i in 0..<(m - 1) {
            quad(bottomLeftIndex[i], bottomRightIndex[i], bottomRightIndex[i + 1], bottomLeftIndex[i + 1])
        }
        // Nose and tail end caps: fan the closed loop from its bottomLeft corner.
        func cap(spineIndex: Int, reversed: Bool) {
            var loop: [Int32] = [bottomLeftIndex[spineIndex]]
            loop.append(contentsOf: topRingIndex[spineIndex])
            loop.append(bottomRightIndex[spineIndex])
            let apex = loop[0]
            for k in 1..<(loop.count - 1) {
                let a = loop[k], b = loop[k + 1]
                if reversed { quad(apex, b, a, a) } else { quad(apex, a, b, b) }
            }
        }
        cap(spineIndex: 0, reversed: true)
        cap(spineIndex: m - 1, reversed: false)

        var normalAccum = [SCNVector3](repeating: SCNVector3Zero, count: positions.count)
        var t = 0
        while t < indices.count {
            let ia = Int(indices[t]), ib = Int(indices[t + 1]), ic = Int(indices[t + 2])
            let a = positions[ia], b = positions[ib], c = positions[ic]
            let e1 = SCNVector3(b.x - a.x, b.y - a.y, b.z - a.z)
            let e2 = SCNVector3(c.x - a.x, c.y - a.y, c.z - a.z)
            let n = SCNVector3(e1.y * e2.z - e1.z * e2.y, e1.z * e2.x - e1.x * e2.z, e1.x * e2.y - e1.y * e2.x)
            for idx in [ia, ib, ic] {
                normalAccum[idx] = SCNVector3(normalAccum[idx].x + n.x, normalAccum[idx].y + n.y, normalAccum[idx].z + n.z)
            }
            t += 3
        }
        let normals: [SCNVector3] = normalAccum.map { n in
            let len = sqrt(n.x * n.x + n.y * n.y + n.z * n.z)
            return len > 0.0001 ? SCNVector3(n.x / len, n.y / len, n.z / len) : SCNVector3(0, 1, 0)
        }

        let source = SCNGeometrySource(vertices: positions)
        let normalSource = SCNGeometrySource(normals: normals)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [source, normalSource], elements: [element])
    }
}

enum ProceduralCarModel {
    private static func vec(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> SCNVector3 {
        SCNVector3(Float(x), Float(y), Float(z))
    }

    /// Internal (not fileprivate): SpinnableCarModelView builds a live scene
    /// from the same node graph as the static bake below.
    static func node(for p: CarBodyProfile, paint color: UIColor) -> SCNNode {
        let car = SCNNode()
        let paint = paintMaterial(color)
        paint.isDoubleSided = true
        add(CarBodyMesh.lowerBody(p), paint, to: car)
        add(shape(p.greenhousePath, depth: p.width * 0.84, chamfer: 0.08),
            material(UIColor(white: 0.03, alpha: 1), metalness: 0.3, roughness: 0.06), to: car)
        if p.hasRoof {
            add(shape(p.roofPath, depth: p.width * 0.84 + 0.02, chamfer: 0.025), paint, to: car)
        }
        let trim = material(UIColor(white: 0.05, alpha: 1), metalness: 0.1, roughness: 0.55)
        if p.hasBed {
            // open cargo bed: a dark recess just below the bed rails
            let bedLength = p.length - p.rearGlassBaseX - 0.22
            let bed = SCNNode(geometry: SCNBox(width: bedLength, height: 0.04, length: p.width - 0.22, chamferRadius: 0.02))
            bed.geometry?.materials = [trim]
            bed.position = vec(p.rearGlassBaseX + 0.1 + bedLength / 2, p.deckHeight + 0.005, 0)
            car.addChildNode(bed)
        }
        // rocker trim between the arches
        let rocker = SCNNode(geometry: SCNBox(width: p.rearAxle - p.frontAxle - 2 * (p.wheelRadius + 0.1), height: 0.09, length: p.width + 0.01, chamferRadius: 0.03))
        rocker.geometry?.materials = [trim]
        rocker.position = vec((p.frontAxle + p.rearAxle) / 2, p.clearance + 0.05, 0)
        car.addChildNode(rocker)
        if p.hasGrille {
            let grille = SCNNode(geometry: SCNBox(width: 0.06, height: 0.15, length: p.width * 0.55, chamferRadius: 0.04))
            grille.geometry?.materials = [trim]
            grille.position = vec(0.02, p.clearance + 0.19, 0)
            car.addChildNode(grille)
        }
        let tailMaterial = material(UIColor(red: 0.5, green: 0, blue: 0, alpha: 1), metalness: 0, roughness: 0.2)
        tailMaterial.emission.contents = UIColor(red: 0.75, green: 0.03, blue: 0.03, alpha: 1)
        // Lights sit against the body's own width at each end (it narrows
        // into rounded corners), so they read as part of the surface.
        let noseHalfWidth = CarBodyMesh.halfWidth(at: 0.05, p)
        let tailHalfWidth = CarBodyMesh.halfWidth(at: p.length - 0.02, p)
        if p.hasTailLightBar {
            let bar = SCNNode(geometry: SCNBox(width: 0.05, height: 0.045, length: 2 * tailHalfWidth - 0.1, chamferRadius: 0.018))
            bar.geometry?.materials = [tailMaterial]
            bar.position = vec(p.length - 0.01, p.tailHeight - 0.13, 0)
            car.addChildNode(bar)
        }
        for side in [CGFloat(1), -1] {
            let head = SCNNode(geometry: SCNBox(width: 0.16, height: 0.06, length: 0.44, chamferRadius: 0.03))
            let hm = material(.white, metalness: 0, roughness: 0.2); hm.emission.contents = UIColor(white: 0.95, alpha: 1)
            head.geometry?.materials = [hm]
            head.position = vec(0.1, p.noseHeight - 0.05, side * (noseHalfWidth - 0.24))
            head.eulerAngles.z = 0.3
            car.addChildNode(head)
            if !p.hasTailLightBar {
                let tail = SCNNode(geometry: SCNBox(width: 0.06, height: 0.07, length: 0.42, chamferRadius: 0.02))
                tail.geometry?.materials = [tailMaterial]
                tail.position = vec(p.length - 0.005, p.tailHeight - 0.13, side * (tailHalfWidth - 0.24))
                car.addChildNode(tail)
            }
            for axle in [p.frontAxle, p.rearAxle] {
                car.addChildNode(wheel(radius: p.wheelRadius, at: vec(axle, p.wheelRadius, side * (p.width / 2 - 0.13)), outward: side))
            }
        }
        return car
    }

    private static func wheel(radius: CGFloat, at position: SCNVector3, outward: CGFloat) -> SCNNode {
        let wheel = SCNNode(); wheel.position = position
        let tire = SCNNode(geometry: SCNCylinder(radius: radius, height: 0.24))
        tire.geometry?.materials = [material(UIColor(white: 0.04, alpha: 1), metalness: 0, roughness: 0.9)]
        tire.eulerAngles.x = .pi / 2
        wheel.addChildNode(tire)
        let rimR = radius * 0.66
        let face = SCNNode(geometry: SCNCylinder(radius: rimR, height: 0.02))
        face.geometry?.materials = [material(UIColor(white: 0.12, alpha: 1), metalness: 0.6, roughness: 0.4)]
        face.eulerAngles.x = .pi / 2
        face.position = vec(0, 0, outward * 0.115)
        wheel.addChildNode(face)
        let silver = material(UIColor(white: 0.78, alpha: 1), metalness: 1, roughness: 0.22)
        for i in 0..<5 {
            let spoke = SCNNode(geometry: SCNBox(width: 0.055, height: rimR * 2 * 0.96, length: 0.03, chamferRadius: 0.012))
            spoke.geometry?.materials = [silver]
            spoke.position = vec(0, 0, outward * 0.128)
            spoke.eulerAngles.z = Float(i) * .pi / 5
            wheel.addChildNode(spoke)
        }
        let lip = SCNNode(geometry: SCNTube(innerRadius: rimR - 0.025, outerRadius: rimR, height: 0.03))
        lip.geometry?.materials = [silver]
        lip.eulerAngles.x = .pi / 2
        lip.position = vec(0, 0, outward * 0.128)
        wheel.addChildNode(lip)
        let hub = SCNNode(geometry: SCNCylinder(radius: 0.045, height: 0.04))
        hub.geometry?.materials = [silver]
        hub.eulerAngles.x = .pi / 2
        hub.position = vec(0, 0, outward * 0.135)
        wheel.addChildNode(hub)
        return wheel
    }

    private static func add(_ geometry: SCNGeometry, _ m: SCNMaterial, to parent: SCNNode) {
        geometry.materials = [m]
        parent.addChildNode(SCNNode(geometry: geometry))
    }

    private static func shape(_ path: CGPath, depth: CGFloat, chamfer: CGFloat) -> SCNShape {
        let b = UIBezierPath(cgPath: path)
        b.flatness = 0.005
        let s = SCNShape(path: b, extrusionDepth: depth)
        s.chamferRadius = chamfer
        s.chamferMode = .both
        let profile = UIBezierPath()
        profile.move(to: CGPoint(x: 0, y: 1))
        profile.addCurve(to: CGPoint(x: 1, y: 0), controlPoint1: CGPoint(x: 0.55, y: 1), controlPoint2: CGPoint(x: 1, y: 0.55))
        s.chamferProfile = profile
        return s
    }

    private static func paintMaterial(_ color: UIColor) -> SCNMaterial {
        let m = material(color, metalness: 0.35, roughness: 0.22)
        m.clearCoat.contents = 1.0
        m.clearCoatRoughness.contents = 0.04
        return m
    }

    private static func material(_ color: UIColor, metalness: CGFloat, roughness: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metalness
        m.roughness.contents = roughness
        return m
    }
}

// MARK: - Paint

/// Maps the free-text `Car.color` ("Silver", "Dark Blue", "Pearl White") to a
/// paint. Unknown or empty colors get a neutral silver.
enum CarPaint {
    private static let table: [(keywords: [String], color: UIColor)] = [
        (["black", "onyx", "obsidian", "ebony"], UIColor(white: 0.06, alpha: 1)),
        (["white", "pearl", "ivory", "alpine", "chalk"], UIColor(white: 0.93, alpha: 1)),
        (["charcoal", "gunmetal", "graphite"], UIColor(white: 0.22, alpha: 1)),
        (["gray", "grey", "slate"], UIColor(white: 0.42, alpha: 1)),
        (["silver", "platinum", "titanium", "aluminum"], UIColor(white: 0.62, alpha: 1)),
        (["burgundy", "maroon", "wine"], UIColor(red: 0.36, green: 0.04, blue: 0.08, alpha: 1)),
        (["red", "crimson", "ruby", "scarlet"], UIColor(red: 0.62, green: 0.05, blue: 0.07, alpha: 1)),
        (["orange"], UIColor(red: 0.85, green: 0.33, blue: 0.05, alpha: 1)),
        (["yellow"], UIColor(red: 0.92, green: 0.75, blue: 0.08, alpha: 1)),
        (["gold", "champagne"], UIColor(red: 0.72, green: 0.6, blue: 0.38, alpha: 1)),
        (["bronze", "copper"], UIColor(red: 0.5, green: 0.3, blue: 0.16, alpha: 1)),
        (["brown", "mocha", "espresso"], UIColor(red: 0.3, green: 0.18, blue: 0.1, alpha: 1)),
        (["beige", "tan", "sand", "khaki"], UIColor(red: 0.72, green: 0.65, blue: 0.52, alpha: 1)),
        (["navy", "midnight"], UIColor(red: 0.06, green: 0.1, blue: 0.26, alpha: 1)),
        (["teal", "turquoise", "cyan", "aqua"], UIColor(red: 0.05, green: 0.45, blue: 0.5, alpha: 1)),
        (["blue", "sapphire", "cobalt"], UIColor(red: 0.1, green: 0.26, blue: 0.62, alpha: 1)),
        (["green", "emerald", "olive", "forest", "sage"], UIColor(red: 0.12, green: 0.33, blue: 0.18, alpha: 1)),
        (["purple", "violet", "plum"], UIColor(red: 0.3, green: 0.12, blue: 0.42, alpha: 1)),
        (["pink", "rose"], UIColor(red: 0.85, green: 0.45, blue: 0.55, alpha: 1)),
    ]
    static let fallback = UIColor(white: 0.62, alpha: 1)

    static func color(for name: String) -> UIColor {
        let lowered = name.lowercased()
        var color = table.first(where: { $0.keywords.contains(where: lowered.contains) })?.color ?? fallback
        if lowered.contains("dark") { color = color.adjusted(by: 0.55) }
        if lowered.contains("light") { color = color.adjusted(by: 1.35) }
        return color
    }
}

private extension UIColor {
    func adjusted(by factor: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: min(r * factor, 1), green: min(g * factor, 1), blue: min(b * factor, 1), alpha: a)
    }

    var cacheKey: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - Renderer

/// Renders a body style in a paint color to a transparent, tightly cropped
/// image at a 3/4 front angle. Cached on disk (Caches/GarageHeroModels) keyed
/// by style + color + `version`, so each combination renders once per device.
enum CarModelRenderer {
    /// Bump when the model or lighting changes, to retire old cached renders.
    private static let version = 6
    /// Rendered image size, in pixels (the renderer is given a pixel size and
    /// the result is re-wrapped at scale 1 — see the image-size pitfall).
    private static let renderSize = CGSize(width: 2400, height: 1200)

    private static var cacheDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("GarageHeroModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func normalizedStyle(_ bodyStyle: String) -> String {
        let style = bodyStyle.lowercased()
        let known = ["sedan", "coupe", "convertible", "hatchback", "wagon", "suv", "crossover", "pickup", "van", "minivan"]
        return known.contains(style) ? style : "sedan"
    }

    private static func cacheURL(style: String, paint: UIColor) -> URL {
        cacheDirectory.appendingPathComponent("\(style)-\(paint.cacheKey)-v\(version).png")
    }

    /// Synchronous disk probe, for painting a cached render on the first frame.
    static func cachedImage(for car: Car) -> UIImage? {
        let key = CarBodyProfile.modelKey(make: car.make, model: car.model, bodyStyle: car.bodyStyle)
        let url = cacheURL(style: key, paint: CarPaint.color(for: car.color))
        return UIImage(contentsOfFile: url.path)
    }

    static func image(for car: Car) async -> UIImage? {
        let key = CarBodyProfile.modelKey(make: car.make, model: car.model, bodyStyle: car.bodyStyle)
        let profile = CarBodyProfile.forCar(make: car.make, model: car.model, bodyStyle: car.bodyStyle)
        let paint = CarPaint.color(for: car.color)
        let url = cacheURL(style: key, paint: paint)
        if let cached = UIImage(contentsOfFile: url.path) { return cached }
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            // A hand-tuned profile's numbers can, in principle, hit a
            // SceneKit shape-tessellation edge case that renders nothing at
            // all (verified once, for too-tight a nose curve — see the
            // comment on `teslaModel3`). Never ship that as a blank hero:
            // fall back to the plain body-style shape, which is always
            // within known-safe bounds, and cache the fallback under the
            // same key so a transient failure doesn't retry every load.
            let image = render(profile: profile, paint: paint)
                ?? render(profile: CarBodyProfile.forBodyStyle(car.bodyStyle), paint: paint)
            guard let image else { return nil }
            if let data = image.pngData() { try? data.write(to: url, options: .atomic) }
            return image
        }.value
    }

    private static func render(profile: CarBodyProfile, paint: UIColor) -> UIImage? {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scene.lightingEnvironment.contents = studioEnvironment()
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
        camera.camera?.fieldOfView = 17
        camera.camera?.wantsHDR = true
        camera.position = SCNVector3(0, 1.7, 14)
        camera.look(at: SCNVector3(0, 0.7, 0))
        scene.rootNode.addChildNode(camera)

        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        let snapshot = renderer.snapshot(atTime: 0, with: renderSize, antialiasingMode: .multisampling4X)
        guard let cgImage = snapshot.cgImage, let cropped = cropToOpaque(cgImage) else { return nil }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    /// A dark studio with an overhead softbox and a few vertical strips, so the
    /// clear coat picks up highlights. Internal (not private): reused by
    /// SpinnableCarModelView's live scene for the same lighting look.
    static func studioEnvironment() -> UIImage {
        let size = CGSize(width: 1024, height: 512)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let colors = [UIColor(white: 0.08, alpha: 1).cgColor, UIColor(white: 0.55, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
            }
            UIColor.white.setFill()
            cg.fill(CGRect(x: 0, y: size.height * 0.06, width: size.width, height: size.height * 0.1))
            UIColor(white: 0.8, alpha: 1).setFill()
            for x in [0.12, 0.42, 0.62, 0.9] {
                cg.fill(CGRect(x: size.width * x, y: size.height * 0.24, width: size.width * 0.05, height: size.height * 0.26))
            }
        }
    }

    /// Trims the transparent margin so the car fills the image.
    private static func cropToOpaque(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let pad = 8
        let rect = CGRect(x: max(minX - pad, 0), y: max(minY - pad, 0),
                          width: min(maxX + pad, width - 1) - max(minX - pad, 0) + 1,
                          height: min(maxY + pad, height - 1) - max(minY - pad, 0) + 1)
        return image.cropping(to: rect)
    }
}
