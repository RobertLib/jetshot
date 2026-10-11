//
//  ShardSystem.swift
//  jetshot
//

import SpriteKit
import UIKit

/// Energy shards: what a destroyed enemy bursts into, and what the Overdrive meter runs
/// on.
///
/// A kill used to be a number floating up from an explosion. Now it is also a handful of
/// glowing shards that spray out, hang for a moment and then stream into the ship —
/// straight away if the ship is close, after a beat if it is not. That gives every kill
/// a visible payout travelling back to the player, rewards flying *towards* the fight
/// (close kills pay out at once), and feeds the meter the Overdrive decision hangs on.
///
/// Every shard is eventually pulled in. An earlier version left distant shards to drift
/// down the screen to be chased, and a busy level ended up covered in green confetti
/// that the eye had to filter out from the fire it actually needed to read.
///
/// Shards fly on hand-integrated velocities rather than `SKAction`s: each one has to
/// re-aim at a moving ship every frame, and a few dozen custom actions per second would
/// cost more than the one loop here. The loop runs on the scene's gameplay clock, so a
/// pause freezes them and a hit-stop slows them with everything else.
final class ShardSystem {

    // MARK: - Tuning

    /// Radius inside which shards home on the ship as soon as they settle.
    static let attractRadius: CGFloat = 140
    /// Age at which every shard homes, however far away it is.
    static let recallTime: TimeInterval = 0.9
    /// Distance at which a homing shard counts as collected.
    static let collectRadius: CGFloat = 22
    /// How long a fresh shard hangs before it can be pulled in, so the burst is seen.
    static let settleTime: TimeInterval = 0.28
    /// A shard nobody collects is gone after this long, or once it leaves the screen.
    static let lifetime: TimeInterval = 7.0
    /// Upper bound on live shards. An Overdrive cancelling a boss barrage can convert a
    /// hundred rounds at once; past this the oldest are simply retired.
    static let maxLive = 180

    static let color = UIColor(red: 0.55, green: 1.0, blue: 0.42, alpha: 1.0)

    // MARK: - State

    private struct Shard {
        let node: SKSpriteNode
        var velocity: CGVector
        var age: TimeInterval
        var homing: Bool
    }

    private var shards: [Shard] = []
    private weak var parent: SKNode?

    /// Called once per collected shard, with where it was collected.
    var onCollect: ((CGPoint) -> Void)?

    /// Live shard count, for tests.
    var liveCount: Int { shards.count }

    init(parent: SKNode) {
        self.parent = parent
    }

    // MARK: - Spawning

    /// Bursts `count` shards out of `position`.
    func spawn(at position: CGPoint, count: Int, speed: ClosedRange<CGFloat> = 90...200) {
        guard let parent = parent, count > 0 else { return }

        for _ in 0..<count {
            let node = SKSpriteNode(texture: Self.texture)
            node.size = Self.texture.size()
            node.position = position
            node.zPosition = 30
            node.blendMode = .add
            node.zRotation = CGFloat.random(in: 0...(.pi * 2))
            node.setScale(CGFloat.random(in: 0.85...1.1))
            parent.addChild(node)

            // A slight upward bias, so the burst blooms rather than drops.
            let angle = CGFloat.random(in: 0...(.pi * 2))
            let magnitude = CGFloat.random(in: speed)
            let velocity = CGVector(dx: cos(angle) * magnitude, dy: sin(angle) * magnitude + 40)
            shards.append(Shard(node: node, velocity: velocity, age: 0, homing: false))
        }

        if shards.count > Self.maxLive {
            let overflow = shards.count - Self.maxLive
            for shard in shards.prefix(overflow) { shard.node.removeFromParent() }
            shards.removeFirst(overflow)
        }
    }

    // MARK: - Simulation

