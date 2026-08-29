//
//  BossManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 26.10.2025.
//

import SpriteKit

/// Manages boss spawning, attacks, and defeat animations.
/// Handles boss-specific combat mechanics and visual effects.
class BossManager {
    private weak var scene: GameScene?
    private var boss: Boss?
    private var isAttacking: Bool = false
    private weak var player: Player?

    /// Act the fight is currently in, so a crossing can be detected on the damage that
    /// causes it. See `BossPhaseRules`.
    private var currentPhase: Int = 0

    /// Index into the boss's available patterns of the attack that just fired, so the
    /// next draw can avoid repeating it.
    ///
    /// A plain `randomElement()` over fourteen patterns still lands the same attack twice
    /// in a row about seven per cent of the time, and a repeated barrage reads as the
    /// fight glitching rather than as bad luck.
    private var lastPatternIndex: Int?

    init(scene: GameScene) {
        self.scene = scene
    }

    func setPlayer(_ player: Player) {
        self.player = player
    }

    func spawnBoss(level: Int, completion: @escaping () -> Void) {
        guard let scene = scene else { return }

        let config = BossConfig.config(for: level)
        let newBoss = Boss(config: config, sceneSize: scene.size)
        boss = newBoss

        // Add boss to game content node
        scene.gameContentNode.addChild(newBoss)
        newBoss.addHealthBarToScene(scene)

        // Wait for entrance animation.
        // Weak capture: the closure is retained by an action on the boss, which this
        // manager owns — capturing self strongly closed a manager → boss → closure →
        // manager cycle for the length of the fight.
        newBoss.enterScene { [weak self] in
            self?.startAttacking()
            completion()
        }
    }

    func startAttacking() {
        isAttacking = true
        currentPhase = boss?.currentPhase ?? 0
        scheduleNextAttack()
    }

    private func scheduleNextAttack() {
        guard isAttacking, let boss = boss, boss.isAlive() else { return }

        // A cornered boss presses harder. Scaling the whole range rather than the
        // minimum keeps the rhythm irregular in every act.
        let scale = BossPhaseRules.attackDelayScale(forPhase: currentPhase)
        let delay = TimeInterval.random(
            in: (GameConfiguration.bossAttackDelayMin * scale)...(GameConfiguration.bossAttackDelayMax * scale)
        )

        guard let (pattern, telegraph) = nextAttack() else { return }

        // Wind up, then fire. Splitting the delay this way rather than adding the
        // telegraph on top of it keeps the attack cadence exactly what the tuning above
        // says it is — the warning comes out of the gap, not after it.
        let leadIn = max(0, delay - telegraph)

        // Use SKAction instead of DispatchQueue to respect pause state
        let sequence = SKAction.sequence([
            SKAction.wait(forDuration: leadIn),
            SKAction.run { [weak self] in
                self?.playTelegraph(duration: telegraph)
            },
            SKAction.wait(forDuration: telegraph),
            SKAction.run { [weak self] in
                self?.performAttack(pattern)
                self?.scheduleNextAttack()
            }
        ])
        boss.run(sequence, withKey: "bossAttackSchedule")
    }

    /// Draws the next attack and how long it should be signalled for, or nil if the boss
    /// has nothing available.
    private func nextAttack() -> (pattern: BossAttackPattern, telegraph: TimeInterval)? {
        guard let boss = boss else { return nil }

        let available = boss.availableAttackPatterns()
        guard !available.isEmpty else { return nil }

        var index = Int.random(in: 0..<available.count)
        if available.count > 1, let last = lastPatternIndex, index == last {
            // One deterministic step aside rather than a re-roll loop: it cannot spin,
            // and over many draws it is indistinguishable from rejection sampling.
            index = (index + 1) % available.count
        }
        lastPatternIndex = index

        let telegraph = BossPhaseRules.telegraphDuration(
            forPatternIndex: index,
            totalPatterns: available.count
        )
        return (available[index], telegraph)
    }

