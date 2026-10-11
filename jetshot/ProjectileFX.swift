//
//  ProjectileFX.swift
//  jetshot
//

import SpriteKit
import UIKit

/// Every projectile in the game, as a single pre-lit sprite, plus the impact spark a
/// player round leaves on whatever it hits.
///
/// Projectiles used to be `SKShapeNode`s with a core child and a bloom child — three
/// nodes and a path tessellation per round. That was tolerable at the old 3.3 shots a
/// second; at the current cadence an eight-barrel ship has fifty-odd rounds in flight,
/// and shape nodes are the most expensive thing SpriteKit draws. Each kind here is one
/// `SKSpriteNode` over a texture rendered once, glow included, which is what lets the
/// screen get busier without the frame rate paying for it.
///
/// It also fixes the language of the playfield. Enemy fire used to come in orange, red,
/// blue and yellow — the same family as the enemies themselves, the explosions and the
/// coins — so a round in flight had to be read rather than seen. Every hostile round is
/// now hot pink with a white core, the shmup convention for "this kills you", and
/// nothing else on the screen uses that colour. Everything the player fires is cyan,
/// amber or gold.
/// A round the player fired: a sprite that knows how hard it hits.
///
/// A subclass rather than `userData`, because this is read on every contact and built
/// dozens of times a second — a typed stored property is free where a dictionary per
/// round is not.
final class PlayerRound: SKSpriteNode {
    /// Hit points taken off whatever this lands on.
    var damage: Int = CombatRules.boltDamage
}

enum ProjectileFX {

    // MARK: - Palette

    /// Hostile fire. Reserved: nothing friendly, and nothing decorative, may use it.
    static let hostile = UIColor(red: 1.0, green: 0.2, blue: 0.55, alpha: 1.0)
    static let hostileRim = UIColor(red: 1.0, green: 0.62, blue: 0.82, alpha: 1.0)
    /// Homing rounds: still in the hostile family, pushed towards violet so the one
    /// round that follows you reads differently from the ones that do not.
    static let hostileHoming = UIColor(red: 0.78, green: 0.32, blue: 1.0, alpha: 1.0)

    static let playerBolt = UIColor(red: 0.25, green: 1.0, blue: 0.9, alpha: 1.0)
    static let overdriveBolt = UIColor(red: 1.0, green: 0.78, blue: 0.22, alpha: 1.0)

    // MARK: - Kinds

    /// The shapes hostile fire comes in. The size grows with the threat, the colour
    /// never changes.
    enum HostileKind {
        /// The default round most enemies fire.
        case orb
        /// Tank spread and turret bursts: bigger, slower, same hue.
        case heavy
        /// Sniper's aimed shot: a needle, rotated along its flight.
        case needle
        /// Boss fire.
        case boss
        /// Boss homing rounds.
        case homing

        /// Radius of the drawn body, in points.
        var radius: CGFloat {
            switch self {
            case .orb: return 6
            case .heavy: return 7
            case .needle: return 4
            case .boss: return 8
            case .homing: return 7.5
            }
        }

        /// Radius of the collision circle. Deliberately inside the drawn body: a round
        /// that visibly misses must actually miss, and the glow is not the bullet.
        var hitRadius: CGFloat {
            return radius * 0.78
        }
    }

    // MARK: - Factories

    /// A player round. Physics and name are set up; the caller only flies it.
    static func playerRound(overdrive: Bool = false) -> PlayerRound {
        let texture = overdrive ? overdriveBoltTexture : boltTexture
        let sprite = PlayerRound(texture: texture)
        sprite.size = texture.size()
        sprite.blendMode = .add
        sprite.name = "bullet"
        sprite.zPosition = 8
        sprite.damage = overdrive ? CombatRules.overdriveBoltDamage : CombatRules.boltDamage

        let body = SKPhysicsBody(rectangleOf: CGSize(width: overdrive ? 7 : 5, height: 26))
        body.isDynamic = true
        body.categoryBitMask = PhysicsCategory.bullet
        body.contactTestBitMask = PhysicsCategory.enemy | PhysicsCategory.obstacle
        body.collisionBitMask = PhysicsCategory.none
        body.usesPreciseCollisionDetection = true
        body.affectedByGravity = false
        sprite.physicsBody = body
        return sprite
    }

