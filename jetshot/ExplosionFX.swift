//
//  ExplosionFX.swift
//  jetshot
//

import SpriteKit

/// Builds the layered explosion burst.
///
/// Third piece lifted out of `GameScene` (after `WeaponHeatSystem` and
/// `PowerUpTimerHUD`), and the easiest of the three: unlike those two this owns no state
/// at all, so it is a plain namespace of pure functions rather than a collaborator. It
/// returns a detached node and never touches the scene — the caller keeps the parts that
/// genuinely are the scene's: the sound, the camera shake, and the full-screen flash.
///
/// The type stays main-actor (the project's `SWIFT_DEFAULT_ACTOR_ISOLATION`), because
/// building SpriteKit nodes genuinely is main-actor work. Only the two pure lookups below
/// are marked `nonisolated`, for the same reason as `GameRules`: they are arithmetic over
/// plain numbers, and leaving them main-actor bound would put them out of reach of a test
/// module for no benefit.
enum ExplosionFX {

    /// How hard the camera kicks for a given blast, and for how long.
    ///
    /// Pure, so `jetshotTests` can pin the size ordering down without a scene. iPad gets a
    /// gentler kick: the same shake is far more uncomfortable on a large display held
    /// close, which is what `GameConfiguration.iPadShakeMultiplier` is for.
    nonisolated static func cameraShake(for size: ExplosionSize, isIPad: Bool) -> (intensity: CGFloat, duration: TimeInterval) {
        let multiplier: CGFloat = isIPad ? GameConfiguration.iPadShakeMultiplier : 1.0
        switch size {
        case .small:
            return (GameConfiguration.shakeIntensitySmall * multiplier, 0.15)
        case .normal:
            return (GameConfiguration.shakeIntensityNormal * multiplier, 0.25)
        case .large:
            return (GameConfiguration.shakeIntensityLarge * multiplier, 0.35)
        case .huge:
            return (GameConfiguration.shakeIntensityHuge * multiplier, 0.45)
        }
    }

    /// Relative scale of every layer in the burst.
    nonisolated static func sizeMultiplier(for size: ExplosionSize) -> CGFloat {
        switch size {
        case .small:  return 0.6
        case .normal: return 1.0
        case .large:  return 1.4
        case .huge:   return 2.0
        }
    }

    /// A detached, self-removing explosion node centred on its own origin.
    ///
    /// Drawn the way the story films draw light: a pin-sharp white core, an
    /// anamorphic lens streak through it, a pressure wave laid into the world's floor
    /// plane, and sparks and shards as lines of light. The layers are staged in time —
    /// flash, streak, wave, then sparks — because a blast that happens all on one frame
    /// reads as a single popping circle.
    ///
    /// The caller positions it and parents it (to `GameScene.effectsParent`, never the
    /// scene: the scene keeps ticking while the game is paused).
    ///
    /// `tint` is the dead ship's own colour: its bloom, its streak and a ring of its
    /// sparks, so every enemy type dies in its own colour rather than all in orange.
    static func burst(size: ExplosionSize, particleMultiplier: CGFloat, tint: UIColor? = nil) -> SKNode {
        let container = SKNode()
        container.zPosition = 500

        let m = sizeMultiplier(for: size)

        let hot = UIColor(red: 1.0, green: 0.96, blue: 0.82, alpha: 1.0)
        let fire = UIColor(red: 1.0, green: 0.52, blue: 0.12, alpha: 1.0)
        let ember = UIColor(red: 1.0, green: 0.78, blue: 0.22, alpha: 1.0)
        let accent = tint ?? fire

        // 1. White-hot core: brightest for only a couple of frames.
        let core = LightSprite.star(size: 70 * m, color: hot)
        core.zPosition = 6
        container.addChild(core)
        let coreGrow = SKAction.scale(to: 1.8, duration: 0.16)
        coreGrow.timingMode = .easeOut
        core.run(.group([coreGrow, .fadeOut(withDuration: 0.16)]))

        // 2. A bloom in the ship's colour over a short-lived fireball.
        let bloom = NeonFX.radialGlow(radius: 26 * m, color: accent)
        bloom.zPosition = 3
        bloom.alpha = 0.75
        container.addChild(bloom)
        let bloomGrow = SKAction.scale(to: 2.3, duration: 0.42)
        bloomGrow.timingMode = .easeOut
        let bloomFade = SKAction.fadeOut(withDuration: 0.42)
        bloomFade.timingMode = .easeIn
        bloom.run(.group([bloomGrow, bloomFade]))

        let fireball = NeonFX.radialGlow(radius: 15 * m, color: fire)
        fireball.zPosition = 4
        container.addChild(fireball)
        fireball.run(.group([.scale(to: 2.2, duration: 0.26), .fadeOut(withDuration: 0.26)]))

        // 3. The lens streak: the films' signature on every bright source.
        let streakColor = StoryPalette.mix(accent, hot, 0.45)
        for (length, thickness, alpha) in [(190 * m, 7 * m, 0.9), (110 * m, 2.5 * m, 1.0)] as [(CGFloat, CGFloat, CGFloat)] {
            let flare = LightSprite.flare(length: length, thickness: thickness,
                                          color: thickness < 3 * m ? .white : streakColor)
            flare.zPosition = 7
            flare.xScale = 0.2
            flare.alpha = alpha
            container.addChild(flare)
            let open = SKAction.scaleX(to: 1, duration: 0.1)
            open.timingMode = .easeOut
            flare.run(.sequence([open, .group([.scaleX(to: 1.3, duration: 0.3), .fadeOut(withDuration: 0.3)])]))
        }

        // 4. The pressure wave, laid into the floor plane of the world behind.
        container.addChild(LightRing.wave(from: 8 * m, to: 72 * m, width: 1.6 + 0.6 * m, color: ember,
                                          duration: 0.5, squash: 0.42))
        // A second, faster wave in the screen plane on the heavy hits reads as overpressure.
        if size == .large || size == .huge {
            container.addChild(LightRing.wave(from: 6 * m, to: 96 * m, width: 1.4, color: hot,
                                              duration: 0.32, segments: 32))
        }

        // 5. Sparks: fast, thin, drag to a stop.
        let sparkCount = Int(CGFloat(Int(11 * m)) * particleMultiplier)
        container.addChild(NeonFX.sparks(
            at: .zero,
            count: sparkCount,
            color: ember,
            speed: 66 * m,
            length: 9 * min(m, 1.4),
            lifetime: 0.36
        ))

        // 5b. The ship's own colour, thrown wider and faster than the fire.
        if let tint = tint {
            container.addChild(NeonFX.sparks(
                at: .zero,
                count: Int(CGFloat(Int(9 * m)) * particleMultiplier),
                color: tint,
                speed: 100 * m,
                length: 11 * min(m, 1.4),
                lifetime: 0.42
            ))
        }

        // 6. Shards: short lines of light tumbling outwards.
        let shardCount = Int(CGFloat(Int(5 * m)) * particleMultiplier)
        for i in 0..<max(0, shardCount) {
            let angle = CGFloat(i) * .pi * 2 / CGFloat(max(1, shardCount)) + CGFloat.random(in: -0.4...0.4)
            let length = CGFloat.random(in: 5...10) * min(m, 1.5)
            let shard = LightSprite.tube(from: CGPoint(x: -length / 2, y: 0), to: CGPoint(x: length / 2, y: 0),
                                         width: 1.2, color: i % 2 == 0 ? accent : hot)
            shard.zPosition = 5
            shard.zRotation = CGFloat.random(in: 0...(.pi))
            container.addChild(shard)

            let distance = CGFloat.random(in: 30...62) * m
            let travel = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: 0.6)
            travel.timingMode = .easeOut
            let tumble = SKAction.rotate(byAngle: CGFloat.random(in: -7...7), duration: 0.6)
            shard.run(.group([travel, tumble, .fadeOut(withDuration: 0.6)]))
        }

