//
//  FormationManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 20.10.2025.
//

import SpriteKit

// Formation pattern types
enum FormationPattern {
    case vShape      // V formation
    case line        // Single line
    case arc         // Curved arc
    case arrow       // Arrow/chevron shape (for scouts)
    case diamond     // Diamond shape (for elite guard)
    case box         // Rectangle formation (for bombers)
    case circle      // Circular formation (for spinners)
    case cross       // Cross/plus shape (for commanders)

    func positions(count: Int, centerX: CGFloat, startY: CGFloat, spacing: CGFloat) -> [CGPoint] {
        var positions: [CGPoint] = []

        switch self {
        case .vShape:
            // V shape formation
            let halfCount = count / 2
            for i in 0..<count {
                let offset = i - halfCount
                let x = centerX + CGFloat(offset) * spacing
                let y = startY - abs(CGFloat(offset)) * spacing * 0.5
                positions.append(CGPoint(x: x, y: y))
            }

        case .line:
            // Horizontal line
            let halfCount = count / 2
            for i in 0..<count {
                let offset = i - halfCount
                let x = centerX + CGFloat(offset) * spacing
                positions.append(CGPoint(x: x, y: startY))
            }

        case .arc:
            // Arc formation
            let radius: CGFloat = spacing * CGFloat(count) * 0.4
            let angleStep = .pi / CGFloat(count + 1)
            for i in 0..<count {
                let angle = angleStep * CGFloat(i + 1)
                let x = centerX + (CGFloat(i) - CGFloat(count - 1) / 2.0) * spacing * 0.8
                let y = startY - sin(angle) * radius * 0.3
                positions.append(CGPoint(x: x, y: y))
            }

        case .arrow:
            // Sharp arrow/chevron formation - narrow V pointing down
            let halfCount = count / 2
            for i in 0..<count {
                let offset = i - halfCount
                let x = centerX + CGFloat(offset) * spacing * 0.8
                let y = startY - abs(CGFloat(offset)) * spacing * 0.7 // Steeper than V
                positions.append(CGPoint(x: x, y: y))
            }

        case .diamond:
            // Diamond/rhombus shape
            if count == 1 {
                positions.append(CGPoint(x: centerX, y: startY))
            } else if count == 3 {
                // Simple diamond with 3
                positions.append(CGPoint(x: centerX, y: startY)) // Top
                positions.append(CGPoint(x: centerX - spacing, y: startY - spacing)) // Left
                positions.append(CGPoint(x: centerX + spacing, y: startY - spacing)) // Right
            } else {
                // Larger diamond
                let layers = (count + 3) / 4
                var index = 0
                for layer in 0..<layers {
                    if layer == 0 {
                        // Top point
                        positions.append(CGPoint(x: centerX, y: startY))
                        index += 1
                    } else {
                        // Sides
                        let layerY = startY - CGFloat(layer) * spacing
                        let layerWidth = CGFloat(layer) * spacing
                        positions.append(CGPoint(x: centerX - layerWidth, y: layerY))
                        index += 1
                        if index < count {
                            positions.append(CGPoint(x: centerX + layerWidth, y: layerY))
                            index += 1
                        }
                    }
                    if index >= count { break }
                }
            }

        case .box:
            // Rectangular box formation
            let rows = (count <= 4) ? 2 : 3
            let cols = (count + rows - 1) / rows
            var index = 0

            for row in 0..<rows {
                let rowY = startY - CGFloat(row) * spacing
                let rowCount = min(cols, count - index)
                let rowStartX = centerX - CGFloat(rowCount - 1) * spacing * 0.5

                for col in 0..<rowCount {
                    let x = rowStartX + CGFloat(col) * spacing
                    positions.append(CGPoint(x: x, y: rowY))
                    index += 1
                }
            }

        case .circle:
            // Circular formation
            let radius = spacing * 1.5
            let angleStep = (2.0 * .pi) / CGFloat(count)

            for i in 0..<count {
                let angle = angleStep * CGFloat(i) - .pi / 2 // Start at top
                let x = centerX + cos(angle) * radius
                let y = startY + sin(angle) * radius
                positions.append(CGPoint(x: x, y: y))
            }

        case .cross:
            // Cross/plus formation
            if count == 1 {
                positions.append(CGPoint(x: centerX, y: startY))
            } else if count <= 5 {
                // Simple cross with center
                positions.append(CGPoint(x: centerX, y: startY)) // Center
                if count > 1 {
                    positions.append(CGPoint(x: centerX, y: startY + spacing)) // Top
                }
                if count > 2 {
                    positions.append(CGPoint(x: centerX, y: startY - spacing)) // Bottom
                }
                if count > 3 {
                    positions.append(CGPoint(x: centerX - spacing, y: startY)) // Left
                }
                if count > 4 {
                    positions.append(CGPoint(x: centerX + spacing, y: startY)) // Right
                }
            } else {
                // Extended cross
                let armLength = (count - 1) / 4
                positions.append(CGPoint(x: centerX, y: startY)) // Center
                var index = 1

                // Vertical arm (up)
                for i in 1...armLength {
                    if index >= count { break }
                    positions.append(CGPoint(x: centerX, y: startY + CGFloat(i) * spacing))
                    index += 1
                }
                // Vertical arm (down)
                for i in 1...armLength {
                    if index >= count { break }
                    positions.append(CGPoint(x: centerX, y: startY - CGFloat(i) * spacing))
                    index += 1
                }
                // Horizontal arm (left)
                for i in 1...armLength {
                    if index >= count { break }
                    positions.append(CGPoint(x: centerX - CGFloat(i) * spacing, y: startY))
                    index += 1
                }
                // Horizontal arm (right)
                for i in 1...armLength {
                    if index >= count { break }
                    positions.append(CGPoint(x: centerX + CGFloat(i) * spacing, y: startY))
                    index += 1
                }
            }
        }

        return positions
    }
}

