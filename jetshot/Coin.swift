//
//  Coin.swift
//  jetshot
//
//  Created by Robert Libšanský on 01.11.2025.
//

import SpriteKit

class Coin: SKNode {
    private var shape: SKShapeNode!
    private let size: CGFloat = 24
    let pointValue: Int = 10

    init(position: CGPoint) {
        super.init()

        self.position = position
        self.name = "coin"

        setupVisuals()
        setupPhysics()
        addAnimations()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // Deliberately does not stop actions.
        //
        // `shape?.removeAllActions()` / `removeAllActions()` used to run here, which was
        // both pointless and unsound: a node owns its action list, so deallocating it
        // discards those actions anyway, and `deinit` is nonisolated while SKNode's
        // methods are main-actor isolated under this project's default isolation —
        // an error in the Swift 6 language mode.

        // No cache unregistration here either. It was unreachable twice over: GameScene's
        // activeCoins holds a strong reference, so deinit cannot run while the coin is
        // still listed, and by the time it does run the node is already detached, making
        // `self.scene` nil. GameScene.pruneCoinCache() does the eviction instead.
    }

    /// The star-cut crystal, sized for the coin's radius (half its 24-point `size`).
    fileprivate static let crystal: WireMesh = {
        let radius: Float = 12
        let inner = radius * 0.4
        var vertices: [Vec3] = []
        for i in 0..<10 {
            // Same start as the star path in `setupVisuals`, so crystal and body agree.
            let a = Float(i) * .pi / 5 - .pi / 2
            let r = i % 2 == 0 ? radius : inner
            vertices.append(Vec3(cos(a) * r, sin(a) * r, 0))
        }
        vertices.append(Vec3(0, 0, radius * 0.45))
        vertices.append(Vec3(0, 0, -radius * 0.45))
        var edges: [(Int, Int)] = []
        for i in 0..<10 {
            edges.append((i, (i + 1) % 10))
            if i % 2 == 0 {
                edges.append((i, 10))
                edges.append((i, 11))
            }
        }
        return WireMesh(vertices: vertices, edges: edges)
    }()

    private func setupVisuals() {
        // Main container for star shape
        shape = SKShapeNode()

        // Create star with golden color
        let starColor = UIColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0) // Rich gold
        let starBorder = UIColor(red: 1.0, green: 0.95, blue: 0.3, alpha: 1.0) // Bright gold

        // Create 5-pointed star path
        let starPath = CGMutablePath()
        let radius: CGFloat = size / 2
        let innerRadius: CGFloat = radius * 0.4
        let points = 5

        for i in 0..<points * 2 {
            let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let currentRadius = i % 2 == 0 ? radius : innerRadius
            let x = currentRadius * cos(angle)
            let y = currentRadius * sin(angle)

            if i == 0 {
                starPath.move(to: CGPoint(x: x, y: y))
            } else {
                starPath.addLine(to: CGPoint(x: x, y: y))
            }
        }
        starPath.closeSubpath()

        // Warm halo behind the star, so a pickup reads as valuable at a glance
        // even against the brightest nebula.
        let halo = NeonFX.radialGlow(radius: radius * 2.2, color: UIColor(red: 1.0, green: 0.78, blue: 0.15, alpha: 1.0))
        halo.alpha = 0.55
        halo.zPosition = -2
        addChild(halo)
        let haloUp = SKAction.scale(to: 1.2, duration: 0.6)
        haloUp.timingMode = .easeInEaseOut
        let haloDown = SKAction.scale(to: 0.92, duration: 0.6)
        haloDown.timingMode = .easeInEaseOut
        halo.run(.repeatForever(.sequence([haloUp, haloDown])))

        // A faint gold body for the bloom to come off; the star itself is the crystal
        // below, turning in 3D.
        let mainStar = SKShapeNode(path: starPath)
        mainStar.fillColor = starColor.withAlphaComponent(0.22)
        mainStar.strokeColor = starBorder.withAlphaComponent(0.35)
        mainStar.lineWidth = 1
        shape.addChild(mainStar)

        // A star-cut crystal: the five-point outline raised to a point front and back,
        // spinning on its axis so it flashes its faces like the energy the opening film
        // shows being scooped up in the rift.
        let crystal = WireBody(extent: radius * 1.1, perspective: 4.5, interval: 1.0 / 30,
                               seed: Float.random(in: 0...20)) { frame in
            let q = rotation(frame.t * 2.2, Vec3(0, 1, 0)) * rotation(0.3, Vec3(1, 0, 0))
            frame.canvas.mesh(Coin.crystal, rotation: q, scale: 1, color: starBorder, alpha: 1, width: 1.2, backAlpha: 0.45)
        }
        crystal.zPosition = 1
        shape.addChild(crystal)

        // White-hot centre, which reads as a gemstone catching the light.
        let core = NeonFX.radialGlow(radius: radius * 0.55, color: UIColor(red: 1.0, green: 1.0, blue: 0.92, alpha: 1.0))
        core.zPosition = 2
        shape.addChild(core)

        addChild(shape)