        // Remove container after animation
        container.run(.sequence([
            .wait(forDuration: 1.0),
            .removeFromParent()
        ]))

        return container
    }

    /// The dead ship's own outline coming apart: every edge of its hull flung
    /// outwards and spinning, the way the opening film's entities die.
    ///
    /// - Parameters:
    ///   - path: The hull, in the ship's own coordinates.
    ///   - rotation, scale: The ship's, so the pieces start exactly where it was.
    static func shatter(path: CGPath, color: UIColor, at position: CGPoint,
                        rotation: CGFloat = 0, scale: CGFloat = 1) -> SKNode {
        var segments: [(CGPoint, CGPoint)] = []
        var start = CGPoint.zero
        var current = CGPoint.zero
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint:
                current = e.points[0]
                start = current
            case .addLineToPoint:
                segments.append((current, e.points[0]))
                current = e.points[0]
            case .addQuadCurveToPoint:
                segments.append((current, e.points[1]))
                current = e.points[1]
            case .addCurveToPoint:
                segments.append((current, e.points[2]))
                current = e.points[2]
            case .closeSubpath:
                if current != start { segments.append((current, start)) }
                current = start
            @unknown default:
                break
            }
        }
        // Long round outlines would throw a confetti of tiny pieces; keep it legible.
        if segments.count > 16 {
            let step = Int((Double(segments.count) / 16).rounded(.up))
            segments = stride(from: 0, to: segments.count, by: step).map { segments[$0] }
        }

        let container = SKNode()
        container.position = position
        container.zRotation = rotation
        container.setScale(scale)
        container.zPosition = 499

        for (a, b) in segments {
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let piece = LightSprite.tube(from: CGPoint(x: a.x - mid.x, y: a.y - mid.y),
                                         to: CGPoint(x: b.x - mid.x, y: b.y - mid.y), width: 1.7, color: color)
            piece.position = mid
            container.addChild(piece)

            let length = max(0.001, (mid.x * mid.x + mid.y * mid.y).squareRoot())
            let out = length > 0.5
                ? CGVector(dx: mid.x / length, dy: mid.y / length)
                : CGVector(dx: CGFloat.random(in: -1...1), dy: CGFloat.random(in: -1...1))
            let distance = CGFloat.random(in: 16...40)
            let fly = SKAction.moveBy(x: out.dx * distance, y: out.dy * distance, duration: 0.55)
            fly.timingMode = .easeOut
            let spin = SKAction.rotate(byAngle: CGFloat.random(in: -4...4), duration: 0.55)
            let fade = SKAction.fadeOut(withDuration: 0.55)
            fade.timingMode = .easeIn
            piece.run(.group([fly, spin, fade, .scale(to: 0.6, duration: 0.55)]))
        }
        container.run(.sequence([.wait(forDuration: 0.6), .removeFromParent()]))
        return container
    }

    /// Full-screen bleach, only for the heavy hits and kept brief.
    ///
    /// Stays a separate call because it is the one layer that does not belong to the
    /// burst node — it covers the whole scene, so `burst(size:particleMultiplier:)` has
    /// nothing to hang it on.
    static func screenFlash(for size: ExplosionSize, in scene: SKScene) {
        let hot = UIColor(red: 1.0, green: 0.96, blue: 0.82, alpha: 1.0)
        if size == .huge {
            NeonFX.screenFlash(in: scene, color: hot, alpha: 0.20, duration: 0.16)
        } else if size == .large {
            NeonFX.screenFlash(in: scene, color: hot, alpha: 0.10, duration: 0.12)
        }
    }
}
