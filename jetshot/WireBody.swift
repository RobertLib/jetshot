//
//  WireBody.swift
//  jetshot
//
//  The film's wireframe renderer, brought down to the size of one game object.
//

import SpriteKit
import simd

/// A small, self-animating piece of real 3D wireframe — a hull, a shield, a core —
/// drawn with the same light-tube lines as the story films.
///
/// Each body owns a `WireCanvas` whose viewport is centred on the node and a camera
/// far enough down +Z that one world unit is one point in the node's plane: model a
/// mesh in points and it lands at the size a shape node of the same numbers would
/// have, with just enough perspective to read as a solid. +X is right, +Y is up the
/// screen and +Z comes out of it towards the player.
///
/// It redraws itself from an action rather than from anybody's update loop, so it
/// runs on whatever clock its parent does: a paused `gameContentNode` freezes it, a
/// hit-stop's slowed `speed` slows it, and removing the node stops it.
final class WireBody: SKNode {

    struct Frame {
        /// Seconds on the body's own clock.
        let t: Float
        let canvas: WireCanvas
    }

    let canvas: WireCanvas
    /// Camera distance from the node's plane, in points.
    let distance: Float
    private let fov: Float
    private let baseSettings: WireCanvas.Settings
    private let render: (Frame) -> Void
    /// Seconds between redraws; 0 redraws every frame. Slow, distant or small things
    /// can afford 30 Hz and give the frame budget back to the playfield.
    private let interval: Float
    private(set) var clock: Float
    private var sinceDraw: Float = .infinity
    private var lastElapsed: CGFloat = 0

    /// Master brightness for the body, multiplied into every line it draws.
    var intensity: Float = 1

    /// - Parameters:
    ///   - extent: Rough radius of what will be drawn, in points. Sets the viewport
    ///     (lines wholly outside it are culled) and the camera distance.
    ///   - perspective: Camera distance in multiples of `extent`. Smaller is a wider
    ///     lens and a stronger 3D read; 4–5 keeps shapes honest at gameplay size.
    ///   - interval: Seconds between redraws (0 for every frame).
    ///   - seed: Starting point on the clock, so a group of bodies built together
    ///     does not turn in lockstep.
    init(extent: CGFloat, perspective: Float = 4.5, interval: Float = 0, seed: Float = 0,
         render: @escaping (Frame) -> Void) {
        let half = extent * 1.35
        canvas = WireCanvas(viewport: CGRect(x: -half, y: -half, width: half * 2, height: half * 2))
        distance = Float(extent) * perspective
        fov = 2 * atan(Float(half) / distance) * 180 / .pi
        var settings = WireCanvas.Settings()
        settings.fogNear = distance * 50
        settings.fogFar = distance * 100
        settings.widthReference = distance
        baseSettings = settings
        self.render = render
        self.interval = interval
        clock = seed
        super.init()
        addChild(canvas)
        draw()
        run(.repeatForever(.customAction(withDuration: 60) { [weak self] _, elapsed in
            self?.tick(elapsed: elapsed)
        }), withKey: "wireBody")
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func tick(elapsed: CGFloat) {
        // The action restarts every 60 s; a smaller elapsed than last time is the wrap.
        var dt = Float(elapsed - lastElapsed)
        if elapsed < lastElapsed { dt = Float(elapsed) }
        lastElapsed = elapsed
        dt = min(max(dt, 0), 0.1)
        clock += dt
        sinceDraw += dt
        // Nothing to see: a scan cone waiting at zero alpha, a hidden effect. The clock
        // still runs, so it picks up where it should when it shows again.
        if isHidden || alpha < 0.01 || (parent.map { $0.isHidden || $0.alpha < 0.01 } ?? false) { return }
        if sinceDraw >= interval { draw() }
    }

    /// Redraws now, whatever the interval says.
    func draw() {
        sinceDraw = 0
        canvas.settings = baseSettings
        canvas.settings.intensity = intensity
        canvas.begin(WireCamera(position: Vec3(0, 0, distance), target: .zero, fov: fov))
        render(Frame(t: clock, canvas: canvas))
        canvas.end()
    }
}

// MARK: - Shared meshes

extension WireMesh {

    /// A rough rock: an icosahedron, once subdivided, pushed in and out per vertex.
    static func rock(radius: Float, seed: UInt64, roughness: Float = 0.28, subdivisions: Int = 1) -> WireMesh {
        let base = geodesic(radius: 1, subdivisions: subdivisions)
        var rng = StoryRandom(seed: seed)
        // A couple of broad lumps plus fine noise reads as stone; pure per-vertex noise
        // reads as a crumpled ball.
        let lumps = (0..<3).map { _ in (rng.direction(), rng.float(-0.35...0.25)) }
        let vertices = base.vertices.map { v -> Vec3 in
            var r: Float = 1 + rng.float(-roughness...roughness) * 0.5
            for (dir, depth) in lumps {
                r += depth * max(0, simd_dot(v, dir) - 0.4) * 1.6
            }
            return v * radius * max(0.55, r)
        }
        return WireMesh(vertices: vertices, edges: base.edges)
    }

    /// A hexagonal prism, axis along Z.
    static func hexPrism(radius: Float, depth: Float) -> WireMesh {
        var vertices: [Vec3] = []
        var edges: [(Int, Int)] = []
        for z in [-depth / 2, depth / 2] {
            let start = vertices.count
            for i in 0..<6 {
                let a = Float(i) / 6 * 2 * .pi + .pi / 2
                vertices.append(Vec3(cos(a) * radius, sin(a) * radius, z))
                edges.append((start + i, start + (i + 1) % 6))
            }
        }
        for i in 0..<6 { edges.append((i, i + 6)) }
        return WireMesh(vertices: vertices, edges: edges)
    }

