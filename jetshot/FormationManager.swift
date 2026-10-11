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
            if count == 3 {
                // Simple diamond with 3
                positions.append(CGPoint(x: centerX, y: startY)) // Top
                positions.append(CGPoint(x: centerX - spacing, y: startY - spacing)) // Left
                positions.append(CGPoint(x: centerX + spacing, y: startY - spacing)) // Right
            } else {
                positions = Self.diamondPositions(count: count, centerX: centerX, startY: startY, spacing: spacing)
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
            positions = Self.crossPositions(count: count, centerX: centerX, startY: startY, spacing: spacing)
        }

        return positions
    }

    /// A diamond for any count: rings of lattice points one, two, three steps out from a
    /// centre, filled from the inside out. The centre is used only for an odd count, so
    /// what is left for the outermost ring is always even and goes in mirrored pairs —
    /// its widest points first, then its top and bottom tips, then along its edges — and
    /// the silhouette stays a diamond, symmetric about the vertical. The top slot sits at
    /// `startY`, as the old layout's did.
    ///
    /// The old layout grew one layer per four enemies but put only two slots in each, so
    /// it laid out roughly half the formation; the spawner places one enemy per slot, so
    /// a 14-strong diamond arrived as 7 while the level still waited on the full count.
    private static func diamondPositions(count: Int, centerX: CGFloat, startY: CGFloat, spacing: CGFloat) -> [CGPoint] {
        guard count > 0 else { return [] }

        var cells: [(dx: Int, dy: Int)] = count % 2 == 1 ? [(0, 0)] : []
        var ring = 1
        while cells.count < count {
            var pairs: [[(dx: Int, dy: Int)]] = [[(ring, 0), (-ring, 0)], [(0, ring), (0, -ring)]]
            for step in 1..<ring {
                pairs.append([(ring - step, step), (step - ring, step)])
                pairs.append([(ring - step, -step), (step - ring, -step)])
            }
            for pair in pairs where cells.count < count {
                cells.append(contentsOf: pair)
            }
            ring += 1
        }

        let rowStep = spacing * 0.8
        let top = cells.map(\.dy).max() ?? 0
        return cells.map {
            CGPoint(x: centerX + CGFloat($0.dx) * spacing, y: startY - CGFloat(top - $0.dy) * rowStep)
        }
    }

    /// A centre and four arms that share the rest round-robin — up, down, left, right,
    /// the order the small cross always filled in — so every count gets exactly its
    /// slots. Up to five this is the old small cross unchanged.
    ///
    /// The old extended cross gave every arm `(count - 1) / 4` slots and dropped the
    /// remainder: an 8-strong cross laid out 5. It also kept the centre at `startY`, so a
    /// long up arm ran off the top of the screen; the centre now drops to keep the top
    /// of that arm one row above `startY`, and vertical arms past three slots close up
    /// rather than reach down into the player's space. The horizontal arms are left to
    /// `fitHorizontally`.
    private static func crossPositions(count: Int, centerX: CGFloat, startY: CGFloat, spacing: CGFloat) -> [CGPoint] {
        guard count > 0 else { return [] }

        var arms = [0, 0, 0, 0] // up, down, left, right
        for index in 0..<(count - 1) {
            arms[index % 4] += 1
        }

        let longestVertical = max(arms[0], arms[1])
        let rowStep = longestVertical > 3 ? spacing * 3 / CGFloat(longestVertical) : spacing
        let centreY = startY - max(0, CGFloat(arms[0]) * rowStep - spacing)

        var positions = [CGPoint(x: centerX, y: centreY)]
        let directions: [(dx: CGFloat, dy: CGFloat)] = [(0, 1), (0, -1), (-1, 0), (1, 0)]
        for (arm, length) in arms.enumerated() where length > 0 {
            let direction = directions[arm]
            let step = direction.dy == 0 ? spacing : rowStep
            for slot in 1...length {
                positions.append(CGPoint(
                    x: centerX + direction.dx * CGFloat(slot) * step,
                    y: centreY + direction.dy * CGFloat(slot) * step
                ))
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

    init(scene: SKScene) {
        self.scene = scene
    }

    /// Squeezes a formation's horizontal spread so every slot stays on screen.
    ///
    /// The patterns lay out from a centre with a fixed 50pt spacing, which the larger
    /// waves outgrow badly — a 26-slot line spans 1250pt against a ~390pt phone, so
    /// most of it sat outside the playfield. Every attack path runs straight down from
    /// the slot it starts in, so those enemies dived past off-screen: unshootable, their
    /// points unearnable, and the wave effectively far smaller than configured. Scaling
    /// about the screen centre keeps each pattern's shape and ordering; the cost is that
    /// the biggest waves now overlap, which beats being invisible.
    private func fitHorizontally(_ positions: [CGPoint], sceneWidth: CGFloat) -> [CGPoint] {
        let margin: CGFloat = 30
        guard let minX = positions.map(\.x).min(),
              let maxX = positions.map(\.x).max() else { return positions }

        let extent = maxX - minX
        let available = sceneWidth - margin * 2
        guard extent > available, extent > 0, available > 0 else { return positions }

        let scale = available / extent
        let centre = sceneWidth / 2
        return positions.map { CGPoint(x: centre + ($0.x - centre) * scale, y: $0.y) }
    }

    /// Spawns a formation made up of `types`, one enemy per entry.
    ///
    /// The type list matters: this used to take only a `count` and hardcode
    /// `type: .formation`, silently discarding the enemy types the level configuration
    /// asked for. 70 of the 79 formation waves in LevelManager specify something else
    /// (.bomber, .eliteGuard, .commander, .spinner, .scout), so late-game formations
    /// were spawning the same basic enemy as the early ones and paying out its 25
    /// points instead of the intended value.
    @discardableResult
    func spawnFormation(pattern: FormationPattern, types: [EnemyType], attackDelay: TimeInterval, onEnemyComplete: @escaping () -> Void) -> Formation? {
        guard let scene = scene, !types.isEmpty else { return nil }

        let centerX = scene.size.width / 2
        let startY = scene.size.height - 150  // Lower position - visible on screen
        let spacing: CGFloat = 50

        let positions = fitHorizontally(
            pattern.positions(count: types.count, centerX: centerX, startY: startY, spacing: spacing),
            sceneWidth: scene.size.width
        )

        var enemies: [Enemy] = []

        for (index, _) in positions.enumerated() {
            // Every pattern lays out exactly `types.count` slots (`FormationLayoutTests`
            // pins that: the spawner places one enemy per slot, so a short layout used to
            // drop enemies), but index defensively rather than trusting the counts match.
            let type = index < types.count ? types[index] : types[types.count - 1]
            let enemy = Enemy(sceneSize: scene.size, scene: scene, type: type)

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

            // Register enemy in cache for optimized updates
            if let gameScene = scene as? GameScene {
                gameScene.registerEnemy(enemy)
            }

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
        return formation
    }

    func update(currentTime: TimeInterval) {
        // Update all formations
        for formation in formations {
            formation.update(currentTime: currentTime)
        }

        // Remove destroyed formations
        formations.removeAll { $0.isDestroyed }
    }
}

// Individual formation group
class Formation {

    private var enemies: [Enemy]
    private var positions: [CGPoint]
    private var attackDelay: TimeInterval
    private weak var scene: SKScene?
    private var formationStartTime: TimeInterval?
    /// Set once every member has taken its slot and the attack has begun.
    private(set) var hasAttacked: Bool = false
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
            guard let startTime = formationStartTime else { return }
            if currentTime - startTime >= attackDelay {
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
            let attackPattern: AttackPattern = [.dive, .loop, .swoop].randomElement() ?? .dive

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
            let attackPattern: AttackPattern = [.dive, .loop].randomElement() ?? .dive // More coordinated patterns

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
            let attackPattern: AttackPattern = [.dive, .swoop].randomElement() ?? .dive

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