    /// A missile the player fired: the wing launchers' (`homing: false`, named
    /// `missile`) or the homing power-up's (named `homingMissile`). Amber, like
    /// everything else the player launches that is not a bolt; the homing missiles used
    /// to be pink, which is now the colour reserved for hostile fire.
    static func missile(homing: Bool) -> PlayerRound {
        let texture = missileTexture
        let sprite = PlayerRound(texture: texture)
        sprite.size = homing ? CGSize(width: texture.size().width * 1.15, height: texture.size().height * 1.15)
                             : texture.size()
        sprite.blendMode = .alpha
        sprite.name = homing ? "homingMissile" : "missile"
        sprite.zPosition = 9
        sprite.damage = homing ? CombatRules.homingMissileDamage : CombatRules.sideMissileDamage

        let body = SKPhysicsBody(rectangleOf: CGSize(width: 8, height: 20))
        body.isDynamic = true
        body.categoryBitMask = PhysicsCategory.bullet
        // Homing missiles fly over walls to reach their target; wing missiles do not.
        body.contactTestBitMask = homing ? PhysicsCategory.enemy : PhysicsCategory.enemy | PhysicsCategory.obstacle
        body.collisionBitMask = PhysicsCategory.none
        body.usesPreciseCollisionDetection = true
        body.affectedByGravity = false
        sprite.physicsBody = body
        return sprite
    }

    /// A hostile round, named `enemyBullet` so every sweep finds it, with its physics
    /// body attached. The caller positions it and either flies it with an action or
    /// gives the body a velocity.
    static func hostileRound(_ kind: HostileKind) -> SKSpriteNode {
        let texture = hostileTexture(kind)
        let sprite = SKSpriteNode(texture: texture)
        sprite.size = texture.size()
        sprite.name = "enemyBullet"
        // Above enemies, shards, sparks and the player's own fire, so nothing friendly
        // ever hides a round that can kill. Under the HUD.
        sprite.zPosition = 90

        let body = SKPhysicsBody(circleOfRadius: kind.hitRadius)
        body.isDynamic = true
        body.categoryBitMask = PhysicsCategory.enemyBullet
        body.contactTestBitMask = PhysicsCategory.player
        body.collisionBitMask = PhysicsCategory.none
        body.usesPreciseCollisionDetection = true
        body.affectedByGravity = false
        body.linearDamping = 0
        body.angularDamping = 0
        sprite.physicsBody = body

        if kind == .homing {
            // The one round that turns: give it a slow throb so it is picked out of a
            // field of otherwise identical dots before it starts to follow.
            let throb = SKAction.sequence([
                .scale(to: 1.18, duration: 0.22),
                .scale(to: 0.92, duration: 0.22)
            ])
            sprite.run(.repeatForever(throb), withKey: "throb")
        }
        return sprite
    }

    /// Turns a projectile that was the player's into a hostile one, in place — the
    /// mirror enemy's reflection. Swaps the art and the collision mask; the caller sets
    /// the new velocity.
    static func convertToHostile(_ node: SKNode) {
        node.name = "enemyBullet"
        node.physicsBody?.categoryBitMask = PhysicsCategory.enemyBullet
        node.physicsBody?.contactTestBitMask = PhysicsCategory.player
        node.physicsBody?.collisionBitMask = PhysicsCategory.none
        node.physicsBody?.linearDamping = 0
        if let sprite = node as? SKSpriteNode {
            let texture = hostileTexture(.needle)
            sprite.texture = texture
            sprite.size = texture.size()
            sprite.blendMode = .alpha
            sprite.colorBlendFactor = 0
        }
    }

    // MARK: - Impact

    /// The spark a round throws when it lands. Three sprites and a flash, all cached
    /// textures — this fires dozens of times a second with a full arsenal, so it must
    /// never build a shape node.
    ///
    /// The streaks spray back down-range, towards the shooter: that is what a round
    /// shattering on armour does, and it reads as the hit landing *on* the target
    /// rather than as a firework centred on it.
    static func impact(at position: CGPoint, color: UIColor, scale: CGFloat = 1.0) -> SKNode {
        let container = SKNode()
        container.position = position
        container.zPosition = 40

        let flash = SKSpriteNode(texture: flashTexture)
        flash.size = CGSize(width: 22 * scale, height: 22 * scale)
        flash.color = color
        flash.colorBlendFactor = 0.55
        flash.blendMode = .add
        container.addChild(flash)
        flash.run(.group([
            .scale(to: 1.7, duration: 0.09),
            .fadeOut(withDuration: 0.09)
        ]))

        for _ in 0..<3 {
            let streak = SKSpriteNode(texture: streakTexture)
            streak.size = CGSize(width: 3 * scale, height: CGFloat.random(in: 9...14) * scale)
            streak.color = color
            streak.colorBlendFactor = 0.7
            streak.blendMode = .add
            let angle = -CGFloat.pi / 2 + CGFloat.random(in: -1.25...1.25)
            streak.zRotation = angle - .pi / 2
            let distance = CGFloat.random(in: 14...26) * scale
            let travel = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: 0.16)
            travel.timingMode = .easeOut
            streak.run(.group([travel, .fadeOut(withDuration: 0.16), .scaleY(to: 0.3, duration: 0.16)]))
            container.addChild(streak)
        }