    /// Advances every shard by `deltaTime`.
    ///
    /// - Parameters:
    ///   - target: where the ship is. Homing shards steer for it.
    ///   - attractAll: true while something (Magnet, Overdrive) pulls every shard in
    ///     regardless of distance.
    ///   - floor: the y below which a shard is considered lost.
    func update(deltaTime dt: TimeInterval, target: CGPoint?, attractAll: Bool, floor: CGFloat = -30) {
        guard !shards.isEmpty else { return }
        let step = CGFloat(dt)

        var index = 0
        while index < shards.count {
            var shard = shards[index]
            shard.age += dt

            if let target = target, shard.age >= Self.settleTime {
                let dx = target.x - shard.node.position.x
                let dy = target.y - shard.node.position.y
                let distance = (dx * dx + dy * dy).squareRoot()

                if distance <= Self.collectRadius {
                    collect(at: index)
                    continue
                }
                if attractAll || distance < Self.attractRadius || shard.age >= Self.recallTime {
                    // Once a shard has started for the ship it does not give up, so a
                    // player who darts away is chased rather than leaving a trail of
                    // shards stranded at the edge of the radius.
                    shard.homing = true
                }
                if shard.homing, distance > 0 {
                    let pull: CGFloat = 2600
                    shard.velocity.dx += dx / distance * pull * step
                    shard.velocity.dy += dy / distance * pull * step
                    // Bleed off the sideways component so they spiral in tightly.
                    shard.velocity.dx *= 1 - min(1, 3.5 * step)
                    shard.velocity.dy *= 1 - min(1, 3.5 * step)
                }
            }

            if !shard.homing {
                // Air drag on the burst, then a slow fall.
                let drag = 1 - min(1, 3.2 * step)
                shard.velocity.dx *= drag
                shard.velocity.dy *= drag
                if shard.age > Self.settleTime {
                    shard.velocity.dy -= 85 * step
                    shard.velocity.dy = max(shard.velocity.dy, -120)
                }
            }

            let speedLimit: CGFloat = 950
            let speed = (shard.velocity.dx * shard.velocity.dx + shard.velocity.dy * shard.velocity.dy).squareRoot()
            if speed > speedLimit {
                shard.velocity.dx *= speedLimit / speed
                shard.velocity.dy *= speedLimit / speed
            }

            shard.node.position.x += shard.velocity.dx * step
            shard.node.position.y += shard.velocity.dy * step
            shard.node.zRotation += 7 * step

            let expired = shard.age > Self.lifetime || shard.node.position.y < floor
            if expired {
                shard.node.removeFromParent()
                shards.remove(at: index)
                continue
            }

            // Fade out over the last second of life, so a lost shard dims away instead
            // of popping.
            let remaining = Self.lifetime - shard.age
            shard.node.alpha = remaining < 1 ? CGFloat(max(0, remaining)) : 1

            shards[index] = shard
            index += 1
        }
    }

    private func collect(at index: Int) {
        let node = shards[index].node
        let position = node.position
        node.removeFromParent()
        shards.remove(at: index)
        onCollect?(position)
    }

    /// Drops every shard, for teardown.
    func removeAll() {
        for shard in shards { shard.node.removeFromParent() }
        shards.removeAll()
    }

    // MARK: - Art

    private static var cachedTexture: SKTexture?

    static func clearCache() {
        cachedTexture = nil
    }

    /// A small faceted diamond with a hot centre and a soft glow.
    static var texture: SKTexture {
        if let texture = cachedTexture { return texture }

        let side: CGFloat = 22
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let cg = ctx.cgContext
            let c = CGPoint(x: side / 2, y: side / 2)
            let diamond = UIBezierPath()
            diamond.move(to: CGPoint(x: c.x, y: c.y - 6.5))
            diamond.addLine(to: CGPoint(x: c.x + 4.2, y: c.y))
            diamond.addLine(to: CGPoint(x: c.x, y: c.y + 6.5))
            diamond.addLine(to: CGPoint(x: c.x - 4.2, y: c.y))
            diamond.close()

            cg.saveGState()
            cg.setShadow(offset: .zero, blur: 5, color: color.cgColor)
            color.setFill()
            diamond.fill()
            cg.restoreGState()

            // Facet: the left half a shade brighter reads as a cut stone catching light.
            let facet = UIBezierPath()
            facet.move(to: CGPoint(x: c.x, y: c.y - 6.5))
            facet.addLine(to: CGPoint(x: c.x - 4.2, y: c.y))
            facet.addLine(to: CGPoint(x: c.x, y: c.y + 6.5))
            facet.close()
            UIColor.white.withAlphaComponent(0.45).setFill()
            facet.fill()

            UIColor.white.setFill()
            cg.fillEllipse(in: CGRect(x: c.x - 1.4, y: c.y - 1.4, width: 2.8, height: 2.8))
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        cachedTexture = texture
        return texture
    }
}
