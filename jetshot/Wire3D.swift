//
//  Wire3D.swift
//  jetshot
//
//  A small wireframe 3D renderer for the story cinematics.
//
//  The game is all neon vector, so the cutscenes are too: real perspective
//  projection of 3D line meshes, depth fog, near-plane clipping and a moving
//  camera, drawn with nothing but SpriteKit sprites. Every edge is one pooled
//  sprite stretched over a soft "light tube" texture, so a frame of a thousand
//  lines is a single batched draw call and nothing is allocated per frame —
//  no CGPaths, no shape nodes, no tessellation.
//

import SpriteKit
import simd

typealias Vec3 = SIMD3<Float>

// MARK: - Math helpers

nonisolated func clamp01(_ x: Float) -> Float { min(1, max(0, x)) }

nonisolated func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

nonisolated func lerp(_ a: Vec3, _ b: Vec3, _ t: Float) -> Vec3 { a + (b - a) * t }

/// Hermite ease between two edges, like GLSL's `smoothstep`.
nonisolated func smooth(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = clamp01((x - edge0) / (edge1 - edge0))
    return t * t * (3 - 2 * t)
}

nonisolated func easeOut(_ t: Float) -> Float {
    let u = 1 - clamp01(t)
    return 1 - u * u * u
}

nonisolated func easeIn(_ t: Float) -> Float {
    let u = clamp01(t)
    return u * u * u
}

nonisolated func easeInOut(_ t: Float) -> Float { smooth(0, 1, t) }

/// Rotation about an arbitrary axis.
nonisolated func rotation(_ angle: Float, _ axis: Vec3) -> simd_quatf {
    simd_quatf(angle: angle, axis: simd_normalize(axis))
}

/// Yaw (about Y), then pitch (about X), then roll (about Z).
nonisolated func rotation(yaw: Float, pitch: Float = 0, roll: Float = 0) -> simd_quatf {
    rotation(yaw, Vec3(0, 1, 0)) * rotation(pitch, Vec3(1, 0, 0)) * rotation(roll, Vec3(0, 0, 1))
}

nonisolated let identityRotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

/// A point on a sphere from two angles (latitude from the +Y pole, longitude).
nonisolated func spherePoint(radius: Float, theta: Float, phi: Float) -> Vec3 {
    Vec3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi)) * radius
}

/// Deterministic random numbers, so every frame of a shot can recompute the same
/// layout from scratch instead of storing it.
struct StoryRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }

    mutating func float(_ range: ClosedRange<Float>) -> Float {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit()
    }

    /// A uniformly distributed direction.
    mutating func direction() -> Vec3 {
        let z = float(-1...1)
        let a = float(0...(2 * .pi))
        let r = (1 - z * z).squareRoot()
        return Vec3(r * cos(a), z, r * sin(a))
    }

    /// A roughly Gaussian value (sum of uniforms), mean 0, about unit spread.
    mutating func gaussian() -> Float {
        (unit() + unit() + unit() + unit() - 2) * 1.7
    }
}

// MARK: - Meshes

/// Vertices plus the edges between them. Faces only matter while building.
struct WireMesh {
    var vertices: [Vec3]
    var edges: [(Int, Int)]

    /// Unique edges of a triangle list.
    static func fromFaces(_ vertices: [Vec3], _ faces: [(Int, Int, Int)]) -> WireMesh {
        var seen = Set<Int>()
        var edges: [(Int, Int)] = []
        let n = vertices.count
        for (a, b, c) in faces {
            for (i, j) in [(a, b), (b, c), (c, a)] {
                let key = min(i, j) * n + max(i, j)
                if seen.insert(key).inserted { edges.append((i, j)) }
            }
        }
        return WireMesh(vertices: vertices, edges: edges)
    }