// Attack pattern for formation enemies
enum AttackPattern {
    case dive        // Dive straight down
    case loop        // Loop attack
    case swoop       // Swoop from side
    case spiral      // Spiral attack (for spinners)
    case wave        // Wave attack (for commanders)

    func createPath(from start: CGPoint, sceneSize: CGSize) -> [CGPoint] {
        var path: [CGPoint] = []

        switch self {
        case .dive:
            // Simple dive - smooth downward path with gentle curve
            let steps = 20
            for i in 0...steps {
                let progress = CGFloat(i) / CGFloat(steps)
                let y = start.y - (start.y + 20) * progress
                // Gentle sine wave for variety
                let xOffset = sin(progress * .pi * 2) * 30
                let x = start.x + xOffset
                path.append(CGPoint(x: x, y: y))
            }

        case .loop:
            // Circular loop attack - smooth circle starting from current position
            let loopRadius: CGFloat = 80

            // Calculate starting angle based on current position
            // This ensures smooth transition from current position
            let startAngle = atan2(start.y - (start.y - loopRadius), start.x - start.x)

            let centerX = start.x
            let centerY = start.y - loopRadius

            // Start from current position, make a full loop, then dive
            let steps = 24
            path.append(start) // Start exactly at current position

            for i in 1...steps {
                let angle = startAngle + (CGFloat(i) / CGFloat(steps)) * 2.0 * .pi
                let x = centerX + loopRadius * cos(angle)
                let y = centerY + loopRadius * sin(angle)
                path.append(CGPoint(x: x, y: y))
            }

            // Then dive down smoothly
            let diveSteps = 10
            for i in 1...diveSteps {
                let progress = CGFloat(i) / CGFloat(diveSteps)
                let y = centerY + loopRadius - (centerY + loopRadius + 20) * progress
                path.append(CGPoint(x: centerX, y: y))
            }

        case .swoop:
            // Swooping S-curve attack - smooth bezier curve
            let steps = 30
            let side = Bool.random() ? -1.0 : 1.0  // Random side

            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                // Parametric S-curve
                let x = start.x + CGFloat(side) * 150 * sin(t * .pi)
                let y = start.y - (start.y + 20) * t
                path.append(CGPoint(x: x, y: y))
            }

        case .spiral:
            // Spiral attack - decreasing radius spiral down
            let steps = 40
            let initialRadius: CGFloat = 100

            for i in 0...steps {
                let progress = CGFloat(i) / CGFloat(steps)
                let angle = progress * .pi * 4 // 2 full rotations
                let radius = initialRadius * (1.0 - progress * 0.7) // Decrease radius
                let x = start.x + cos(angle) * radius
                let y = start.y - (start.y + 20) * progress
                path.append(CGPoint(x: x, y: y))
            }

        case .wave:
            // Wave attack - multiple waves down
            let steps = 35
            let amplitude: CGFloat = 80
            let frequency: CGFloat = 3

            for i in 0...steps {
                let progress = CGFloat(i) / CGFloat(steps)
                let x = start.x + sin(progress * .pi * frequency) * amplitude
                let y = start.y - (start.y + 20) * progress
                path.append(CGPoint(x: x, y: y))
            }
        }

