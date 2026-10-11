//
//  VectorFX3D.swift
//  jetshot
//
//  3D vector furniture for shields, cores, auras and targeting.
//
//  These used to be *pseudo*-3D: circles squashed by a fixed 0.3 to suggest depth,
//  each dot and ring its own SKShapeNode with its own repeating action — a shield
//  sphere alone was 140 nodes. They are now real wireframe in perspective, drawn by
//  `WireBody` with the story films' light-tube lines, so the hardware on an enemy is
//  built the same way as the world behind it and the entities in the opening film.
//

import SpriteKit
import simd

/// Generates 3D vector effects for ships, enemies and bosses.
class VectorFX3D {

    // MARK: - Meshes

    private static let sphere = WireMesh.geodesic(radius: 1, subdivisions: 1)
    private static let coarseSphere = WireMesh.geodesic(radius: 1, subdivisions: 0)
    private static let octa = WireMesh.octahedron(radius: 1)
    private static let spikes = WireMesh.spiked(radius: 1, spike: 1.8)
    private static let cube = WireMesh.box(Vec3(1, 1, 1))

    /// A turning, slightly random start, so a group built together does not move in step.
    private static func seed() -> Float { Float.random(in: 0...100) }

    // MARK: - Shield Sphere Effect

    /// A geodesic shield bubble, its far side faint behind its near side.
    ///
    /// - Parameters:
    ///   - radius: Radius of the bubble.
    ///   - color: Shield colour.
    ///   - persistent: If false it flashes outwards and fades instead of staying.
    static func createShieldSphere(radius: CGFloat, color: UIColor, persistent: Bool = true) -> SKNode {
        let r = Float(radius)
        let body = WireBody(extent: radius * 1.1, perspective: 5, interval: 1.0 / 30, seed: seed()) { frame in
            let c = frame.canvas
            let q = rotation(frame.t * 0.35, Vec3(0.3, 1, 0.15))
            c.mesh(sphere, rotation: q, scale: r, color: color, alpha: 0.5, width: 1, backAlpha: 0.22)
            // The rim, where a real bubble is brightest.
            c.polyline(StoryScenery.circle(center: .zero, radius: r * 1.02, u: Vec3(1, 0, 0), v: Vec3(0, 1, 0), segments: 40),
                       color: color, alpha: 0.55 + 0.15 * sin(frame.t * 3), width: 1.3)
            // A highlight sweeping over the surface.
            let a = frame.t * 1.3
            c.glow(Vec3(cos(a) * r * 0.6, sin(a * 0.7) * r * 0.5, r * 0.6), radius: r * 0.22, color: StoryPalette.white, alpha: 0.18)
        }
        body.name = "vectorShield"

        if !persistent {
            body.run(.sequence([.group([.scale(to: 2.5, duration: 0.5), .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
        }
        return body
    }

    // MARK: - Scanning Cone Effect

    /// A 3D scanning cone (for enemies detecting player), with a ring of light
    /// running down it.
    static func createScanCone(length: CGFloat, angle: CGFloat, color: UIColor, direction: CGPoint = CGPoint(x: 0, y: -1)) -> SKNode {
        let container = SKNode()
        container.name = "scanCone"
        container.zRotation = atan2(direction.y, direction.x) + .pi / 2

        let l = Float(length)
        let spread = tan(Float(angle) / 2)
        let body = WireBody(extent: length * 0.6, perspective: 4, interval: 1.0 / 30, seed: seed()) { frame in
            let c = frame.canvas
            // Apex at the top of the body, opening downwards, tilted towards the camera.
            let tilt = rotation(0.5, Vec3(1, 0, 0))
            let apex = Vec3(0, l * 0.5, 0)
            func ring(_ d: Float) -> [Vec3] {
                (0...14).map { s in
                    let a = Float(s) / 14 * 2 * .pi + frame.t * 0.6
                    return apex + tilt.act(Vec3(cos(a) * d * spread, -d, sin(a) * d * spread))
                }
            }
            for i in 1...4 {
                c.polyline(ring(l * Float(i) / 4), color: color, alpha: 0.25 + 0.12 * Float(i), width: 1)
            }
            let far = ring(l)
            for s in stride(from: 0, to: 14, by: 2) {
                c.line(apex, far[s], color: color, alpha: 0.3, width: 1)
            }
            let sweep = (frame.t / 1.5).truncatingRemainder(dividingBy: 1)
            c.polyline(ring(l * sweep), color: StoryPalette.white, alpha: (1 - sweep) * 0.8, width: 1.4)
        }
        // The apex sits on the container's origin and the cone opens down its -Y.
        body.position = CGPoint(x: 0, y: -length / 2)
        container.addChild(body)
        return container
    }

    // MARK: - PowerUp Burst Effect

    /// A spiral burst of light when a power-up is collected. Self-removing.
    static func createPowerUpBurst(at position: CGPoint, color: UIColor, particleCount: Int = 40) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = "powerUpBurst"

        for i in 0..<particleCount {
            let particle = LightSprite.star(size: 9, color: i % 3 == 0 ? .white : color)

            // A shell of points thrown out on a double spiral, seen in perspective.
            let theta = CGFloat(i) / CGFloat(particleCount) * .pi * 4
            let phi = CGFloat(i) / CGFloat(particleCount) * .pi * 2
            let distance: CGFloat = 80
            let x = cos(theta) * sin(phi) * distance
            let y = cos(phi) * distance
            let z = sin(theta) * sin(phi) * distance
            let depth = 1 + z / 240
            let target = CGPoint(x: x * depth, y: y * depth)

            let move = SKAction.move(to: target, duration: 0.8)
            move.timingMode = .easeOut
            particle.setScale(depth)
            particle.run(.sequence([.group([move, .fadeOut(withDuration: 0.8), .scale(to: 0.4, duration: 0.8)]),
                                    .removeFromParent()]))
            container.addChild(particle)
        }

        let ring = LightSprite.ring(radius: 14, color: color)
        ring.run(.sequence([.group([.scale(to: 4, duration: 0.45), .fadeOut(withDuration: 0.45)]), .removeFromParent()]))
        container.addChild(ring)

        let flash = LightSprite.star(size: 70, color: .white)
        flash.run(.sequence([.group([.scale(to: 2.4, duration: 0.35), .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
        container.addChild(flash)

        container.run(.sequence([.wait(forDuration: 1.0), .removeFromParent()]))
        return container
    }

    // MARK: - Vector Aura (Enemy Special)

    /// Rings of the given shape wheeling round an enemy on tilted axes — a gyroscope.
    static func createVectorAura(radius: CGFloat, color: UIColor, style: AuraStyle = .hexagon) -> SKNode {
        let sides: Int
        switch style {
        case .circle: sides = 28
        case .hexagon: sides = 6
        case .octagon: sides = 8
        case .triangle: sides = 3
        }
        let r = Float(radius)
        let axes = [Vec3(1, 0.3, 0), Vec3(-0.3, 1, 0.2), Vec3(0.2, 0.2, 1)]
        let body = WireBody(extent: radius + 26, perspective: 4.5, interval: 1.0 / 30, seed: seed()) { frame in
            let c = frame.canvas
            for (i, axis) in axes.enumerated() {
                let q = rotation(frame.t * (0.9 + Float(i) * 0.35) * (i % 2 == 0 ? 1 : -1), axis)
                let (u, v) = StoryScenery.basis(q.act(simd_normalize(axis)))
                let ringRadius = r + Float(i) * 8
                let points = (0..<sides).map { s -> Vec3 in
                    let a = Float(s) / Float(sides) * 2 * .pi
                    return (u * cos(a) + v * sin(a)) * ringRadius
                }
                c.polyline(points, closed: true, color: color, alpha: 0.55 - Float(i) * 0.12, width: 1.1)
                if sides <= 8 && i == 0 {
                    for p in points { c.dot(p, size: 5, color: color, alpha: 0.8) }
                }
            }
        }
        body.name = "vectorAura"
        return body
    }

    // MARK: - Targeting Reticle

    /// A lock-on: brackets closing on the target, then a flash. Self-contained, but
    /// left for the caller to remove, as before.
    static func createTargetingReticle(at target: CGPoint, color: UIColor, lockDuration: TimeInterval = 1.0) -> SKNode {
        let container = SKNode()
        container.position = target
        container.name = "targetingReticle"

        let half: CGFloat = 22, arm: CGFloat = 9
        for (sx, sy) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] as [(CGFloat, CGFloat)] {
            let corner = SKNode()
            corner.position = CGPoint(x: half * sx, y: half * sy)
            corner.addChild(LightSprite.tube(from: .zero, to: CGPoint(x: -arm * sx, y: 0), width: 1.4, color: color))
            corner.addChild(LightSprite.tube(from: .zero, to: CGPoint(x: 0, y: -arm * sy), width: 1.4, color: color))
            let close = SKAction.move(to: CGPoint(x: half * 0.45 * sx, y: half * 0.45 * sy), duration: lockDuration)
            close.timingMode = .easeIn
            corner.run(close)
            container.addChild(corner)
        }

        let ring = LightSprite.ring(radius: 14, color: color)
        ring.alpha = 0.6
        ring.run(.group([.scale(to: 0.7, duration: lockDuration),
                         .repeat(.sequence([.fadeAlpha(to: 0.2, duration: 0.12), .fadeAlpha(to: 0.7, duration: 0.12)]),
                                 count: max(1, Int(lockDuration / 0.24)))]))
        container.addChild(ring)

        for angle in [0, CGFloat.pi / 2, .pi, .pi * 1.5] {
            container.addChild(LightSprite.tube(from: CGPoint(x: cos(angle) * 6, y: sin(angle) * 6),
                                                to: CGPoint(x: cos(angle) * 12, y: sin(angle) * 12),
                                                width: 1.1, color: color))
        }
        container.addChild(LightSprite.star(size: 10, color: .white))

        container.run(.sequence([
            .wait(forDuration: lockDuration),
            .run { [weak container] in
                let flash = LightSprite.ring(radius: 30, color: StoryPalette.red)
                flash.run(.sequence([.group([.scale(to: 0.5, duration: 0.2), .fadeOut(withDuration: 0.2)]), .removeFromParent()]))
                container?.addChild(flash)
            }
        ]))
        return container
    }

    // MARK: - Helpers

    enum AuraStyle {
        case circle
        case hexagon
        case octagon
        case triangle
    }

    // MARK: - Energy Core Effect

    /// Nested wireframe shells turning against each other round a white-hot point —
    /// the film's epicentre, at the scale of one machine.
    static func createEnergyCore(radius: CGFloat, color: UIColor, layers: Int = 3) -> SKNode {
        let r = Float(radius)
        let shells = max(1, min(layers, 6))
        let body = WireBody(extent: radius * 1.15, perspective: 4.5, interval: 1.0 / 30, seed: seed()) { frame in
            let c = frame.canvas
            for layer in 0..<shells {
                let k = Float(layer)
                let mesh = layer == 0 ? coarseSphere : (layer % 2 == 1 ? octa : cube)
                let scale = r * (1 - k * 0.2) * (layer == 2 ? 0.6 : 1)
                let q = rotation(frame.t * (0.7 + k * 0.4) * (layer % 2 == 0 ? 1 : -1), Vec3(0.3 + k * 0.2, 1, 0.2))
                c.mesh(mesh, rotation: q, scale: scale, color: layer == 1 ? StoryPalette.white : color,
                       alpha: 0.75 - k * 0.1, width: 1.1, backAlpha: 0.3)
            }
            let pulse: Float = 1 + 0.2 * sin(frame.t * 5)
            c.glow(.zero, radius: r * 0.7 * pulse, color: color, alpha: 0.45)
            c.glow(.zero, radius: r * 0.25 * pulse, color: StoryPalette.white, alpha: 0.9)
        }
        body.name = "energyCore"
        return body
    }

    // MARK: - Rotating Cannon Barrels

    /// A ring of barrels on a turning hub, laid in a tilted plane.
    static func createRotatingCannons(count: Int, radius: CGFloat, color: UIColor) -> SKNode {
        let r = Float(radius)
        let n = max(1, count)
        let body = WireBody(extent: radius + 14, perspective: 4.5, interval: 1.0 / 30, seed: seed()) { frame in
            let c = frame.canvas
            let tilt = rotation(0.55, Vec3(1, 0, 0))
            let spin = frame.t * (2 * .pi / 4)
            var hub: [Vec3] = []
            for i in 0..<n {
                let a = Float(i) / Float(n) * 2 * .pi + spin
                let dir = tilt.act(Vec3(cos(a), sin(a), 0))
                let base = dir * r
                c.line(base, base + dir * 9, color: color, alpha: 0.95, width: 1.6)
                c.dot(base + dir * 10, size: 5, color: StoryPalette.white, alpha: 0.8)
                hub.append(base)
            }
            if hub.count > 2 { c.polyline(hub, closed: true, color: color, alpha: 0.45, width: 1) }
        }
        body.name = "rotatingCannons"
        return body
    }

    // MARK: - Force Field Effect

    /// A dashed field ring turning in a tilted plane, with faint spokes.
    static func createForceField(radius: CGFloat, color: UIColor) -> SKNode {
        let r = Float(radius)
        let body = WireBody(extent: radius * 1.1, perspective: 4.5, interval: 1.0 / 30, seed: seed()) { frame in
            let c = frame.canvas
            let tilt = rotation(0.9, Vec3(1, 0, 0.15)) * rotation(frame.t * 0.25, Vec3(0, 0, 1))
            let u = tilt.act(Vec3(1, 0, 0)), v = tilt.act(Vec3(0, 1, 0))
            let breathe: Float = 0.55 + 0.2 * sin(frame.t * 4)
            StoryScenery.dashedRing(c, center: .zero, radius: r, u: u, v: v, phase: frame.t * 1.2, dashes: 10, fill: 0.62,
                                    color: color, alpha: breathe, width: 1.3)
            for s in 0..<8 {
                let a = Float(s) / 8 * 2 * .pi + frame.t * 0.6
                let dir = u * cos(a) + v * sin(a)
                c.line(dir * r * 0.55, dir * r * 0.95, color: color, alpha: breathe * 0.4, width: 1)
            }
        }
        body.name = "forceField"
        return body
    }

    // MARK: - Charge Up Effect

    /// Light converging on a point before an attack. Self-removing.
    static func createChargeEffect(at position: CGPoint, color: UIColor, duration: TimeInterval = 1.0) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = "chargeEffect"

        let particleCount = 18
        for i in 0..<particleCount {
            let angle = CGFloat(i) / CGFloat(particleCount) * .pi * 2
            let distance: CGFloat = 60
            let start = CGPoint(x: cos(angle) * distance, y: sin(angle) * distance)
            // A short streak pointing at the centre, so it reads as being drawn in.
            let streak = LightSprite.tube(from: start, to: CGPoint(x: start.x * 0.82, y: start.y * 0.82), width: 1.3, color: color)
            let move = SKAction.move(to: .zero, duration: duration)
            move.timingMode = .easeIn
            streak.run(.sequence([.group([move, .fadeOut(withDuration: duration)]), .removeFromParent()]))
            container.addChild(streak)
        }

        let ring = LightSprite.ring(radius: 26, color: color)
        ring.alpha = 0
        ring.run(.sequence([.group([.fadeAlpha(to: 0.7, duration: duration * 0.3), .scale(to: 0.25, duration: duration)]),
                            .fadeOut(withDuration: 0.1)]))
        container.addChild(ring)

        let glow = LightSprite.star(size: 18, color: color)
        glow.alpha = 0
        glow.run(.group([.fadeIn(withDuration: duration), .scale(to: 2.4, duration: duration)]))
        container.addChild(glow)

        container.run(.sequence([.wait(forDuration: duration + 0.5), .removeFromParent()]))
        return container
    }

    // MARK: - Radar Sweep

    /// A radar dish seen in perspective: rings, and a sweep with a fading wake.
    static func createRadarSweep(radius: CGFloat, color: UIColor) -> SKNode {
        let r = Float(radius)
        let body = WireBody(extent: radius * 1.1, perspective: 4.5, interval: 1.0 / 30, seed: seed()) { frame in
            let c = frame.canvas
            let tilt = rotation(0.75, Vec3(1, 0, 0))
            let u = tilt.act(Vec3(1, 0, 0)), v = tilt.act(Vec3(0, 1, 0))
            c.polyline(StoryScenery.circle(center: .zero, radius: r, u: u, v: v, segments: 36), color: color, alpha: 0.5, width: 1.1)
            let pulse = (frame.t * 0.8).truncatingRemainder(dividingBy: 1)
            c.polyline(StoryScenery.circle(center: .zero, radius: r * pulse, u: u, v: v, segments: 28),
                       color: color, alpha: (1 - pulse) * 0.5, width: 1)
            let sweep = frame.t * .pi
            for k in 0..<5 {
                let a = sweep - Float(k) * 0.12
                c.line(.zero, (u * cos(a) + v * sin(a)) * r, color: color, alpha: 0.9 - Float(k) * 0.18, width: 1.3)
            }
        }
        body.name = "radarSweep"
        return body
    }

    // MARK: - Energy Beam Charger

    /// Lines of light converging down the line a beam is about to take.
    static func createBeamCharger(length: CGFloat, color: UIColor) -> SKNode {
        let container = SKNode()
        container.name = "beamCharger"

        for i in 0..<8 {
            let offset = CGFloat(i - 4) * 3
            let line = LightSprite.tube(from: CGPoint(x: offset, y: 0), to: CGPoint(x: 0, y: -length), width: 1.2, color: color)
            line.alpha = 0.45
            container.addChild(line)

            let particle = LightSprite.star(size: 7, color: .white)
            particle.position = CGPoint(x: offset, y: 0)
            let move = SKAction.move(to: CGPoint(x: 0, y: -length), duration: 0.5)
            // [weak particle] — runs forever; a strong capture would leak the node.
            let reset = SKAction.run { [weak particle] in
                particle?.position = CGPoint(x: offset, y: 0)
                particle?.alpha = 1.0
            }
            particle.run(.repeatForever(.sequence([.group([move, .fadeOut(withDuration: 0.5)]), reset])))
            container.addChild(particle)
        }
        return container
    }

    // MARK: - Orbital Defense

    /// Defence nodes riding an orbit tilted out of the screen, so they pass in front
    /// of the hull and behind it.
    static func createOrbitalDefense(count: Int, radius: CGFloat, color: UIColor) -> SKNode {
        let r = Float(radius)
        let n = max(1, count)
        let body = WireBody(extent: radius + 10, perspective: 4.5, interval: 1.0 / 30, seed: seed()) { frame in
            let c = frame.canvas
            let tilt = rotation(1.0, Vec3(1, 0, 0.2))
            let u = tilt.act(Vec3(1, 0, 0)), v = tilt.act(Vec3(0, 1, 0))
            StoryScenery.dashedRing(c, center: .zero, radius: r, u: u, v: v, phase: 0, dashes: 24, fill: 0.5,
                                    color: color, alpha: 0.3, width: 1)
            let spin = frame.t * (2 * .pi / 3)
            for i in 0..<n {
                let a = Float(i) / Float(n) * 2 * .pi + spin
                let p = (u * cos(a) + v * sin(a)) * r
                let near = 0.6 + 0.4 * clamp01(p.z / r * 0.5 + 0.5)
                c.mesh(octa, at: p, rotation: rotation(frame.t * 3, Vec3(0, 1, 0.3)), scale: 4.5,
                       color: color, alpha: near, width: 1.2)
                c.glow(p, radius: 5, color: StoryPalette.white, alpha: near * 0.6)
            }
        }
        body.name = "orbitalDefense"
        return body
    }

    // MARK: - Small 3D cores

    enum CoreShape {
        case octahedron
        case spiked
        case cage
        case sphere
    }

    /// The beating heart of an enemy: a small turning crystal with a white-hot centre.
    /// The shapes are the film's hostile entities, so what the player shoots at is
    /// recognisably what the opening showed guarding the way.
    static func createCore(radius: CGFloat, shape: CoreShape, color: UIColor) -> SKNode {
        let r = Float(radius)
        let mesh: WireMesh
        switch shape {
        case .octahedron: mesh = octa
        case .spiked: mesh = spikes
        case .cage: mesh = cube
        case .sphere: mesh = coarseSphere
        }
        let meshScale: Float = shape == .spiked ? r * 0.55 : (shape == .cage ? r * 0.62 : r)
        let speed = Float.random(in: 1.1...1.7)
        let body = WireBody(extent: radius * 1.2, perspective: 4.5, interval: 1.0 / 30, seed: seed()) { frame in
            let c = frame.canvas
            let q = rotation(frame.t * speed, Vec3(0.4, 1, 0.25))
            c.mesh(mesh, rotation: q, scale: meshScale, color: color, alpha: 1, width: 1.2, backAlpha: 0.4)
            if shape == .cage {
                c.mesh(octa, rotation: q.inverse, scale: r * 0.45, color: StoryPalette.white, alpha: 0.8, width: 1)
            }
            let beat: Float = 0.75 + 0.25 * sin(frame.t * 4)
            c.glow(.zero, radius: r * 0.55 * beat, color: color, alpha: 0.6)
            c.glow(.zero, radius: r * 0.22, color: StoryPalette.white, alpha: 0.95)
        }
        body.name = "core3D"
        return body
    }
}