    private static let icoFaces: [(Int, Int, Int)] = [
        (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11),
        (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
        (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9),
        (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)
    ]

    private static func icoVertices() -> [Vec3] {
        let t: Float = (1 + Float(5).squareRoot()) / 2
        return [
            Vec3(-1, t, 0), Vec3(1, t, 0), Vec3(-1, -t, 0), Vec3(1, -t, 0),
            Vec3(0, -1, t), Vec3(0, 1, t), Vec3(0, -1, -t), Vec3(0, 1, -t),
            Vec3(t, 0, -1), Vec3(t, 0, 1), Vec3(-t, 0, -1), Vec3(-t, 0, 1)
        ].map { simd_normalize($0) }
    }

    /// A geodesic sphere: an icosahedron with each face split `subdivisions` times.
    static func geodesic(radius: Float, subdivisions: Int) -> WireMesh {
        var vertices = icoVertices()
        var faces = icoFaces
        for _ in 0..<max(0, subdivisions) {
            var cache: [Int: Int] = [:]
            func midpoint(_ a: Int, _ b: Int) -> Int {
                let key = min(a, b) * 100_000 + max(a, b)
                if let index = cache[key] { return index }
                vertices.append(simd_normalize((vertices[a] + vertices[b]) * 0.5))
                cache[key] = vertices.count - 1
                return vertices.count - 1
            }
            var next: [(Int, Int, Int)] = []
            for (a, b, c) in faces {
                let ab = midpoint(a, b), bc = midpoint(b, c), ca = midpoint(c, a)
                next += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
            }
            faces = next
        }
        return fromFaces(vertices.map { $0 * radius }, faces)
    }

    /// An icosahedron with a spike raised out of every face — the silhouette of a
    /// hostile quantum entity.
    static func spiked(radius: Float, spike: Float) -> WireMesh {
        let base = icoVertices()
        var vertices = base.map { $0 * radius }
        var edges = fromFaces(vertices, icoFaces).edges
        for (a, b, c) in icoFaces {
            let tip = simd_normalize(base[a] + base[b] + base[c]) * radius * spike
            vertices.append(tip)
            let index = vertices.count - 1
            edges += [(index, a), (index, b), (index, c)]
        }
        return WireMesh(vertices: vertices, edges: edges)
    }

    static func octahedron(radius r: Float) -> WireMesh {
        let v = [Vec3(r, 0, 0), Vec3(-r, 0, 0), Vec3(0, r, 0), Vec3(0, -r, 0), Vec3(0, 0, r), Vec3(0, 0, -r)]
        return fromFaces(v, [(0, 2, 4), (0, 4, 3), (0, 3, 5), (0, 5, 2), (1, 2, 5), (1, 5, 3), (1, 3, 4), (1, 4, 2)])
    }

    static func box(_ half: Vec3) -> WireMesh {
        var v: [Vec3] = []
        for x in [-half.x, half.x] { for y in [-half.y, half.y] { for z in [-half.z, half.z] { v.append(Vec3(x, y, z)) } } }
        var edges: [(Int, Int)] = []
        for i in 0..<8 { for bit in [1, 2, 4] where i & bit == 0 { edges.append((i, i | bit)) } }
        return WireMesh(vertices: v, edges: edges)
    }

    /// Latitude rings plus meridians.
    static func globe(radius: Float, rings: Int, meridians: Int, segments: Int = 32) -> WireMesh {
        var vertices: [Vec3] = []
        var edges: [(Int, Int)] = []
        for ring in 1..<rings {
            let theta = Float(ring) / Float(rings) * .pi
            let start = vertices.count
            for s in 0..<segments {
                vertices.append(spherePoint(radius: radius, theta: theta, phi: Float(s) / Float(segments) * 2 * .pi))
                edges.append((start + s, start + (s + 1) % segments))
            }
        }
        let steps = rings * 2
        for m in 0..<meridians {
            let phi = Float(m) / Float(meridians) * 2 * .pi
            let start = vertices.count
            for s in 0...steps {
                vertices.append(spherePoint(radius: radius, theta: Float(s) / Float(steps) * .pi, phi: phi))
                if s > 0 { edges.append((start + s - 1, start + s)) }
            }
        }
        return WireMesh(vertices: vertices, edges: edges)
    }

    /// A circle in the XZ plane, optionally with tick marks pointing outwards.
    static func ring(radius: Float, segments: Int, ticks: Int = 0, tickLength: Float = 0) -> WireMesh {
        var vertices: [Vec3] = []
        var edges: [(Int, Int)] = []
        for s in 0..<segments {
            let a = Float(s) / Float(segments) * 2 * .pi
            vertices.append(Vec3(cos(a), 0, sin(a)) * radius)
            edges.append((s, (s + 1) % segments))
        }
        for t in 0..<ticks {
            let a = Float(t) / Float(ticks) * 2 * .pi
            let dir = Vec3(cos(a), 0, sin(a))
            vertices.append(dir * radius)
            vertices.append(dir * (radius + tickLength))
            edges.append((vertices.count - 2, vertices.count - 1))
        }
        return WireMesh(vertices: vertices, edges: edges)
    }

    /// The Singularity-7, built up from the same outline the in-game ship is drawn
    /// with (`Player.setupPlayer`), so the hero of the film is recognisably the ship
    /// the player flies. Forward is -Z, up is +Y, one unit is one point of the
    /// gameplay sprite: 36 long, 24 across the wings.
    static let ship: WireMesh = {
        // Outline (x, y) in sprite space, with hull heights above and below it.
        let outline: [(Float, Float, Float, Float)] = [
            (0, 18, 0.5, -0.4),     // nose
            (-5, 8, 2.6, -1.8),
            (-4, -2, 3.0, -2.0),
            (-12, -8, 0.5, -0.4),   // left wing tip
            (-10, -12, 0.5, -0.4),
            (-5, -10, 1.6, -1.2),
            (-6, -18, 1.6, -1.4),   // left engine
            (-3, -18, 1.6, -1.4),
            (-3, -10, 2.4, -1.8),
            (0, -8, 2.6, -2.0),     // tail
            (3, -10, 2.4, -1.8),
            (3, -18, 1.6, -1.4),    // right engine
            (6, -18, 1.6, -1.4),
            (5, -10, 1.6, -1.2),
            (10, -12, 0.5, -0.4),
            (12, -8, 0.5, -0.4),    // right wing tip
            (4, -2, 3.0, -2.0),
            (5, 8, 2.6, -1.8)
        ]
        var vertices: [Vec3] = []
        var edges: [(Int, Int)] = []
        let n = outline.count
        for (x, y, top, _) in outline { vertices.append(Vec3(x, top, -y)) }
        for (x, y, _, bottom) in outline { vertices.append(Vec3(x, bottom, -y)) }
        for i in 0..<n {
            edges.append((i, (i + 1) % n))
            edges.append((n + i, n + (i + 1) % n))
            // Struts only where the hull is deep enough to read as a side wall.
            if outline[i].2 > 1 { edges.append((i, n + i)) }
        }

        // Canopy: a raised diamond on the spine, tied to the nose and the tail.
        let canopy = vertices.count
        vertices += [Vec3(0, 3.0, -9), Vec3(-2.2, 3.4, -3), Vec3(0, 5.0, -3.5), Vec3(2.2, 3.4, -3), Vec3(0, 3.8, 2)]
        edges += [
            (canopy, canopy + 1), (canopy + 1, canopy + 4), (canopy + 4, canopy + 3), (canopy + 3, canopy),
            (canopy + 2, canopy), (canopy + 2, canopy + 1), (canopy + 2, canopy + 3), (canopy + 2, canopy + 4),
            (0, canopy), (canopy + 4, 9)
        ]

        // Wing panel lines on the upper surface.
        edges += [(5, 3), (13, 15), (2, 5), (16, 13)]

        // Engine nacelles: octagonal rings joined fore and aft.
        for side: Float in [-1, 1] {
            let cx = 4.5 * side
            var rings: [Int] = []
            for z: Float in [9, 18.5] {
                let start = vertices.count
                rings.append(start)
                for s in 0..<8 {
                    let a = Float(s) / 8 * 2 * .pi
                    vertices.append(Vec3(cx + cos(a) * 1.9, 0.1 + sin(a) * 1.9, z))
                    edges.append((start + s, start + (s + 1) % 8))
                }
            }
            for s in stride(from: 0, to: 8, by: 2) { edges.append((rings[0] + s, rings[1] + s)) }
        }
        return WireMesh(vertices: vertices, edges: edges)
    }()

    /// Where the exhaust leaves the ship, in ship space.
    static let shipNozzles: [Vec3] = [Vec3(-4.5, 0.1, 19), Vec3(4.5, 0.1, 19)]

    /// The ship's 2D outline, for drawing it flat (the constellation in the ending).
    static let shipOutline2D: [SIMD2<Float>] = [
        SIMD2(0, 18), SIMD2(-5, 8), SIMD2(-4, -2), SIMD2(-12, -8), SIMD2(-10, -12), SIMD2(-5, -10),
        SIMD2(-6, -18), SIMD2(-3, -18), SIMD2(-3, -10), SIMD2(0, -8), SIMD2(3, -10), SIMD2(3, -18),
        SIMD2(6, -18), SIMD2(5, -10), SIMD2(10, -12), SIMD2(12, -8), SIMD2(4, -2), SIMD2(5, 8)
    ]
}

// MARK: - Camera

struct WireCamera {
    var position = Vec3(0, 0, 100)
    var target = Vec3.zero
    var up = Vec3(0, 1, 0)
    /// Roll about the view axis, radians.
    var roll: Float = 0
    /// Field of view across the frame's *shorter* side, so a composition framed for
    /// a phone stays framed on an iPad, which only gains extra width.
    var fov: Float = 62 * .pi / 180