        // Add stronger pulsing glow effect
        GlowHelper.addPulsingEnhancedGlow(
            to: mainStar,
            color: UIColor(red: 1.0, green: 0.9, blue: 0.2, alpha: 1.0),
            minIntensity: 0.8,
            maxIntensity: 1.2,
            duration: 1.0
        )

        addGlint(radius: radius)
    }

    /// Occasional four-ray glint. Non-periodic-looking sparkle is what makes a
    /// row of identical pickups feel alive instead of stamped.
    private func addGlint(radius: CGFloat) {
        let glint = SKNode()
        glint.zPosition = 3
        glint.alpha = 0
        addChild(glint)

        for i in 0..<2 {
            let ray = SKShapeNode(rectOf: CGSize(width: 1.6, height: radius * 3.4), cornerRadius: 0.8)
            ray.fillColor = .white
            ray.strokeColor = .clear
            ray.blendMode = .add
            ray.zRotation = CGFloat(i) * .pi / 2
            glint.addChild(ray)
        }

        let flash = SKAction.sequence([
            .wait(forDuration: Double.random(in: 0.4...2.6)),
            .group([.fadeAlpha(to: 0.9, duration: 0.09), .scale(to: 1.25, duration: 0.09)]),
            .group([.fadeOut(withDuration: 0.24), .scale(to: 0.7, duration: 0.24)]),
            .run { glint.setScale(1.0) },
            .wait(forDuration: Double.random(in: 1.4...3.4))
        ])
        glint.run(.repeatForever(flash))
    }

    private func setupPhysics() {
        let physicsBody = SKPhysicsBody(circleOfRadius: size / 2)
        physicsBody.isDynamic = true
        physicsBody.categoryBitMask = PhysicsCategory.coin
        physicsBody.contactTestBitMask = PhysicsCategory.collector
        physicsBody.collisionBitMask = PhysicsCategory.none
        physicsBody.usesPreciseCollisionDetection = true
        self.physicsBody = physicsBody
    }

    private func addAnimations() {
        // Random rotation direction (left or right)
        let rotationDirection: CGFloat = Bool.random() ? 1.0 : -1.0

        // Random rotation duration (slower = 4-8 seconds for full rotation)
        let rotationDuration = Double.random(in: 4.0...8.0)

        // Rotate with random direction and speed
        let rotate = SKAction.rotate(byAngle: .pi * 2 * rotationDirection, duration: rotationDuration)
        shape.run(SKAction.repeatForever(rotate))

        // Gentle vertical bobbing
        let moveUp = SKAction.moveBy(x: 0, y: 3, duration: 0.6)
        let moveDown = SKAction.moveBy(x: 0, y: -3, duration: 0.6)
        let bob = SKAction.sequence([moveUp, moveDown])
        shape.run(SKAction.repeatForever(bob))

        // Slow downward movement
        let moveDownScreen = SKAction.moveTo(y: -50, duration: 10.0)
        let remove = SKAction.removeFromParent()
        run(SKAction.sequence([moveDownScreen, remove]))
    }

    func collect(scorePosition: CGPoint) {
        // Immediately disable physics to prevent multiple collisions
        self.physicsBody = nil

        // Stop all existing animations
        removeAllActions()
        shape.removeAllActions()

        // Create collection sparkle effect at collection point
        createCollectionEffect()

        // Fly to score position animation
        let flyDuration: TimeInterval = 0.4
        let flyToScore = SKAction.move(to: scorePosition, duration: flyDuration)
        flyToScore.timingMode = .easeIn

        let shrink = SKAction.scale(to: 0.3, duration: flyDuration)
        let fadeOut = SKAction.fadeOut(withDuration: flyDuration * 0.7)
        fadeOut.timingMode = .easeIn

        let remove = SKAction.removeFromParent()

        run(SKAction.sequence([
            SKAction.group([flyToScore, shrink, fadeOut]),
            remove
        ]))
    }

    private func createCollectionEffect() {
        guard let parent = self.parent else { return }

        // Create sparkle particles
        let sparkle = SKEmitterNode()

        sparkle.particleTexture = ParticleTexture.solidCircle(diameter: 8)

        sparkle.particleBirthRate = 30
        sparkle.numParticlesToEmit = 20
        sparkle.particleLifetime = 0.5
        sparkle.particlePositionRange = CGVector(dx: 10, dy: 10)
        sparkle.particleSpeed = 50
        sparkle.particleSpeedRange = 30
        sparkle.emissionAngleRange = .pi * 2
        sparkle.particleAlpha = 1.0
        sparkle.particleAlphaSpeed = -2.0
        sparkle.particleScale = 0.3
        sparkle.particleScaleSpeed = -0.3
        sparkle.particleColor = UIColor(red: 1.0, green: 0.9, blue: 0.2, alpha: 1.0)
        sparkle.particleColorBlendFactor = 1.0
        sparkle.particleBlendMode = .add
        sparkle.position = self.position

        parent.addChild(sparkle)

        // Remove sparkle after animation
        sparkle.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.5),
            SKAction.removeFromParent()
        ]))
    }
}