        return path
    }
}

class FormationManager {

    private weak var scene: SKScene?
    private var formations: [Formation] = []
    private var lastUpdateTime: TimeInterval = 0

    init(scene: SKScene) {
        self.scene = scene
    }

    // Spawn a new formation
    func spawnFormation(pattern: FormationPattern, count: Int, attackDelay: TimeInterval, onEnemyComplete: @escaping () -> Void) {
        guard let scene = scene else { return }

        let centerX = scene.size.width / 2
        let startY = scene.size.height - 150  // Lower position - visible on screen
        let spacing: CGFloat = 50

        let positions = pattern.positions(count: count, centerX: centerX, startY: startY, spacing: spacing)

        var enemies: [Enemy] = []

        for (index, _) in positions.enumerated() {
            let enemy = Enemy(sceneSize: scene.size, scene: scene, type: .formation)

            // Spawn from top with curved entry path
            let spawnX = centerX + CGFloat.random(in: -150...150)
            enemy.position = CGPoint(x: spawnX, y: scene.size.height + 50)

            // Get GameScene to access gameContentNode
            let parentNode: SKNode
            if let gameScene = scene as? GameScene {
                parentNode = gameScene.gameContentNode
            } else {
                parentNode = scene
            }

            parentNode.addChild(enemy)
            enemies.append(enemy)

            // Move to formation position with staggered delay and curved path
            let delay = TimeInterval(index) * 0.2
            let moveAction = SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak enemy] in
                    guard let enemy = enemy else { return }

                    // Create smooth curved entry path using bezier
                    let currentPos = enemy.position
                    let targetPos = positions[index]

                    // Create control points for smooth curve
                    let controlX = (currentPos.x + targetPos.x) / 2
                    let controlY = currentPos.y - 100 // Curve downward

                    // Build path with multiple intermediate points for smooth animation
                    var pathPoints: [CGPoint] = []
                    let steps = 15
                    for i in 0...steps {
                        let t = CGFloat(i) / CGFloat(steps)
                        // Quadratic bezier curve formula
                        let x = pow(1-t, 2) * currentPos.x + 2*(1-t)*t*controlX + pow(t, 2)*targetPos.x
                        let y = pow(1-t, 2) * currentPos.y + 2*(1-t)*t*controlY + pow(t, 2)*targetPos.y
                        pathPoints.append(CGPoint(x: x, y: y))
                    }

                    // Create smooth path
                    let path = CGMutablePath()
                    path.move(to: pathPoints[0])
                    for i in 1..<pathPoints.count {
                        path.addLine(to: pathPoints[i])
                    }

                    let followPath = SKAction.follow(path, asOffset: false, orientToPath: false, duration: 1.5)
                    enemy.run(followPath) {
                        enemy.isInFormation = true
                    }
                }
            ])
            enemy.run(moveAction)
        }

        let formation = Formation(
            enemies: enemies,
            positions: positions,
            attackDelay: attackDelay,
            scene: scene,
            onEnemyComplete: onEnemyComplete
        )

        formations.append(formation)
    }

    func update(currentTime: TimeInterval) {
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }

        // Update all formations
        for formation in formations {
            formation.update(currentTime: currentTime)
        }

        // Remove destroyed formations
        formations.removeAll { $0.isDestroyed }

        lastUpdateTime = currentTime
    }
}

// Individual formation group
class Formation {