    /// The wind-up: the boss swells while a ring collapses onto it, then it fires.
    ///
    /// A converging ring rather than a colour flash because `Boss` is an `SKShapeNode`.
    /// `SKAction.colorize` only drives `SKSpriteNode.color` and `colorBlendFactor`, which
    /// a shape node does not have — it is accepted, runs for its full duration and does
    /// nothing at all, which would have left this "telegraph" as a barely perceptible 8%
    /// scale nudge. Convergence also reads better than brightness for a wind-up: it has a
    /// direction and an obvious arrival time.
    private func playTelegraph(duration: TimeInterval) {
        guard let boss = boss, boss.isAlive() else { return }

        boss.removeAction(forKey: "bossTelegraph")
        boss.run(SKAction.sequence([
            SKAction.scale(to: 1.09, duration: duration * 0.75),
            SKAction.scale(to: 1.0, duration: duration * 0.25)
        ]), withKey: "bossTelegraph")

        let radius = boss.bossSize * 0.5
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.strokeColor = boss.telegraphColor
        ring.fillColor = .clear
        ring.lineWidth = 3
        ring.blendMode = .add
        ring.zPosition = -1
        ring.setScale(2.6)
        ring.alpha = 0
        boss.addChild(ring)

        ring.run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeAlpha(to: 0.9, duration: duration * 0.4),
                SKAction.scale(to: 1.0, duration: duration)
            ]),
            SKAction.fadeOut(withDuration: 0.1),
            SKAction.removeFromParent()
        ]))
    }

    /// Runs the escalation when the boss crosses a health threshold: everything stops,
    /// the boss flares, and it comes back attacking faster and with more of its list.
    private func advanceToPhase(_ phase: Int) {
        guard let boss = boss, boss.isAlive() else { return }

        currentPhase = phase
        lastPatternIndex = nil

        // Cancel the pending attack outright. Letting a wind-up that started in the
        // previous act land in the middle of the transition is exactly the kind of
        // unreadable moment the telegraph exists to remove.
        boss.removeAction(forKey: "bossAttackSchedule")
        boss.removeAction(forKey: "bossTelegraph")

        boss.playPhaseTransitionEffect()

        if let scene = scene {
            scene.shakeCamera(intensity: 12.0, duration: 0.4)
            SoundManager.shared.playBossAppearSound(on: scene)
            HapticManager.shared.heavyTap()
        }

        // Resume on the boss's own clock so a pause holds the breather too.
        boss.run(SKAction.sequence([
            SKAction.wait(forDuration: BossPhaseRules.phaseTransitionPause),
            SKAction.run { [weak self] in
                self?.scheduleNextAttack()
            }
        ]), withKey: "bossPhaseResume")
    }

    private func performAttack(_ pattern: BossAttackPattern) {
        guard let boss = boss, scene != nil, boss.isAlive() else { return }

        let bossPosition = boss.position

        switch pattern {
        case .straightShot:
            shootStraight(from: bossPosition)

        case .doubleShot:
            shootDouble(from: bossPosition)

        case .tripleShot:
            shootTriple(from: bossPosition)

        case .spread:
            shootSpread(from: bossPosition)

        case .aimed:
            shootAimed(from: bossPosition)

        case .spiral:
            shootSpiral(from: bossPosition)

        case .wave:
            shootWave(from: bossPosition)

        case .burst:
            shootBurst(from: bossPosition)

        case .homing:
            shootHoming(from: bossPosition)

        case .laser:
            shootLaser(from: bossPosition)

        // NEW HARDER ATTACK PATTERNS
        case .circularBarrage:
            shootCircularBarrage(from: bossPosition)

        case .cascade:
            shootCascade(from: bossPosition)

        case .doubleSpiral:
            shootDoubleSpiral(from: bossPosition)

        case .barrageRain:
            shootBarrageRain(from: bossPosition)

        case .zigzagPattern:
            shootZigzagPattern(from: bossPosition)

        case .sectorSweep:
            shootSectorSweep(from: bossPosition)
        }
    }

    // MARK: - Attack Patterns

    private func shootStraight(from position: CGPoint) {
        createBullet(at: position, angle: -.pi / 2)
        guard let scene = scene else { return }
        SoundManager.shared.playEnemyShootSound(on: scene)
    }

    private func shootDouble(from position: CGPoint) {
        let offset: CGFloat = 30
        createBullet(at: CGPoint(x: position.x - offset, y: position.y), angle: -.pi / 2)
        createBullet(at: CGPoint(x: position.x + offset, y: position.y), angle: -.pi / 2)
        guard let scene = scene else { return }
        SoundManager.shared.playEnemyShootSound(on: scene)
    }

    private func shootTriple(from position: CGPoint) {
        let offset: CGFloat = 40
        createBullet(at: CGPoint(x: position.x - offset, y: position.y), angle: -.pi / 2)
        createBullet(at: position, angle: -.pi / 2)
        createBullet(at: CGPoint(x: position.x + offset, y: position.y), angle: -.pi / 2)
        guard let scene = scene else { return }
        SoundManager.shared.playEnemyShootSound(on: scene)
    }

    private func shootSpread(from position: CGPoint) {
        let angles: [CGFloat] = [-0.8, -0.5, -0.2, 0.2, 0.5, 0.8]
        for angle in angles {
            createBullet(at: position, angle: -.pi / 2 + angle)
        }
        guard let scene = scene else { return }
        SoundManager.shared.playEnemyShootSound(on: scene)
    }

    private func shootAimed(from position: CGPoint) {
        guard let player = player else {
            shootStraight(from: position)
            return
        }

        let playerPosition = player.position
        let dx = playerPosition.x - position.x
        let dy = playerPosition.y - position.y
        let angle = atan2(dy, dx)

        createBullet(at: position, angle: angle, speed: 300)
        guard let scene = scene else { return }
        SoundManager.shared.playEnemyShootSound(on: scene)
    }

    private func shootSpiral(from position: CGPoint) {
        guard let boss = boss else { return }

        let bulletCount = 10
        var actions: [SKAction] = []

        for i in 0..<bulletCount {
            let spiralSpread = (CGFloat(i) / CGFloat(bulletCount)) * 1.2 - 0.6

            let shootAction = SKAction.run { [weak self] in
                self?.createBullet(at: position, angle: -.pi / 2 + spiralSpread, speed: 200)
                // Play sound every 3rd bullet to avoid spam
                if i % 3 == 0, let scene = self?.scene {
                    SoundManager.shared.playEnemyShootSound(on: scene)
                }
            }

            let waitAction = SKAction.wait(forDuration: 0.08)
            actions.append(waitAction)
            actions.append(shootAction)
        }

        let sequence = SKAction.sequence(actions)
        boss.run(sequence)
    }

    private func shootWave(from position: CGPoint) {
        guard let boss = boss else { return }

        let bulletCount = 8
        var actions: [SKAction] = []

        for i in 0..<bulletCount {
            let angle = -0.8 + (CGFloat(i) / CGFloat(bulletCount - 1)) * 1.6

            let shootAction = SKAction.run { [weak self] in
                self?.createBullet(at: position, angle: -.pi / 2 + angle)
                // Play sound every other bullet
                if i % 2 == 0, let scene = self?.scene {
                    SoundManager.shared.playEnemyShootSound(on: scene)
                }
            }

            let waitAction = SKAction.wait(forDuration: 0.1)
            actions.append(waitAction)
            actions.append(shootAction)
        }

        let sequence = SKAction.sequence(actions)
        boss.run(sequence)
    }

    private func shootBurst(from position: CGPoint) {
        guard let boss = boss else { return }

        var actions: [SKAction] = []

        for i in 0..<5 {
            let shootAction = SKAction.run { [weak self] in
                guard let self = self else { return }
                let offset: CGFloat = 40
                self.createBullet(at: CGPoint(x: position.x - offset, y: position.y), angle: -.pi / 2)
                self.createBullet(at: position, angle: -.pi / 2)
                self.createBullet(at: CGPoint(x: position.x + offset, y: position.y), angle: -.pi / 2)
                // Play sound every other burst
                if i % 2 == 0, let scene = self.scene {
                    SoundManager.shared.playEnemyShootSound(on: scene)
                }
            }

            let waitAction = SKAction.wait(forDuration: 0.1)
            actions.append(shootAction)
            actions.append(waitAction)
        }

        let sequence = SKAction.sequence(actions)
        boss.run(sequence)
    }

    private func shootHoming(from position: CGPoint) {
        guard let scene = scene, player != nil else {
            shootAimed(from: position)
            return
        }

        let bullet = createBullet(at: position, angle: -.pi / 2, speed: 150, isHoming: true)
        SoundManager.shared.playPowerUpSound(on: scene)  // Different sound for homing missiles

        // Add homing behavior
        let updateAction = SKAction.run { [weak self, weak bullet] in
            guard let self = self,
                  let bullet = bullet,
                  let player = self.player,
                  let bulletBody = bullet.physicsBody else { return }

            let playerPosition = player.position
            let bulletPosition = bullet.position
            let dx = playerPosition.x - bulletPosition.x
            let dy = playerPosition.y - bulletPosition.y
            let targetAngle = atan2(dy, dx)

            // Smooth rotation towards player
            let currentAngle = atan2(bulletBody.velocity.dy, bulletBody.velocity.dx)
            var angleDiff = targetAngle - currentAngle

            // Normalize angle difference
            while angleDiff > .pi { angleDiff -= 2 * .pi }
            while angleDiff < -.pi { angleDiff += 2 * .pi }

            let turnSpeed: CGFloat = 0.05
            let newAngle = currentAngle + angleDiff * turnSpeed

            let speed: CGFloat = 150
            bulletBody.velocity = CGVector(
                dx: cos(newAngle) * speed,
                dy: sin(newAngle) * speed
            )
        }

        let wait = SKAction.wait(forDuration: 0.05)
        let sequence = SKAction.sequence([updateAction, wait])
        bullet?.run(SKAction.repeat(sequence, count: 100))
    }

    private func shootLaser(from position: CGPoint) {
        guard let scene = scene else { return }

        // Warning indicator
        let warning = SKShapeNode(rectOf: CGSize(width: 8, height: scene.size.height))
        warning.fillColor = UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.3)
        warning.strokeColor = .red
        warning.lineWidth = 2
        warning.position = CGPoint(x: position.x, y: scene.size.height / 2)
        warning.zPosition = 5
        scene.gameContentNode.addChild(warning)

        // Warning sound
        SoundManager.shared.playPowerUpSound(on: scene)  // Using power-up sound for laser charge

        // Flash warning
        let flash = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.7, duration: 0.2),
            SKAction.fadeAlpha(to: 0.3, duration: 0.2)
        ])
        warning.run(SKAction.repeat(flash, count: 3))

        // Fire laser after delay - use SKAction to respect pause state
        let waitAction = SKAction.wait(forDuration: 1.2)
        let fireAction = SKAction.run { [weak self] in
            self?.fireLaserBeam(at: position, warning: warning)
        }
        let sequence = SKAction.sequence([waitAction, fireAction])
        warning.run(sequence, withKey: "laserFire")
    }

    private func fireLaserBeam(at position: CGPoint, warning: SKShapeNode) {
        guard let scene = scene else { return }

        let laser = SKShapeNode(rectOf: CGSize(width: 20, height: scene.size.height))
        laser.fillColor = .red
        laser.strokeColor = UIColor(red: 1.0, green: 0.5, blue: 0.5, alpha: 1.0)
        laser.lineWidth = 3
        laser.glowWidth = 15
        laser.position = CGPoint(x: position.x, y: scene.size.height / 2)
        laser.zPosition = 5
        laser.name = "bosslaser"

        // Physics for laser
        let physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 20, height: scene.size.height))
        physicsBody.categoryBitMask = PhysicsCategory.enemyBullet
        physicsBody.contactTestBitMask = PhysicsCategory.player
        physicsBody.collisionBitMask = PhysicsCategory.none
        physicsBody.isDynamic = false
        laser.physicsBody = physicsBody

        scene.gameContentNode.addChild(laser)
        warning.removeFromParent()

        // Laser sound and haptic
        SoundManager.shared.playExplosionSound(on: scene)  // Using explosion for laser blast
        HapticManager.shared.heavyTap()

        // Remove laser after short duration - use SKAction to respect pause state
        let waitAction = SKAction.wait(forDuration: 0.5)
        let removeAction = SKAction.removeFromParent()
        let sequence = SKAction.sequence([waitAction, removeAction])
        laser.run(sequence)
    }

    // MARK: - NEW HARDER ATTACK PATTERNS

    private func shootCircularBarrage(from position: CGPoint) {
        guard let boss = boss else { return }

        var actions: [SKAction] = []
        let bulletRings = 2 // Two rings of bullets
        let bulletsPerRing = 9 // 9 bullets per ring - leaves gaps

        for ring in 0..<bulletRings {
            let shootAction = SKAction.run { [weak self] in
                guard let self = self else { return }

                for i in 0..<bulletsPerRing {
                    let spreadAngle = (CGFloat(i) / CGFloat(bulletsPerRing + 2) - 0.5) * 1.8
                    self.createBullet(at: position, angle: -.pi / 2 + spreadAngle, speed: 200)
                }

                if let scene = self.scene {
                    SoundManager.shared.playEnemyShootSound(on: scene)
                }
                HapticManager.shared.lightTap()
            }

            actions.append(shootAction)
            if ring < bulletRings - 1 {
                actions.append(SKAction.wait(forDuration: 0.4))
            }
        }

        let sequence = SKAction.sequence(actions)
        boss.run(sequence)
    }

    private func shootCascade(from position: CGPoint) {
        guard let boss = boss, let scene = scene else { return }

        var actions: [SKAction] = []
        let columns = 6 // Fewer columns - leaves gaps
        let sceneWidth = scene.size.width
        let columnWidth = sceneWidth / CGFloat(columns + 1) // +1 for wider spacing

        // Create cascading effect from left to right
        for i in 0..<columns {
            let shootAction = SKAction.run { [weak self] in
                guard let self = self else { return }

                // Calculate X position for this column with offset
                let xPos = columnWidth * CGFloat(i + 1)

                // Create bullet at calculated position, shooting straight down
                let bulletPosition = CGPoint(x: xPos, y: position.y)
                self.createBullet(at: bulletPosition, angle: -.pi / 2) // Straight down

                // Only add diagonal variation every other column
                if i % 3 == 0 {
                    self.createBullet(at: bulletPosition, angle: -.pi / 2 - 0.12) // Slightly left
                } else if i % 3 == 2 {
                    self.createBullet(at: bulletPosition, angle: -.pi / 2 + 0.12) // Slightly right
                }

                if i % 2 == 0, let scene = self.scene {
                    SoundManager.shared.playEnemyShootSound(on: scene)
                }
            }

            actions.append(shootAction)
            actions.append(SKAction.wait(forDuration: 0.12)) // Slower cascade for readability
        }

        let sequence = SKAction.sequence(actions)
        boss.run(sequence)
    }

    private func shootDoubleSpiral(from position: CGPoint) {
        guard let boss = boss else { return }

        var actions: [SKAction] = []
        var currentSpread1: CGFloat = -0.4 // Start closer to center (more downward)
        var currentSpread2: CGFloat = 0.4  // Start closer to center (more downward)
        let bulletCount = 15 // Fewer bullets
        let spreadIncrement: CGFloat = 0.08 // Slower spread

        for i in 0..<bulletCount {
            let shootAction = SKAction.run { [weak self] in
                guard let self = self else { return }

                // First spiral - sweeps from left to right
                self.createBullet(at: position, angle: -.pi / 2 + currentSpread1, speed: 220)

                // Second spiral - sweeps from right to left
                self.createBullet(at: position, angle: -.pi / 2 + currentSpread2, speed: 220)

                if i % 4 == 0, let scene = self.scene {
                    SoundManager.shared.playEnemyShootSound(on: scene)
                }
            }

            currentSpread1 += spreadIncrement
            currentSpread2 -= spreadIncrement

            actions.append(shootAction)
            actions.append(SKAction.wait(forDuration: 0.12)) // Slightly slower
        }

        let sequence = SKAction.sequence(actions)
        boss.run(sequence)
    }

    private func shootBarrageRain(from position: CGPoint) {
        guard let boss = boss, let _ = scene else { return }

        var actions: [SKAction] = []
        let waves = 4 // Fewer waves
        let bulletsPerWave = 10 // Fewer bullets

        // Create one random safe gap that will be consistent across all waves
        let gapIndex = Int.random(in: 2...(bulletsPerWave - 4)) // Random position for gap
        let gapWidth = 3 // Wider gap for easier dodging

        for _ in 0..<waves {
            let shootAction = SKAction.run { [weak self] in
                guard let self = self, let scene = self.scene else { return }

                // Rain of bullets across screen width with one consistent gap
                for i in 0..<bulletsPerWave {
                    // Skip bullets in the gap area
                    if i >= gapIndex && i < gapIndex + gapWidth {
                        continue
                    }

                    let xOffset = (CGFloat(i) / CGFloat(bulletsPerWave - 1) - 0.5) * scene.size.width * 0.75
                    let bulletPos = CGPoint(x: position.x + xOffset, y: position.y)

                    // Slightly random downward angle
                    let baseAngle: CGFloat = -.pi / 2
                    let randomSpread: CGFloat = CGFloat.random(in: -0.15...0.15)

                    self.createBullet(at: bulletPos, angle: baseAngle + randomSpread, speed: 260)
                }

                if let scene = self.scene {
                    SoundManager.shared.playEnemyShootSound(on: scene)
                }
                HapticManager.shared.mediumTap()
            }

            actions.append(shootAction)
            actions.append(SKAction.wait(forDuration: 0.35)) // More time between waves
        }

        let sequence = SKAction.sequence(actions)
        boss.run(sequence)
    }

    private func shootZigzagPattern(from position: CGPoint) {
        guard let boss = boss else { return }

        var actions: [SKAction] = []
        let bulletGroups = 8
        var goingRight = true

        for group in 0..<bulletGroups {
            let shootAction = SKAction.run { [weak self] in
                guard let self = self else { return }

                // Zigzag pattern - 3 bullets at an angle
                let baseAngle: CGFloat = -.pi / 2
                let sideAngle: CGFloat = goingRight ? 0.4 : -0.4

                self.createBullet(at: position, angle: baseAngle + sideAngle, speed: 260)
                self.createBullet(at: position, angle: baseAngle + sideAngle * 0.5, speed: 260)
                self.createBullet(at: position, angle: baseAngle, speed: 260)

                if group % 2 == 0, let scene = self.scene {
                    SoundManager.shared.playEnemyShootSound(on: scene)
                }
            }

            goingRight.toggle()

            actions.append(shootAction)
            actions.append(SKAction.wait(forDuration: 0.15))
        }

        let sequence = SKAction.sequence(actions)
        boss.run(sequence)
    }

    private func shootSectorSweep(from position: CGPoint) {
        guard let boss = boss else { return }

        var actions: [SKAction] = []
        let sectors = 12 // Fewer sectors = bigger gaps between them
        let startSpread: CGFloat = -0.7 // Narrower sweep
        let endSpread: CGFloat = 0.7   // Narrower sweep

        for i in 0..<sectors {
            let shootAction = SKAction.run { [weak self] in
                guard let self = self else { return }

                // Sweeping barrage - fires in a sweeping fan pattern downward
                let progress = CGFloat(i) / CGFloat(sectors - 1)
                let centerSpread = startSpread + (endSpread - startSpread) * progress

                // Fire 3 bullets in a small fan
                for j in 0..<3 {
                    let spreadAngle = (CGFloat(j) - 1) * 0.25 // Slightly wider fan
                    self.createBullet(at: position, angle: -.pi / 2 + centerSpread + spreadAngle, speed: 220)
                }

                if i % 3 == 0, let scene = self.scene {
                    SoundManager.shared.playEnemyShootSound(on: scene)
                }
            }

            actions.append(shootAction)
            actions.append(SKAction.wait(forDuration: 0.15)) // More time between sectors
        }

        let sequence = SKAction.sequence(actions)
        boss.run(sequence)
    }

    // MARK: - Bullet Creation

    @discardableResult
    private func createBullet(at position: CGPoint, angle: CGFloat, speed: CGFloat = 250, isHoming: Bool = false) -> SKShapeNode? {
        guard let scene = scene else { return nil }

        let bullet = SKShapeNode(circleOfRadius: 8)
        bullet.fillColor = isHoming ? .yellow : .red
        bullet.strokeColor = isHoming ? UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0) : UIColor(red: 1.0, green: 0.5, blue: 0.5, alpha: 1.0)
        bullet.lineWidth = 2
        bullet.position = position
        bullet.zPosition = 5
        // Must match the spelling every other producer and every sweep uses.
        // SpriteKit name matching is case-sensitive, and this used to read
        // "enemybullet": since boss bullets carry no lifetime action of their own,
        // cleanupOffScreenBullets() was their only route out of the scene and it could
        // never match them. Every shot a boss fired stayed alive — physics body and
        // glow child included — for the rest of the level, and was also invisible to
        // slow motion and resetEntitySpeeds().
        bullet.name = "enemyBullet"

        // Add glow using GlowHelper
        let bulletColor = isHoming ? UIColor.yellow : UIColor.red
        GlowHelper.addEnhancedGlow(to: bullet, color: bulletColor, intensity: 0.9)

        // Add extra glow particle effect for homing bullets
        if isHoming {
            let glow = SKShapeNode(circleOfRadius: 6)
            glow.fillColor = UIColor(red: 1.0, green: 0.9, blue: 0.0, alpha: 0.5)
            glow.strokeColor = .clear
            glow.zPosition = -1
            bullet.addChild(glow)

            let pulse = SKAction.sequence([
                SKAction.scale(to: 1.5, duration: 0.3),
                SKAction.scale(to: 1.0, duration: 0.3)
            ])
            glow.run(SKAction.repeatForever(pulse))
        }

        // Physics
        let physicsBody = SKPhysicsBody(circleOfRadius: 8)
        physicsBody.categoryBitMask = PhysicsCategory.enemyBullet
        physicsBody.contactTestBitMask = PhysicsCategory.player
        physicsBody.collisionBitMask = PhysicsCategory.none
        physicsBody.velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
        physicsBody.linearDamping = 0
        physicsBody.angularDamping = 0
        bullet.physicsBody = physicsBody

        scene.gameContentNode.addChild(bullet)

        // Hard lifetime cap, so a boss bullet can never outlive the fight even if it
        // somehow stalls on screen. Enemy bullets already carry one of these; these
        // ones are driven by physics velocity rather than a move action, so this is a
        // plain wait rather than a move+remove sequence — a move action would fight
        // the velocity. The off-screen sweep still does the routine cleanup; this is
        // only the backstop.
        bullet.run(SKAction.sequence([
            SKAction.wait(forDuration: 8.0),
            SKAction.removeFromParent()
        ]), withKey: "bulletLifetime")

        return bullet
    }

    // MARK: - Boss Management

    func bossTakeDamage() -> (defeated: Bool, points: Int) {
        guard let boss = boss else { return (false, 0) }

        let phaseBefore = boss.currentPhase
        let defeated = boss.takeDamage()

        // Checked before the defeat branch returns, and only while the boss lives: a
        // dying boss crosses every remaining threshold on its way to zero, and firing a
        // transition into the defeat animation would fight it for the same nodes.
        if !defeated {
            let phaseAfter = boss.currentPhase
            if phaseAfter > phaseBefore {
                advanceToPhase(phaseAfter)
            }
        }

        if defeated {
            isAttacking = false
            let points = boss.getPoints()

            // Boss defeat animation is handled in takeDamage() method
            // Trigger camera shake effects during boss explosion sequence using SKAction
            guard let scene = scene else { return (true, points) }

            var shakeActions: [SKAction] = []

            // Small shakes for each explosion. Weak captures: the sequence is retained
            // by the host node, and a strong `self` would keep this manager alive
            // through the whole defeat animation.
            for i in 0..<8 {
                let wait = SKAction.wait(forDuration: 0.2)
                let shake = SKAction.run { [weak self] in
                    self?.scene?.shakeCamera(intensity: 8.0, duration: 0.2)
                }

                if i > 0 {
                    shakeActions.append(wait)
                }
                shakeActions.append(shake)
            }

            // Big shake for final explosion
            let finalWait = SKAction.wait(forDuration: 0.2)
            let finalShake = SKAction.run { [weak self] in
                self?.scene?.shakeCamera(intensity: 20.0, duration: 0.5)
            }
            shakeActions.append(finalWait)
            shakeActions.append(finalShake)

            // Hosted on gameContentNode, not the scene: the scene keeps ticking while
            // the game is paused, so this shake timeline used to run on behind the
            // pause menu, out of step with the explosions it is meant to accompany.
            scene.gameContentNode.run(SKAction.sequence(shakeActions), withKey: "bossCameraShakes")

            return (true, points)
        }

        return (false, 0)
    }

    func isBossActive() -> Bool {
        return boss?.isAlive() ?? false
    }

    func getBoss() -> Boss? {
        return boss
    }

    func getBossPosition() -> CGPoint? {
        return boss?.position
    }

    func cleanup() {
        isAttacking = false
        currentPhase = 0
        lastPatternIndex = nil
        boss?.removeAction(forKey: "bossPhaseResume")
        boss?.removeAction(forKey: "bossTelegraph")
        boss?.removeAction(forKey: "bossAttackSchedule")
        boss?.removeFromParent()
        boss?.removeHealthBarFromScene()
        boss = nil
    }

    // No deinit here on purpose.
    //
    // It used to call `cleanup()`, which is the one genuine actor-isolation violation
    // in the project: with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor this type is
    // MainActor-isolated, but `deinit` is not, so touching SKNode state from it is
    // unsound — and a hard error under the Swift 6 language mode. Deallocation is also
    // the wrong moment for it: it happens whenever the last reference happens to drop.
    // GameScene.willMove(from:) now calls `cleanup()` explicitly, on the main actor, at
    // a point where teardown order is actually known.
}
