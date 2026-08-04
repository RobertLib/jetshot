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
    /// The layers are deliberately staged in time — white flash, fireball, shockwave,
    /// then debris and smoke — because a blast that happens all on one frame reads as a
    /// single popping circle.
    ///
    /// The caller positions it and parents it (to `GameScene.effectsParent`, never the
    /// scene: the scene keeps ticking while the game is paused).
    static func burst(size: ExplosionSize, particleMultiplier: CGFloat) -> SKNode {
        let container = SKNode()
        container.zPosition = 500

        let sizeMultiplier = sizeMultiplier(for: size)

        let hot = UIColor(red: 1.0, green: 0.96, blue: 0.82, alpha: 1.0)
        let fire = UIColor(red: 1.0, green: 0.52, blue: 0.12, alpha: 1.0)
        let ember = UIColor(red: 1.0, green: 0.78, blue: 0.22, alpha: 1.0)

        // 1. White-hot core: brightest for only a couple of frames.
        let core = NeonFX.radialGlow(radius: 16 * sizeMultiplier, color: hot)
        core.zPosition = 4
        container.addChild(core)
        let coreGrow = SKAction.scale(to: 2.1, duration: 0.13)
        coreGrow.timingMode = .easeOut
        core.run(.group([coreGrow, .fadeOut(withDuration: 0.13)]))

        // 2. Fireball: bigger, slower, cooling as it expands.
        let fireball = NeonFX.radialGlow(radius: 22 * sizeMultiplier, color: fire)
        fireball.zPosition = 3
        fireball.alpha = 0.95
        container.addChild(fireball)
        let ballGrow = SKAction.scale(to: 2.6, duration: 0.34)
        ballGrow.timingMode = .easeOut
        let ballFade = SKAction.fadeOut(withDuration: 0.34)
        ballFade.timingMode = .easeIn
        fireball.run(.group([ballGrow, ballFade]))

        // 3. Shockwave ring, thinning as it travels outward.
        container.addChild(NeonFX.shockwave(
            at: .zero,
            startRadius: 10 * sizeMultiplier,
            endRadius: 62 * sizeMultiplier,
            color: ember,
            lineWidth: 2.5 + sizeMultiplier,
            duration: 0.42
        ))

        // A second, faster wave on the heavy hits reads as overpressure.
        if size == .large || size == .huge {
            container.addChild(NeonFX.shockwave(
                at: .zero,
                startRadius: 6 * sizeMultiplier,
                endRadius: 96 * sizeMultiplier,
                color: hot.withAlphaComponent(0.7),
                lineWidth: 2,
                duration: 0.3
            ))
        }

        // 4. Sparks: fast, thin, drag to a stop.
        let sparkCount = Int(CGFloat(Int(11 * sizeMultiplier)) * particleMultiplier)
        container.addChild(NeonFX.sparks(
            at: .zero,
            count: sparkCount,
            color: ember,
            speed: 62 * sizeMultiplier,
            length: 8 * min(sizeMultiplier, 1.4),
            lifetime: 0.34
        ))

        // 5. Debris chunks that tumble as they fly.
        let debrisCount = Int(CGFloat(Int(5 * sizeMultiplier)) * particleMultiplier)
        for i in 0..<max(0, debrisCount) {
            let angle = CGFloat(i) * .pi * 2 / CGFloat(max(1, debrisCount)) + CGFloat.random(in: -0.4...0.4)
            let chunkSize = CGFloat.random(in: 2...4) * min(sizeMultiplier, 1.5)
            let chunk = SKShapeNode(rectOf: CGSize(width: chunkSize, height: chunkSize * 1.4), cornerRadius: 0.6)
            chunk.fillColor = UIColor(red: 0.34, green: 0.25, blue: 0.22, alpha: 1.0)
            chunk.strokeColor = ember.withAlphaComponent(0.85)
            chunk.lineWidth = 0.8
            chunk.zPosition = 5
            container.addChild(chunk)

            let distance = CGFloat.random(in: 30...58) * sizeMultiplier
            let travel = SKAction.moveBy(
                x: cos(angle) * distance,
                y: sin(angle) * distance,
                duration: 0.55
            )
            travel.timingMode = .easeOut
            let tumble = SKAction.rotate(byAngle: CGFloat.random(in: -6...6), duration: 0.55)
            chunk.run(.group([travel, tumble, .fadeOut(withDuration: 0.55)]))
        }

        // 6. Smoke: lingers after the light is gone, so the blast leaves a mark.
        let smokeCount = max(1, Int(3 * particleMultiplier))
        for _ in 0..<smokeCount {
            let puff = NeonFX.radialGlow(
                radius: CGFloat.random(in: 13...20) * sizeMultiplier,
                color: UIColor(red: 0.30, green: 0.26, blue: 0.30, alpha: 1.0),
                softness: 0.75,
                additive: false
            )
            puff.alpha = 0.42
            puff.zPosition = 1
            puff.position = CGPoint(
                x: CGFloat.random(in: -10...10) * sizeMultiplier,
                y: CGFloat.random(in: -10...10) * sizeMultiplier
            )
            container.addChild(puff)

            let drift = SKAction.moveBy(
                x: CGFloat.random(in: -14...14) * sizeMultiplier,
                y: CGFloat.random(in: 4...18) * sizeMultiplier,
                duration: 0.85
            )
            let swell = SKAction.scale(to: 1.9, duration: 0.85)
            puff.run(.group([drift, swell, .fadeOut(withDuration: 0.85)]))
        }

        // Remove container after animation
        container.run(.sequence([
            .wait(forDuration: 1.1),
            .removeFromParent()
        ]))

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