    private var enemies: [Enemy]
    private var positions: [CGPoint]
    private var attackDelay: TimeInterval
    private weak var scene: SKScene?
    private var formationStartTime: TimeInterval?
    private var hasAttacked: Bool = false
    private var onEnemyComplete: (() -> Void)?

    var isDestroyed: Bool {
        return enemies.allSatisfy { $0.parent == nil }
    }

    init(enemies: [Enemy], positions: [CGPoint], attackDelay: TimeInterval, scene: SKScene, onEnemyComplete: @escaping () -> Void) {
        self.enemies = enemies
        self.positions = positions
        self.attackDelay = attackDelay
        self.scene = scene
        self.onEnemyComplete = onEnemyComplete
    }

    func update(currentTime: TimeInterval) {
        guard scene != nil else { return }

        // Check if all enemies are in formation
        let allInFormation = enemies.allSatisfy { $0.isInFormation || $0.parent == nil }

        if allInFormation && !hasAttacked {
            if formationStartTime == nil {
                formationStartTime = currentTime
            }

            // Start attack after delay
            if currentTime - formationStartTime! >= attackDelay {
                initiateAttack()
                hasAttacked = true
            }
        }
    }

    private func initiateAttack() {
        guard scene != nil else { return }

        // All enemies will eventually attack - some sooner, some later
        let allActiveEnemies = enemies.filter { $0.parent != nil }
        guard let firstEnemy = allActiveEnemies.first else { return }

        let enemyType = firstEnemy.enemyType

        // Special behavior for different formation types
        switch enemyType {
        case .eliteGuard:
            // Elite Guard: All attack simultaneously
            initiateEliteGuardAttack(enemies: allActiveEnemies)

        case .spinner:
            // Spinner: Rotate formation first, then spiral attack
            initiateSpinnerAttack(enemies: allActiveEnemies)

        case .commander:
            // Commander: Wave attacks in groups
            initiateCommanderAttack(enemies: allActiveEnemies)

        case .scout:
            // Scout: Quick successive dives
            initiateScoutAttack(enemies: allActiveEnemies)

        case .bomber:
            // Bomber: Slow, heavy attacks
            initiateBomberAttack(enemies: allActiveEnemies)

        default:
            // Default staggered attack for .formation type
            initiateStaggeredAttack(enemies: allActiveEnemies)
        }
    }

    private func initiateStaggeredAttack(enemies: [Enemy]) {
        for (index, enemy) in enemies.enumerated() {
            let delay = TimeInterval(index) * 0.6  // Stagger all attacks
            let attackPattern: AttackPattern = [.dive, .loop, .swoop].randomElement()!

            let waitAction = SKAction.wait(forDuration: delay)
            let attackAction = SKAction.run { [weak self, weak enemy] in
                guard let self = self, let enemy = enemy, let scene = enemy.gameScene else { return }

                let currentPosition = enemy.position
                let path = attackPattern.createPath(from: currentPosition, sceneSize: scene.size)
                enemy.attackFromFormation(path: path, duration: 3.0) { [weak self] in
                    self?.onEnemyComplete?()
                }
            }

            enemy.run(SKAction.sequence([waitAction, attackAction]))
        }
    }

    private func initiateEliteGuardAttack(enemies: [Enemy]) {
        // All attack at the same time with coordinated patterns
        for enemy in enemies {
            let attackPattern: AttackPattern = [.dive, .loop].randomElement()! // More coordinated patterns

            let waitAction = SKAction.wait(forDuration: 0.2) // Minimal delay for all
            let attackAction = SKAction.run { [weak self, weak enemy] in
                guard let self = self, let enemy = enemy, let scene = enemy.gameScene else { return }

                let currentPosition = enemy.position
                let path = attackPattern.createPath(from: currentPosition, sceneSize: scene.size)
                enemy.attackFromFormation(path: path, duration: 2.5) { [weak self] in
                    self?.onEnemyComplete?()
                }
            }

            enemy.run(SKAction.sequence([waitAction, attackAction]))
        }
    }