    init(position: Vec3, target: Vec3, roll: Float = 0, fov: Float = 62) {
        self.position = position
        self.target = target
        self.roll = roll
        self.fov = fov * .pi / 180
    }

    /// A camera circling `target` at `distance`, `elevation` radians above its plane.
    static func orbit(around target: Vec3, distance: Float, yaw: Float, elevation: Float,
                      roll: Float = 0, fov: Float = 62) -> WireCamera {
        let offset = Vec3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation)) * distance
        return WireCamera(position: target + offset, target: target, roll: roll, fov: fov)
    }
}

// MARK: - Canvas

/// Renders a frame of wireframe geometry. Call `begin(_:)`, issue draws, then `end()`.
final class WireCanvas: SKNode {

    /// Per-frame look settings. The director resets them before every frame.
    struct Settings {
        /// Depth where fog starts, and where it has swallowed everything.
        var fogNear: Float = 80
        var fogFar: Float = 700
        /// Depth at which a line is drawn at exactly its nominal width. Nearer lines
        /// thicken and farther ones thin, which sells depth more than fog alone.
        var widthReference: Float = 80
        /// When set, geometry deeper than this goes behind the occluder layer — the
        /// back half of an accretion disc disappearing behind a black hole.
        var depthSplit: Float?
        /// Master brightness for everything drawn this frame.
        var intensity: Float = 1
        /// Screen-space nudge, for chromatic-split glitch copies.
        var offset: CGPoint = .zero
    }

