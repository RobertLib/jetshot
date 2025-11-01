//
//  BossManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 26.10.2025.
//

import SpriteKit

class BossManager {
    private weak var scene: GameScene?
    private var boss: Boss?
    private var attackTimer: Timer?
    private var isAttacking: Bool = false
    private weak var player: Player?

    init(scene: GameScene) {
        self.scene = scene
    }

    func setPlayer(_ player: Player) {
        self.player = player
    }

    func spawnBoss(level: Int, completion: @escaping () -> Void) {
        guard let scene = scene else { return }

        let config = BossConfig.config(for: level)
        boss = Boss(config: config, sceneSize: scene.size)

        scene.addChild(boss!)
        boss?.addHealthBarToScene(scene)

        // Wait for entrance animation
        boss?.enterScene {
            self.startAttacking()
            completion()
        }
    }

    func startAttacking() {
        isAttacking = true
        scheduleNextAttack()
    }

    private func scheduleNextAttack() {
        guard isAttacking, let boss = boss, boss.isAlive() else { return }

        let delay = TimeInterval.random(in: 1.5...3.5)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.performAttack()
            self?.scheduleNextAttack()
        }
    }

    private func performAttack() {
        guard let boss = boss,
              scene != nil,
              boss.isAlive(),
              let bossPosition = boss.position as CGPoint? else { return }

        let patterns = boss.getAttackPatterns()
        guard let pattern = patterns.randomElement() else { return }

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
        }
    }

    // MARK: - Attack Patterns

    private func shootStraight(from position: CGPoint) {
        createBullet(at: position, angle: -.pi / 2)
        SoundManager.shared.playEnemyShoot()
    }

    private func shootDouble(from position: CGPoint) {
        let offset: CGFloat = 30
        createBullet(at: CGPoint(x: position.x - offset, y: position.y), angle: -.pi / 2)
        createBullet(at: CGPoint(x: position.x + offset, y: position.y), angle: -.pi / 2)
        SoundManager.shared.playEnemyShoot()
    }

    private func shootTriple(from position: CGPoint) {
        let offset: CGFloat = 40
        createBullet(at: CGPoint(x: position.x - offset, y: position.y), angle: -.pi / 2)
        createBullet(at: position, angle: -.pi / 2)
        createBullet(at: CGPoint(x: position.x + offset, y: position.y), angle: -.pi / 2)
        SoundManager.shared.playEnemyShoot()
    }

    private func shootSpread(from position: CGPoint) {
        let angles: [CGFloat] = [-0.8, -0.5, -0.2, 0.2, 0.5, 0.8]
        for angle in angles {
            createBullet(at: position, angle: -.pi / 2 + angle)
        }
        SoundManager.shared.playEnemyShoot()
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
        SoundManager.shared.playEnemyShoot()
    }

    private func shootSpiral(from position: CGPoint) {
        guard let boss = boss else { return }

        let bulletCount = 12
        var actions: [SKAction] = []

        // Play sound at the beginning
        actions.append(SKAction.run {
            SoundManager.shared.playEnemyShoot()
        })

        for i in 0..<bulletCount {
            let angle = (CGFloat(i) / CGFloat(bulletCount)) * 2 * .pi

            let shootAction = SKAction.run { [weak self] in
                self?.createBullet(at: position, angle: angle - .pi / 2, speed: 200)
            }

            let waitAction = SKAction.wait(forDuration: 0.05)
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

        // Play sound at the beginning
        actions.append(SKAction.run {
            SoundManager.shared.playEnemyShoot()
        })

        for i in 0..<bulletCount {
            let angle = -0.8 + (CGFloat(i) / CGFloat(bulletCount - 1)) * 1.6

            let shootAction = SKAction.run { [weak self] in
                self?.createBullet(at: position, angle: -.pi / 2 + angle)
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

        for _ in 0..<5 {
            let shootAction = SKAction.run { [weak self] in
                self?.shootTriple(from: position)
            }

            let waitAction = SKAction.wait(forDuration: 0.1)
            actions.append(shootAction)
            actions.append(waitAction)
        }

        let sequence = SKAction.sequence(actions)
        boss.run(sequence)
    }

    private func shootHoming(from position: CGPoint) {
        guard player != nil else {
            shootAimed(from: position)
            return
        }

        SoundManager.shared.playEnemyShoot()

        let bullet = createBullet(at: position, angle: -.pi / 2, speed: 150, isHoming: true)

        // Add homing behavior
        let updateAction = SKAction.run { [weak self, weak bullet] in
            guard let self = self,
                  let bullet = bullet,
                  let player = self.player else { return }

            let playerPosition = player.position
            let bulletPosition = bullet.position
            let dx = playerPosition.x - bulletPosition.x
            let dy = playerPosition.y - bulletPosition.y
            let targetAngle = atan2(dy, dx)

            // Smooth rotation towards player
            let currentAngle = atan2(bullet.physicsBody!.velocity.dy, bullet.physicsBody!.velocity.dx)
            var angleDiff = targetAngle - currentAngle

            // Normalize angle difference
            while angleDiff > .pi { angleDiff -= 2 * .pi }
            while angleDiff < -.pi { angleDiff += 2 * .pi }

            let turnSpeed: CGFloat = 0.05
            let newAngle = currentAngle + angleDiff * turnSpeed

            let speed: CGFloat = 150
            bullet.physicsBody?.velocity = CGVector(
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

        // Play warning sound
        SoundManager.shared.playBossWarning()

        // Warning indicator
        let warning = SKShapeNode(rectOf: CGSize(width: 8, height: scene.size.height))
        warning.fillColor = UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.3)
        warning.strokeColor = .red
        warning.lineWidth = 2
        warning.position = CGPoint(x: position.x, y: scene.size.height / 2)
        warning.zPosition = 5
        scene.addChild(warning)

        // Flash warning
        let flash = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.7, duration: 0.2),
            SKAction.fadeAlpha(to: 0.3, duration: 0.2)
        ])
        warning.run(SKAction.repeat(flash, count: 3))

        // Fire laser after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.fireLaserBeam(at: position, warning: warning)
        }
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

        scene.addChild(laser)
        warning.removeFromParent()

        // Play laser sound and haptic
        SoundManager.shared.playEnemyShoot()
        HapticManager.shared.heavyTap()

        // Remove laser after short duration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            laser.removeFromParent()
        }
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
        bullet.name = "enemybullet"

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

        scene.addChild(bullet)

        return bullet
    }

    // MARK: - Boss Management

    func bossTakeDamage() -> (defeated: Bool, points: Int) {
        guard let boss = boss else { return (false, 0) }

        let defeated = boss.takeDamage()

        if defeated {
            isAttacking = false
            let points = boss.getPoints()

            boss.defeat {
                // Boss defeat animation completed
                // This is called after all explosions finish
            }

            // Trigger camera shake effects during boss explosion sequence
            // Small shakes for each explosion
            for i in 0..<8 {
                let delay = Double(i) * 0.2
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.scene?.shakeCamera(intensity: 8.0, duration: 0.2)
                }
            }

            // Big shake for final explosion
            let finalDelay = 8 * 0.2
            DispatchQueue.main.asyncAfter(deadline: .now() + finalDelay) {
                self.scene?.shakeCamera(intensity: 20.0, duration: 0.5)
            }

            return (true, points)
        }

        return (false, 0)
    }

    func isBossActive() -> Bool {
        return boss?.isAlive() ?? false
    }

    func getBossPosition() -> CGPoint? {
        return boss?.position
    }

    func cleanup() {
        isAttacking = false
        attackTimer?.invalidate()
        attackTimer = nil
        boss?.removeFromParent()
        boss?.removeHealthBarFromScene()
        boss = nil
    }

    deinit {
        cleanup()
    }
}