    /// A ring in the XY plane (facing the camera), unlike `ring`, which lies in XZ.
    static func hoop(radius: Float, segments: Int) -> WireMesh {
        var vertices: [Vec3] = []
        var edges: [(Int, Int)] = []
        for s in 0..<segments {
            let a = Float(s) / Float(segments) * 2 * .pi
            vertices.append(Vec3(cos(a), sin(a), 0) * radius)
            edges.append((s, (s + 1) % segments))
        }
        return WireMesh(vertices: vertices, edges: edges)
    }
}

// MARK: - Light sprites

/// Single sprites cut from the film's light textures, for effects that live in
/// SpriteKit actions rather than in a canvas.
enum LightSprite {

    /// A line of light from `a` to `b`, in its parent's coordinates. Additive.
    static func tube(from a: CGPoint, to b: CGPoint, width: CGFloat, color: UIColor) -> SKSpriteNode {
        let sprite = SKSpriteNode(texture: WireCanvas.lineTexture)
        sprite.colorBlendFactor = 1
        sprite.color = color
        sprite.blendMode = .add
        place(sprite, from: a, to: b, width: width)
        return sprite
    }

    /// Re-aims an existing tube.
    static func place(_ sprite: SKSpriteNode, from a: CGPoint, to b: CGPoint, width: CGFloat) {
        let dx = b.x - a.x, dy = b.y - a.y
        sprite.position = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        sprite.zRotation = atan2(dy, dx)
        sprite.size = CGSize(width: (dx * dx + dy * dy).squareRoot() + width, height: width * 5)
    }

    /// A star-shaped point of light: a pin-sharp core in a wide skirt.
    static func star(size: CGFloat, color: UIColor) -> SKSpriteNode {
        let sprite = SKSpriteNode(texture: WireCanvas.dotTexture, size: CGSize(width: size, height: size))
        sprite.colorBlendFactor = 1
        sprite.color = color
        sprite.blendMode = .add
        return sprite
    }

    /// The anamorphic lens streak the films put through every bright source.
    static func flare(length: CGFloat, thickness: CGFloat, color: UIColor) -> SKSpriteNode {
        let sprite = star(size: 1, color: color)
        sprite.size = CGSize(width: length, height: thickness)
        return sprite
    }

    /// A thin ring of light, `radius` points to the middle of its line.
    static func ring(radius: CGFloat, color: UIColor) -> SKSpriteNode {
        let sprite = SKSpriteNode(texture: ringTexture)
        // The texture's line sits at 0.82 of its half-width.
        let side = radius * 2 / 0.82
        sprite.size = CGSize(width: side, height: side)
        sprite.colorBlendFactor = 1
        sprite.color = color
        sprite.blendMode = .add
        return sprite
    }

    /// A circle drawn with the light-tube profile: hot core, soft halo.
    private static let ringTexture: SKTexture = {
        let side = 256
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let c = CGFloat(side) / 2
            let radius = c * 0.82
            // Concentric strokes from the outside of the halo inwards, so the
            // brightest pass lands last and on top.
            let passes: [(CGFloat, CGFloat)] = [(18, 0.05), (12, 0.1), (7, 0.18), (4, 0.4), (2, 1)]
            for (width, alpha) in passes {
                ctx.cgContext.setStrokeColor(UIColor(white: 1, alpha: alpha).cgColor)
                ctx.cgContext.setLineWidth(width)
                ctx.cgContext.strokeEllipse(in: CGRect(x: c - radius, y: c - radius, width: radius * 2, height: radius * 2))
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }()
}

// MARK: - Ring of light

/// A circle of light built from tube segments, so its line stays the same thickness
/// at any radius — a scaled ring texture would fatten as it grew. `squash` lays it
/// into the world's floor plane, where a blast's pressure wave travels.
final class LightRing: SKNode {

    private let segments: [SKSpriteNode]

    init(segments count: Int = 28, color: UIColor) {
        segments = (0..<max(6, count)).map { _ in
            let s = SKSpriteNode(texture: WireCanvas.lineTexture)
            s.colorBlendFactor = 1
            s.color = color
            s.blendMode = .add
            return s
        }
        super.init()
        segments.forEach(addChild)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(radius: CGFloat, width: CGFloat, squash: CGFloat = 1) {
        let n = CGFloat(segments.count)
        for (i, sprite) in segments.enumerated() {
            let a0 = CGFloat(i) / n * 2 * .pi, a1 = CGFloat(i + 1) / n * 2 * .pi
            LightSprite.place(sprite, from: CGPoint(x: cos(a0) * radius, y: sin(a0) * radius * squash),
                              to: CGPoint(x: cos(a1) * radius, y: sin(a1) * radius * squash), width: width)
        }
    }

    /// A ring that races out from `start` to `end` and fades as it goes, thinning
    /// so it dissipates rather than bloats. Removes itself.
    static func wave(from start: CGFloat, to end: CGFloat, width: CGFloat, color: UIColor,
                     duration: TimeInterval, squash: CGFloat = 1, segments: Int = 28) -> LightRing {
        let ring = LightRing(segments: segments, color: color)
        ring.set(radius: start, width: width, squash: squash)
        let grow = SKAction.customAction(withDuration: duration) { node, elapsed in
            guard let ring = node as? LightRing else { return }
            let t = Float(elapsed / CGFloat(duration))
            let e = CGFloat(easeOut(t))
            ring.set(radius: start + (end - start) * e, width: width * (1 - e * 0.6), squash: squash)
            ring.alpha = CGFloat(1 - smooth(0.25, 1, t))
        }
        ring.run(.sequence([grow, .removeFromParent()]))
        return ring
    }
}