    private func initiateSpinnerAttack(enemies: [Enemy]) {
        // First rotate the entire formation
        let centerX = positions.reduce(0) { $0 + $1.x } / CGFloat(positions.count)
        let centerY = positions.reduce(0) { $0 + $1.y } / CGFloat(positions.count)

        // Rotate formation
        for enemy in enemies {
            let currentPos = enemy.position
            let radius = sqrt(pow(currentPos.x - centerX, 2) + pow(currentPos.y - centerY, 2))
            let startAngle = atan2(currentPos.y - centerY, currentPos.x - centerX)

            var rotationPath: [CGPoint] = []
            let rotationSteps = 20

            for i in 0...rotationSteps {
                let progress = CGFloat(i) / CGFloat(rotationSteps)
                let angle = startAngle + progress * .pi * 2 // Full rotation
                let x = centerX + cos(angle) * radius
                let y = centerY + sin(angle) * radius
                rotationPath.append(CGPoint(x: x, y: y))
            }

            // Create rotation action
            let rotatePath = CGMutablePath()
            rotatePath.move(to: rotationPath[0])
            for i in 1..<rotationPath.count {
                rotatePath.addLine(to: rotationPath[i])
            }

            let rotateAction = SKAction.follow(rotatePath, asOffset: false, orientToPath: false, duration: 2.0)
            let attackAction = SKAction.run { [weak self, weak enemy] in
                guard let self = self, let enemy = enemy, let scene = enemy.gameScene else { return }

                let currentPosition = enemy.position
                let path = AttackPattern.spiral.createPath(from: currentPosition, sceneSize: scene.size)
                enemy.attackFromFormation(path: path, duration: 3.5) { [weak self] in
                    self?.onEnemyComplete?()
                }
            }

            enemy.run(SKAction.sequence([rotateAction, attackAction]))
        }
    }

    private func initiateCommanderAttack(enemies: [Enemy]) {
        // Wave attacks - enemies attack in groups
        let groupSize = max(1, enemies.count / 2)

        for (index, enemy) in enemies.enumerated() {
            let group = index / groupSize
            let delay = TimeInterval(group) * 1.0  // Groups attack together

            let waitAction = SKAction.wait(forDuration: delay)
            let attackAction = SKAction.run { [weak self, weak enemy] in
                guard let self = self, let enemy = enemy, let scene = enemy.gameScene else { return }

                let currentPosition = enemy.position
                let path = AttackPattern.wave.createPath(from: currentPosition, sceneSize: scene.size)
                enemy.attackFromFormation(path: path, duration: 3.2) { [weak self] in
                    self?.onEnemyComplete?()
                }
            }

            enemy.run(SKAction.sequence([waitAction, attackAction]))
        }
    }

    private func initiateScoutAttack(enemies: [Enemy]) {
        // Quick successive attacks
        for (index, enemy) in enemies.enumerated() {
            let delay = TimeInterval(index) * 0.3  // Fast succession

            let waitAction = SKAction.wait(forDuration: delay)
            let attackAction = SKAction.run { [weak self, weak enemy] in
                guard let self = self, let enemy = enemy, let scene = enemy.gameScene else { return }

                let currentPosition = enemy.position
                let path = AttackPattern.dive.createPath(from: currentPosition, sceneSize: scene.size)
                enemy.attackFromFormation(path: path, duration: 2.0) { [weak self] in
                    self?.onEnemyComplete?()
                }
            }

            enemy.run(SKAction.sequence([waitAction, attackAction]))
        }
    }

    private func initiateBomberAttack(enemies: [Enemy]) {
        // Slow, deliberate attacks
        for (index, enemy) in enemies.enumerated() {
            let delay = TimeInterval(index) * 0.8  // Slower succession
            let attackPattern: AttackPattern = [.dive, .swoop].randomElement()!

            let waitAction = SKAction.wait(forDuration: delay)
            let attackAction = SKAction.run { [weak self, weak enemy] in
                guard let self = self, let enemy = enemy, let scene = enemy.gameScene else { return }

                let currentPosition = enemy.position
                let path = attackPattern.createPath(from: currentPosition, sceneSize: scene.size)
                enemy.attackFromFormation(path: path, duration: 4.0) { [weak self] in  // Slower
                    self?.onEnemyComplete?()
                }
            }

            enemy.run(SKAction.sequence([waitAction, attackAction]))
        }
    }
}