        container.run(.sequence([.wait(forDuration: 0.18), .removeFromParent()]))
        return container
    }

    /// Hostile round dissolving — used when Overdrive cancels the screen and when the
    /// barrier eats a shot. Cheap for the same reason as `impact`.
    static func cancelPop(at position: CGPoint) -> SKNode {
        let pop = SKSpriteNode(texture: flashTexture)
        pop.position = position
        pop.size = CGSize(width: 18, height: 18)
        pop.color = hostileRim
        pop.colorBlendFactor = 0.6
        pop.blendMode = .add
        pop.zPosition = 40
        pop.run(.sequence([
            .group([.scale(to: 1.9, duration: 0.14), .fadeOut(withDuration: 0.14)]),
            .removeFromParent()
        ]))
        return pop
    }

    // MARK: - Textures

    private static var cache: [String: SKTexture] = [:]

    static func clearCaches() {
        cache.removeAll()
    }

    private static var boltTexture: SKTexture {
        cached("bolt") {
            renderBolt(core: CGSize(width: 2.4, height: 30), body: CGSize(width: 5, height: 34),
                       canvas: CGSize(width: 18, height: 50), glow: playerBolt, blur: 7)
        }
    }

    private static var overdriveBoltTexture: SKTexture {
        cached("boltOverdrive") {
            renderBolt(core: CGSize(width: 3, height: 34), body: CGSize(width: 7, height: 38),
                       canvas: CGSize(width: 24, height: 58), glow: overdriveBolt, blur: 9)
        }
    }

    private static var missileTexture: SKTexture {
        cached("missile") {
            render(size: CGSize(width: 22, height: 40)) { cg, rect in
                let c = CGPoint(x: rect.midX, y: rect.midY)
                let amber = UIColor(red: 1.0, green: 0.55, blue: 0.12, alpha: 1.0)
                // UIKit's context is y-down, so the nose (top of the sprite) is at small y.
                let hull = UIBezierPath()
                hull.move(to: CGPoint(x: c.x, y: c.y - 13))
                hull.addQuadCurve(to: CGPoint(x: c.x + 3.6, y: c.y - 5), controlPoint: CGPoint(x: c.x + 3.6, y: c.y - 11))
                hull.addLine(to: CGPoint(x: c.x + 3.6, y: c.y + 6))
                hull.addLine(to: CGPoint(x: c.x + 7, y: c.y + 11))
                hull.addLine(to: CGPoint(x: c.x + 2, y: c.y + 9))
                hull.addLine(to: CGPoint(x: c.x - 2, y: c.y + 9))
                hull.addLine(to: CGPoint(x: c.x - 7, y: c.y + 11))
                hull.addLine(to: CGPoint(x: c.x - 3.6, y: c.y + 6))
                hull.addLine(to: CGPoint(x: c.x - 3.6, y: c.y - 5))
                hull.addQuadCurve(to: CGPoint(x: c.x, y: c.y - 13), controlPoint: CGPoint(x: c.x - 3.6, y: c.y - 11))
                hull.close()

                cg.saveGState()
                cg.setShadow(offset: .zero, blur: 6, color: amber.cgColor)
                amber.setFill()
                hull.fill()
                cg.restoreGState()

                UIColor(red: 1.0, green: 0.9, blue: 0.55, alpha: 1.0).setFill()
                UIBezierPath(roundedRect: CGRect(x: c.x - 1.4, y: c.y - 10, width: 2.8, height: 13), cornerRadius: 1.4).fill()

                // Exhaust: a short white-hot flame under the tail.
                cg.saveGState()
                cg.setShadow(offset: .zero, blur: 5, color: amber.cgColor)
                UIColor.white.setFill()
                UIBezierPath(ovalIn: CGRect(x: c.x - 2, y: c.y + 9, width: 4, height: 8)).fill()
                cg.restoreGState()
            }
        }
    }

    private static func hostileTexture(_ kind: HostileKind) -> SKTexture {
        switch kind {
        case .needle:
            return cached("needle") { renderNeedle() }
        case .homing:
            return cached("homing") { renderOrb(radius: kind.radius, color: hostileHoming) }
        default:
            return cached("orb-\(kind.radius)") { renderOrb(radius: kind.radius, color: hostile) }
        }
    }

    /// White, tinted per use through `color`/`colorBlendFactor`.
    private static var flashTexture: SKTexture {
        cached("flash") {
            render(size: CGSize(width: 32, height: 32)) { cg, rect in
                let colors = [
                    UIColor.white.cgColor,
                    UIColor.white.withAlphaComponent(0.55).cgColor,
                    UIColor.white.withAlphaComponent(0).cgColor
                ] as CFArray
                guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                                colors: colors, locations: [0, 0.3, 1]) else { return }
                let centre = CGPoint(x: rect.midX, y: rect.midY)
                cg.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
                                      endCenter: centre, endRadius: rect.width / 2, options: [])
            }
        }
    }

    private static var streakTexture: SKTexture {
        cached("streak") {
            render(size: CGSize(width: 6, height: 24)) { cg, rect in
                cg.setShadow(offset: .zero, blur: 2, color: UIColor.white.cgColor)
                UIColor.white.setFill()
                let capsule = UIBezierPath(roundedRect: rect.insetBy(dx: 1.8, dy: 2), cornerRadius: 1.2)
                capsule.fill()
            }
        }
    }

    private static func cached(_ key: String, _ make: () -> SKTexture) -> SKTexture {
        if let texture = cache[key] { return texture }
        let texture = make()
        cache[key] = texture
        return texture
    }

    private static func render(size: CGSize, draw: (CGContext, CGRect) -> Void) -> SKTexture {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            draw(ctx.cgContext, CGRect(origin: .zero, size: size))
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    /// A capsule of light: a coloured body thrown through a shadow blur for the glow,
    /// with a white-hot core on top. The core is what makes it read as energy rather
    /// than as a coloured stick.
    private static func renderBolt(core: CGSize, body: CGSize, canvas: CGSize,
                                   glow: UIColor, blur: CGFloat) -> SKTexture {
        return render(size: canvas) { cg, rect in
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            let bodyRect = CGRect(x: centre.x - body.width / 2, y: centre.y - body.height / 2,
                                  width: body.width, height: body.height)
            let coreRect = CGRect(x: centre.x - core.width / 2, y: centre.y - core.height / 2,
                                  width: core.width, height: core.height)

            cg.saveGState()
            cg.setShadow(offset: .zero, blur: blur, color: glow.cgColor)
            glow.setFill()
            UIBezierPath(roundedRect: bodyRect, cornerRadius: body.width / 2).fill()
            // Twice, so the halo carries some weight on a black field.
            UIBezierPath(roundedRect: bodyRect, cornerRadius: body.width / 2).fill()
            cg.restoreGState()

            UIColor.white.setFill()
            UIBezierPath(roundedRect: coreRect, cornerRadius: core.width / 2).fill()
        }
    }

    /// Hostile orb: glow, saturated body, a pale rim that separates it from bright
    /// backgrounds and explosions, and a white core.
    private static func renderOrb(radius r: CGFloat, color: UIColor) -> SKTexture {
        let pad = r * 1.3 + 3
        let side = (r + pad) * 2
        return render(size: CGSize(width: side, height: side)) { cg, rect in
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            let body = CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)

            cg.saveGState()
            cg.setShadow(offset: .zero, blur: r * 1.4, color: color.cgColor)
            color.setFill()
            cg.fillEllipse(in: body)
            cg.restoreGState()

            // Rim: a lighter ring just inside the edge.
            cg.setStrokeColor(hostileRim.cgColor)
            cg.setLineWidth(max(1, r * 0.2))
            cg.strokeEllipse(in: body.insetBy(dx: r * 0.12, dy: r * 0.12))

            let coreR = r * 0.48
            UIColor.white.setFill()
            cg.fillEllipse(in: CGRect(x: centre.x - coreR, y: centre.y - coreR, width: coreR * 2, height: coreR * 2))
        }
    }

    /// The sniper's needle: long, thin and pointed along +y, so `zRotation` can lay it
    /// along its flight.
    private static func renderNeedle() -> SKTexture {
        let canvas = CGSize(width: 18, height: 34)
        return render(size: canvas) { cg, rect in
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            let body = CGRect(x: centre.x - 3, y: centre.y - 10, width: 6, height: 20)

            cg.saveGState()
            cg.setShadow(offset: .zero, blur: 6, color: hostile.cgColor)
            hostile.setFill()
            UIBezierPath(roundedRect: body, cornerRadius: 3).fill()
            cg.restoreGState()

            UIColor.white.setFill()
            UIBezierPath(roundedRect: body.insetBy(dx: 1.6, dy: 2.5), cornerRadius: 1.4).fill()
        }
    }
}