    var settings = Settings()
    /// Camera shake, set by the director.
    var shake: CGPoint = .zero

    private(set) var viewport: CGRect
    private(set) var focal: Float = 300
    private(set) var near: Float = 1

    private var eye = Vec3.zero
    private var forward = Vec3(0, 0, -1)
    private var right = Vec3(1, 0, 0)
    private var up = Vec3(0, 1, 0)
    private var originX: CGFloat = 0
    private var originY: CGFloat = 0
    private var scratch: [Vec3] = []

    private let backLayer = Layer(z: 0)
    private let occluderLayer: SKNode
    private let frontLayer = Layer(z: 2)
    private let discs: Pool

    init(viewport: CGRect) {
        self.viewport = viewport
        let occluders = SKNode()
        occluderLayer = occluders
        discs = Pool(parent: occluders, texture: WireCanvas.discTexture, blend: .alpha)
        super.init()
        occluderLayer.zPosition = 1
        addChild(backLayer.node)
        addChild(occluderLayer)
        addChild(frontLayer.node)
        scratch.reserveCapacity(512)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func resize(viewport: CGRect) {
        self.viewport = viewport
    }

    // MARK: Frame

    func begin(_ camera: WireCamera) {
        eye = camera.position
        forward = simd_normalize(camera.target - camera.position)
        var r = simd_cross(forward, camera.up)
        if simd_length_squared(r) < 1e-6 { r = simd_cross(forward, Vec3(0, 0, 1)) }
        r = simd_normalize(r)
        var u = simd_cross(r, forward)
        if camera.roll != 0 {
            let c = cos(camera.roll), s = sin(camera.roll)
            (r, u) = (r * c + u * s, u * c - r * s)
        }
        right = r
        up = u
        focal = Float(min(viewport.width, viewport.height) / 2) / tan(camera.fov / 2)
        originX = viewport.midX + shake.x + settings.offset.x
        originY = viewport.midY + shake.y + settings.offset.y
    }

    /// Re-applies `settings.offset` mid-frame, for drawing a displaced glitch copy.
    func applyOffset() {
        originX = viewport.midX + shake.x + settings.offset.x
        originY = viewport.midY + shake.y + settings.offset.y
    }

    /// Sprites the last finished frame drew.
    private(set) var drawnCount = 0

    func end() {
        drawnCount = backLayer.lines.used + backLayer.dots.used + frontLayer.lines.used + frontLayer.dots.used + discs.used
        backLayer.finish()
        frontLayer.finish()
        discs.finish()
    }

    // MARK: Projection

    @inline(__always) func toView(_ p: Vec3) -> Vec3 {
        let d = p - eye
        return Vec3(simd_dot(d, right), simd_dot(d, up), simd_dot(d, forward))
    }

    @inline(__always) private func screen(_ v: Vec3) -> CGPoint {
        CGPoint(x: originX + CGFloat(v.x / v.z * focal), y: originY + CGFloat(v.y / v.z * focal))
    }

    /// Where a world point lands on screen, or nil if it is behind the camera.
    func project(_ p: Vec3) -> CGPoint? {
        let v = toView(p)
        guard v.z > near else { return nil }
        return screen(v)
    }

    /// Distance from the camera along the view axis.
    func depth(of p: Vec3) -> Float { toView(p).z }

    /// On-screen size of a world-space length at `p`.
    func screenSize(of length: Float, at p: Vec3) -> CGFloat {
        let z = toView(p).z
        guard z > near else { return 0 }
        return CGFloat(length * focal / z)
    }

    private func fog(_ z: Float) -> Float {
        let f = 1 - clamp01((z - settings.fogNear) / max(1, settings.fogFar - settings.fogNear))
        // Fade geometry that is about to pass through the lens instead of letting it
        // balloon into a full-screen smear.
        let lens = clamp01((z - near) / 6)
        return f * f * (3 - 2 * f) * lens
    }

    private func layer(for depth: Float) -> Layer {
        if let split = settings.depthSplit, depth > split { return backLayer }
        return frontLayer
    }

    @inline(__always) private func visible(_ a: CGPoint, _ b: CGPoint, margin: CGFloat) -> Bool {
        let minX = viewport.minX - margin, maxX = viewport.maxX + margin
        let minY = viewport.minY - margin, maxY = viewport.maxY + margin
        if a.x < minX && b.x < minX { return false }
        if a.x > maxX && b.x > maxX { return false }
        if a.y < minY && b.y < minY { return false }
        if a.y > maxY && b.y > maxY { return false }
        return true
    }

    // MARK: Lines

    func line(_ a: Vec3, _ b: Vec3, color: UIColor, alpha: Float = 1, width: Float = 1.4) {
        lineInView(toView(a), toView(b), color: color, alpha: alpha, width: width)
    }

    private func lineInView(_ a0: Vec3, _ b0: Vec3, color: UIColor, alpha: Float, width: Float) {
        var a = a0, b = b0
        if a.z < near && b.z < near { return }
        if a.z < near {
            a = lerp(a, b, (near - a.z) / (b.z - a.z))
        } else if b.z < near {
            b = lerp(b, a, (near - b.z) / (a.z - b.z))
        }
        // A long line crossing the fog gradient is cut into pieces, or it would wear
        // one alpha from end to end and the horizon would never fade.
        let step = max(20, (settings.fogFar - settings.fogNear) / 10)
        let pieces = min(14, max(1, Int(abs(a.z - b.z) / step)))
        if pieces == 1 {
            segment(a, b, color: color, alpha: alpha, width: width)
        } else {
            var previous = a
            for i in 1...pieces {
                let next = lerp(a, b, Float(i) / Float(pieces))
                segment(previous, next, color: color, alpha: alpha, width: width)
                previous = next
            }
        }
    }

    private func segment(_ a: Vec3, _ b: Vec3, color: UIColor, alpha: Float, width: Float) {
        let z = (a.z + b.z) * 0.5
        let shade = alpha * settings.intensity * fog(z)
        guard shade > 0.012 else { return }
        let pa = screen(a), pb = screen(b)
        guard visible(pa, pb, margin: 8) else { return }
        let dx = pb.x - pa.x, dy = pb.y - pa.y
        let length = (dx * dx + dy * dy).squareRoot()
        let w = CGFloat(width * min(2.6, max(0.5, (settings.widthReference / max(z, 1)).squareRoot())))
        let sprite = layer(for: z).lines.next()
        sprite.position = CGPoint(x: (pa.x + pb.x) * 0.5, y: (pa.y + pb.y) * 0.5)
        sprite.zRotation = atan2(dy, dx)
        sprite.size = CGSize(width: length + w, height: w * 5)
        sprite.color = color
        sprite.alpha = CGFloat(min(1, shade))
    }

    func polyline(_ points: [Vec3], closed: Bool = false, color: UIColor, alpha: Float = 1, width: Float = 1.4) {
        guard points.count > 1 else { return }
        var previous = toView(points[0])
        let first = previous
        for i in 1..<points.count {
            let v = toView(points[i])
            lineInView(previous, v, color: color, alpha: alpha, width: width)
            previous = v
        }
        if closed { lineInView(previous, first, color: color, alpha: alpha, width: width) }
    }

    /// Draws a mesh.
    ///
    /// - Parameters:
    ///   - backAlpha: For convex bodies: edges on the far side are drawn at this
    ///     fraction, which reads as a solid object with a translucent skin.
    ///   - edgeAlpha: Per-edge multiplier from the edge's *local* end points, for
    ///     effects such as a scan line revealing the hull.
    func mesh(_ mesh: WireMesh, at position: Vec3 = .zero, rotation q: simd_quatf = identityRotation,
              scale: Float = 1, color: UIColor, alpha: Float = 1, width: Float = 1.4,
              backAlpha: Float? = nil, edgeAlpha: ((Vec3, Vec3) -> Float)? = nil) {
        scratch.removeAll(keepingCapacity: true)
        for v in mesh.vertices { scratch.append(toView(position + q.act(v * scale))) }
        let centre = toView(position)
        for (i, j) in mesh.edges {
            var a = alpha
            if let edgeAlpha {
                a *= edgeAlpha(mesh.vertices[i], mesh.vertices[j])
                if a < 0.012 { continue }
            }
            let va = scratch[i], vb = scratch[j]
            if let backAlpha {
                let mid = (va + vb) * 0.5
                // The eye is the view-space origin: an outward normal (mid - centre)
                // pointing the same way as the ray to the edge faces away from it.
                if simd_dot(mid - centre, mid) > 0 { a *= backAlpha }
            }
            lineInView(va, vb, color: color, alpha: a, width: width)
        }
    }

    // MARK: Points and light

    /// A point light of fixed on-screen size.
    func dot(_ p: Vec3, size: Float, color: UIColor, alpha: Float = 1, fogged: Bool = true) {
        let v = toView(p)
        guard v.z > near else { return }
        var shade = alpha * settings.intensity
        if fogged { shade *= fog(v.z) }
        guard shade > 0.012 else { return }
        let s = screen(v)
        guard visible(s, s, margin: CGFloat(size)) else { return }
        place(layer(for: v.z).dots.next(), at: s, size: CGSize(width: CGFloat(size), height: CGFloat(size)),
              color: color, alpha: shade)
    }

    /// A soft light whose size is a world-space radius, so it grows as it nears.
    func glow(_ p: Vec3, radius: Float, color: UIColor, alpha: Float = 1, fogged: Bool = false) {
        let v = toView(p)
        guard v.z > near else { return }
        var shade = alpha * settings.intensity
        if fogged { shade *= fog(v.z) }
        guard shade > 0.012 else { return }
        let size = CGFloat(radius * focal / v.z * 2)
        guard size > 0.5 else { return }
        let s = screen(v)
        guard visible(s, s, margin: size / 2) else { return }
        place(layer(for: v.z).dots.next(), at: s, size: CGSize(width: size, height: size), color: color, alpha: shade)
    }

    /// An anamorphic lens streak: a long, thin horizontal light through `p`.
    func flare(_ p: Vec3, length: Float, thickness: Float, color: UIColor, alpha: Float = 1) {
        let v = toView(p)
        guard v.z > near else { return }
        let shade = alpha * settings.intensity
        guard shade > 0.012 else { return }
        let s = screen(v)
        let sprite = frontLayer.dots.next()
        place(sprite, at: s, size: CGSize(width: CGFloat(length), height: CGFloat(thickness)), color: color, alpha: shade)
    }

    /// A dark disc in the occluder layer — anything further than `settings.depthSplit`
    /// is hidden behind it.
    func disc(_ p: Vec3, radius: Float, color: UIColor = .black, alpha: Float = 1) {
        let v = toView(p)
        guard v.z > near else { return }
        let size = CGFloat(radius * focal / v.z * 2)
        let sprite = discs.next()
        place(sprite, at: screen(v), size: CGSize(width: size, height: size), color: color, alpha: alpha)
    }

    // MARK: Screen space

    /// A line in screen coordinates, for HUD furniture over the picture.
    func line2D(_ a: CGPoint, _ b: CGPoint, color: UIColor, alpha: Float = 1, width: CGFloat = 1.2) {
        let shade = alpha * settings.intensity
        guard shade > 0.012 else { return }
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        let sprite = frontLayer.lines.next()
        sprite.position = CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
        sprite.zRotation = atan2(dy, dx)
        sprite.size = CGSize(width: length + width, height: width * 5)
        sprite.color = color
        sprite.alpha = CGFloat(min(1, shade))
    }

    /// A soft light in screen coordinates.
    func glow2D(_ p: CGPoint, size: CGFloat, color: UIColor, alpha: Float = 1) {
        let shade = alpha * settings.intensity
        guard shade > 0.012 else { return }
        place(frontLayer.dots.next(), at: p, size: CGSize(width: size, height: size), color: color, alpha: shade)
    }

    @inline(__always) private func place(_ sprite: SKSpriteNode, at p: CGPoint, size: CGSize, color: UIColor, alpha: Float) {
        sprite.position = p
        sprite.size = size
        sprite.color = color
        sprite.alpha = CGFloat(min(1, alpha))
    }

    // MARK: Pools

    private final class Pool {
        let parent: SKNode
        let texture: SKTexture
        let blend: SKBlendMode
        var nodes: [SKSpriteNode] = []
        var used = 0
        var shown = 0

        init(parent: SKNode, texture: SKTexture, blend: SKBlendMode) {
            self.parent = parent
            self.texture = texture
            self.blend = blend
        }

        func next() -> SKSpriteNode {
            if used == nodes.count {
                let sprite = SKSpriteNode(texture: texture)
                sprite.blendMode = blend
                sprite.colorBlendFactor = 1
                sprite.isHidden = true
                parent.addChild(sprite)
                nodes.append(sprite)
            }
            let sprite = nodes[used]
            if used >= shown { sprite.isHidden = false }
            used += 1
            return sprite
        }

        func finish() {
            if used < shown {
                for i in used..<shown { nodes[i].isHidden = true }
            }
            shown = used
            used = 0
        }
    }

    private final class Layer {
        let node = SKNode()
        let lines: Pool
        let dots: Pool

        init(z: CGFloat) {
            node.zPosition = z
            lines = Pool(parent: node, texture: WireCanvas.lineTexture, blend: .add)
            dots = Pool(parent: node, texture: WireCanvas.dotTexture, blend: .add)
        }

        func finish() {
            lines.finish()
            dots.finish()
        }
    }

    // MARK: Textures

    /// A horizontal light tube: a hot core a fifth of the sprite tall inside a soft
    /// halo, uniform along its length so it can be stretched to any line.
    static let lineTexture: SKTexture = {
        let height = 64
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: height), format: format).image { ctx in
            for row in 0..<height {
                let d = abs((Float(row) + 0.5) / Float(height) - 0.5)
                let core = 1 - smooth(0.07, 0.11, d)
                let halo = 0.42 * exp(-(d / 0.19) * (d / 0.19))
                let a = CGFloat(min(1, max(core, halo)))
                ctx.cgContext.setFillColor(UIColor(white: 1, alpha: a).cgColor)
                ctx.cgContext.fill(CGRect(x: 0, y: row, width: 4, height: 1))
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }()

    /// A star: a pin-sharp core in a wide, faint skirt.
    static let dotTexture: SKTexture = {
        let side: CGFloat = 64
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let stops: [(CGFloat, CGFloat)] = [(0, 1), (0.08, 0.95), (0.18, 0.5), (0.4, 0.16), (0.7, 0.04), (1, 0)]
            let colors = stops.map { UIColor(white: 1, alpha: $0.1).cgColor } as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                         locations: stops.map { $0.0 }) {
                let c = CGPoint(x: side / 2, y: side / 2)
                ctx.cgContext.drawRadialGradient(gradient, startCenter: c, startRadius: 0,
                                                 endCenter: c, endRadius: side / 2, options: [])
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }()

    /// A solid disc with a soft rim, for occluders.
    static let discTexture: SKTexture = {
        let side: CGFloat = 128
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let stops: [(CGFloat, CGFloat)] = [(0, 1), (0.9, 1), (1, 0)]
            let colors = stops.map { UIColor(white: 1, alpha: $0.1).cgColor } as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                         locations: stops.map { $0.0 }) {
                let c = CGPoint(x: side / 2, y: side / 2)
                ctx.cgContext.drawRadialGradient(gradient, startCenter: c, startRadius: 0,
                                                 endCenter: c, endRadius: side / 2, options: [])
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }()
}
