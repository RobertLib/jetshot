//
//  VectorFX3D.swift
//  jetshot
//
//  Pseudo-3D vector effects for shields, scanning, and visual enhancements
//

import SpriteKit

/// Generates pseudo-3D vector effects using wireframe projections
class VectorFX3D {

    // MARK: - Shield Sphere Effect

    /// Creates an expanding sphere shield made of dots/particles
    /// - Parameters:
    ///   - radius: Base radius of the shield
    ///   - color: Color of the shield particles
    ///   - persistent: If true, shield stays; if false, it expands and fades
    /// - Returns: SKNode containing the shield effect
    static func createShieldSphere(radius: CGFloat, color: UIColor, persistent: Bool = true) -> SKNode {
        let container = SKNode()
        container.name = "vectorShield"

        // Create multiple latitude circles to simulate 3D sphere
        let latitudes = 6
        let pointsPerCircle = 20

        for i in 0...latitudes {
            let lat = CGFloat(i) / CGFloat(latitudes) * .pi
            let y = cos(lat) * radius
            let circleRadius = sin(lat) * radius

            // Create circle of points at this latitude
            for j in 0..<pointsPerCircle {
                let angle = CGFloat(j) / CGFloat(pointsPerCircle) * 2 * .pi
                let x = cos(angle) * circleRadius
                let z = sin(angle) * circleRadius

                // Project 3D to 2D (simple orthographic projection)
                let point = SKShapeNode(circleOfRadius: 1.5)
                point.fillColor = color
                point.strokeColor = .clear
                point.position = CGPoint(x: x, y: y - z * 0.3) // Slight z-depth effect
                point.alpha = 0.6

                // Pulsing animation
                if persistent {
                    let pulse = SKAction.sequence([
                        SKAction.fadeAlpha(to: 0.3, duration: 0.8),
                        SKAction.fadeAlpha(to: 0.8, duration: 0.8)
                    ])
                    point.run(SKAction.repeatForever(pulse))

                    // Slight rotation for depth
                    let rotate = SKAction.rotate(byAngle: .pi * 2, duration: 4.0)
                    container.run(SKAction.repeatForever(rotate))
                }

                container.addChild(point)
            }
        }

        if !persistent {
            // Expanding and fading animation
            let expand = SKAction.scale(to: 2.5, duration: 0.5)
            let fade = SKAction.fadeOut(withDuration: 0.5)
            let group = SKAction.group([expand, fade])
            let remove = SKAction.removeFromParent()
            container.run(SKAction.sequence([group, remove]))
        }

        return container
    }

    // MARK: - Scanning Cone Effect

    /// Creates a 3D scanning cone effect (for enemies detecting player)
    /// - Parameters:
    ///   - length: Length of the cone
    ///   - angle: Opening angle of the cone
    ///   - color: Color of the scan lines
    ///   - direction: Direction vector (normalized)
    /// - Returns: SKNode containing the scanning cone
    static func createScanCone(length: CGFloat, angle: CGFloat, color: UIColor, direction: CGPoint = CGPoint(x: 0, y: -1)) -> SKNode {
        let container = SKNode()
        container.name = "scanCone"

        // Rotate container to match direction
        let targetAngle = atan2(direction.y, direction.x) - .pi / 2
        container.zRotation = targetAngle

        let rings = 8
        let linesPerRing = 12

        for i in 1...rings {
            let ringDistance = CGFloat(i) / CGFloat(rings) * length
            let ringRadius = tan(angle / 2) * ringDistance

            // Create wireframe ring
            for j in 0..<linesPerRing {
                let theta = CGFloat(j) / CGFloat(linesPerRing) * 2 * .pi
                let x1 = cos(theta) * ringRadius
                let z1 = sin(theta) * ringRadius
                let y1 = -ringDistance

                let theta2 = CGFloat(j + 1) / CGFloat(linesPerRing) * 2 * .pi
                let x2 = cos(theta2) * ringRadius
                let z2 = sin(theta2) * ringRadius

                // Project to 2D
                let point1 = CGPoint(x: x1, y: y1 + z1 * 0.3)
                let point2 = CGPoint(x: x2, y: y1 + z2 * 0.3)

                let line = createLine(from: point1, to: point2, color: color, width: 1.0)
                line.alpha = 0.4 + CGFloat(i) / CGFloat(rings) * 0.4
                container.addChild(line)
            }
        }

        // Animated scanning wave
        let wave = SKShapeNode(circleOfRadius: 3)
        wave.fillColor = color
        wave.strokeColor = color.withAlphaComponent(0.8)
        wave.lineWidth = 2
        wave.alpha = 0.8

        let moveDown = SKAction.moveBy(x: 0, y: -length, duration: 1.5)
        let scaleUp = SKAction.scale(to: tan(angle / 2) * length / 3, duration: 1.5)
        let fade = SKAction.fadeOut(withDuration: 1.5)
        let group = SKAction.group([moveDown, scaleUp, fade])
        let reset = SKAction.run {
            wave.position = .zero
            wave.setScale(1.0)
            wave.alpha = 0.8
        }
        wave.run(SKAction.repeatForever(SKAction.sequence([group, reset])))

        container.addChild(wave)

        // Pulse the whole cone
        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.6),
            SKAction.fadeAlpha(to: 0.7, duration: 0.6)
        ])
        container.run(SKAction.repeatForever(pulse))

        return container
    }

    // MARK: - PowerUp Burst Effect

    /// Creates an explosive 3D particle burst when collecting powerup
    /// - Parameters:
    ///   - position: Center position
    ///   - color: Primary color
    ///   - particleCount: Number of particles
    /// - Returns: SKNode that self-removes
    static func createPowerUpBurst(at position: CGPoint, color: UIColor, particleCount: Int = 40) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = "powerUpBurst"

        // Create 3D spiral explosion
        for i in 0..<particleCount {
            let particle = SKShapeNode(circleOfRadius: 2)
            particle.fillColor = color
            particle.strokeColor = color.withAlphaComponent(0.8)
            particle.glowWidth = 2

            // Calculate 3D trajectory
            let theta = CGFloat(i) / CGFloat(particleCount) * .pi * 4 // Multiple spirals
            let phi = CGFloat(i) / CGFloat(particleCount) * .pi * 2

            let distance: CGFloat = 80
            let x = cos(theta) * sin(phi) * distance
            let y = cos(phi) * distance
            let z = sin(theta) * sin(phi) * distance

            // Project to 2D
            let targetPoint = CGPoint(x: x, y: y - z * 0.4)

            // Animate
            let move = SKAction.move(to: targetPoint, duration: 0.8)
            move.timingMode = .easeOut
            let fade = SKAction.fadeOut(withDuration: 0.8)
            let scale = SKAction.scale(to: 0.5, duration: 0.8)
            let group = SKAction.group([move, fade, scale])
            let remove = SKAction.removeFromParent()

            particle.run(SKAction.sequence([group, remove]))
            container.addChild(particle)
        }

        // Add central flash
        let flash = SKShapeNode(circleOfRadius: 15)
        flash.fillColor = .white
        flash.strokeColor = color
        flash.lineWidth = 3
        flash.glowWidth = 8

        let flashAnim = SKAction.group([
            SKAction.scale(to: 3, duration: 0.4),
            SKAction.fadeOut(withDuration: 0.4)
        ])
        flash.run(SKAction.sequence([flashAnim, SKAction.removeFromParent()]))
        container.addChild(flash)

        // Container self-destructs
        container.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.0),
            SKAction.removeFromParent()
        ]))

        return container
    }

    // MARK: - Vector Aura (Enemy Special)

    /// Creates rotating vector circles/hexagons around enemy
    /// - Parameters:
    ///   - radius: Base radius
    ///   - color: Color of the aura
    ///   - style: Shape style (.circle, .hexagon, .octagon)
    /// - Returns: SKNode with animated aura
    static func createVectorAura(radius: CGFloat, color: UIColor, style: AuraStyle = .hexagon) -> SKNode {
        let container = SKNode()
        container.name = "vectorAura"

        // Create multiple rings
        let ringCount = 3

        for i in 0..<ringCount {
            let ringRadius = radius + CGFloat(i) * 12
            let ring: SKShapeNode

            switch style {
            case .circle:
                ring = SKShapeNode(circleOfRadius: ringRadius)
            case .hexagon:
                ring = createPolygon(sides: 6, radius: ringRadius)
            case .octagon:
                ring = createPolygon(sides: 8, radius: ringRadius)
            case .triangle:
                ring = createPolygon(sides: 3, radius: ringRadius)
            }

            ring.strokeColor = color
            ring.lineWidth = 1.5
            ring.fillColor = .clear
            ring.alpha = 0.6 - CGFloat(i) * 0.15
            ring.glowWidth = 1

            // Rotate each ring differently
            let rotationSpeed = 2.0 + Double(i) * 0.5
            let direction = i % 2 == 0 ? 1.0 : -1.0
            let rotate = SKAction.rotate(byAngle: .pi * 2 * CGFloat(direction), duration: rotationSpeed)
            ring.run(SKAction.repeatForever(rotate))

            // Pulse
            let pulse = SKAction.sequence([
                SKAction.fadeAlpha(to: 0.3, duration: 0.8),
                SKAction.fadeAlpha(to: 0.7, duration: 0.8)
            ])
            ring.run(SKAction.repeatForever(pulse))

            container.addChild(ring)
        }

        // Add corner points for extra detail
        if style == .hexagon || style == .octagon {
            let sides = style == .hexagon ? 6 : 8
            for i in 0..<sides {
                let angle = CGFloat(i) / CGFloat(sides) * .pi * 2
                let x = cos(angle) * radius
                let y = sin(angle) * radius

                let dot = SKShapeNode(circleOfRadius: 2)
                dot.fillColor = color
                dot.strokeColor = .clear
                dot.position = CGPoint(x: x, y: y)
                dot.glowWidth = 2

                let pulse = SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.5, duration: 0.5),
                    SKAction.fadeAlpha(to: 1.0, duration: 0.5)
                ])
                dot.run(SKAction.repeatForever(pulse))

                container.addChild(dot)
            }
        }

        return container
    }

    // MARK: - Grid Wave Effect

    /// Creates a wave grid effect (like water ripples in 3D)
    /// - Parameters:
    ///   - size: Size of the grid
    ///   - color: Color of grid lines
    ///   - position: Position of effect
    /// - Returns: Animated grid node
    static func createGridWave(size: CGFloat, color: UIColor, at position: CGPoint) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = "gridWave"

        let gridSize = 6
        let spacing = size / CGFloat(gridSize)

        // Create grid points
        var points: [[SKShapeNode]] = []
        for i in 0...gridSize {
            var row: [SKShapeNode] = []
            for j in 0...gridSize {
                let x = CGFloat(i - gridSize / 2) * spacing
                let y = CGFloat(j - gridSize / 2) * spacing

                let point = SKShapeNode(circleOfRadius: 1.5)
                point.fillColor = color
                point.strokeColor = .clear
                point.position = CGPoint(x: x, y: y)
                point.alpha = 0.5

                container.addChild(point)
                row.append(point)
            }
            points.append(row)
        }

        // Animate wave
        let waveSpeed = 0.15
        for i in 0...gridSize {
            for j in 0...gridSize {
                let point = points[i][j]
                let delay = Double(i + j) * waveSpeed

                let wave = SKAction.sequence([
                    SKAction.wait(forDuration: delay),
                    SKAction.moveBy(x: 0, y: 8, duration: 0.3),
                    SKAction.moveBy(x: 0, y: -8, duration: 0.3)
                ])

                point.run(SKAction.repeatForever(wave))
            }
        }

        // Connect points with lines
        for i in 0..<gridSize {
            for j in 0..<gridSize {
                // Horizontal line
                if i < gridSize {
                    let line = createLine(
                        from: points[i][j].position,
                        to: points[i + 1][j].position,
                        color: color,
                        width: 0.5
                    )
                    line.alpha = 0.3
                    container.addChild(line)
                }
                // Vertical line
                if j < gridSize {
                    let line = createLine(
                        from: points[i][j].position,
                        to: points[i][j + 1].position,
                        color: color,
                        width: 0.5
                    )
                    line.alpha = 0.3
                    container.addChild(line)
                }
            }
        }

        // Fade out and remove
        let fadeOut = SKAction.fadeOut(withDuration: 1.5)
        let remove = SKAction.removeFromParent()
        container.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.0),
            fadeOut,
            remove
        ]))

        return container
    }

    // MARK: - Targeting Reticle

    /// Creates a 3D targeting reticle (for sniper enemies)
    /// - Parameters:
    ///   - target: Target position
    ///   - color: Reticle color
    ///   - lockDuration: Time to lock on
    /// - Returns: Animated targeting reticle
    static func createTargetingReticle(at target: CGPoint, color: UIColor, lockDuration: TimeInterval = 1.0) -> SKNode {
        let container = SKNode()
        container.position = target
        container.name = "targetingReticle"

        // Outer ring
        let outerRing = SKShapeNode(circleOfRadius: 20)
        outerRing.strokeColor = color
        outerRing.lineWidth = 1.5
        outerRing.fillColor = .clear
        container.addChild(outerRing)

        // Inner ring
        let innerRing = SKShapeNode(circleOfRadius: 12)
        innerRing.strokeColor = color
        innerRing.lineWidth = 1.0
        innerRing.fillColor = .clear
        container.addChild(innerRing)

        // Crosshairs
        let crosshairLength: CGFloat = 25
        for angle in [0, CGFloat.pi / 2, CGFloat.pi, CGFloat.pi * 1.5] {
            let x1 = cos(angle) * 8
            let y1 = sin(angle) * 8
            let x2 = cos(angle) * crosshairLength
            let y2 = sin(angle) * crosshairLength

            let line = createLine(
                from: CGPoint(x: x1, y: y1),
                to: CGPoint(x: x2, y: y2),
                color: color,
                width: 1.5
            )
            container.addChild(line)
        }

        // Center dot
        let center = SKShapeNode(circleOfRadius: 2)
        center.fillColor = color
        center.strokeColor = .clear
        center.glowWidth = 2
        container.addChild(center)

        // Lock-on animation
        let spin = SKAction.rotate(byAngle: .pi * 2, duration: 0.5)
        outerRing.run(SKAction.repeatForever(spin))

        let spinInner = SKAction.rotate(byAngle: -.pi * 2, duration: 0.7)
        innerRing.run(SKAction.repeatForever(spinInner))

        // Converge animation (getting lock)
        let converge = SKAction.scale(to: 0.7, duration: lockDuration)
        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.15),
            SKAction.fadeAlpha(to: 1.0, duration: 0.15)
        ])
        let pulsing = SKAction.repeat(pulse, count: Int(lockDuration / 0.3))

        container.run(SKAction.group([converge, pulsing]))

        // Flash when locked
        container.run(SKAction.sequence([
            SKAction.wait(forDuration: lockDuration),
            SKAction.run {
                let flash = SKShapeNode(circleOfRadius: 30)
                flash.strokeColor = .red
                flash.lineWidth = 3
                flash.fillColor = .clear
                flash.glowWidth = 5
                container.addChild(flash)

                flash.run(SKAction.sequence([
                    SKAction.group([
                        SKAction.scale(to: 0.5, duration: 0.2),
                        SKAction.fadeOut(withDuration: 0.2)
                    ]),
                    SKAction.removeFromParent()
                ]))
            }
        ]))

        return container
    }

    // MARK: - Helper Functions

    private static func createLine(from: CGPoint, to: CGPoint, color: UIColor, width: CGFloat) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: from)
        path.addLine(to: to)

        let line = SKShapeNode(path: path)
        line.strokeColor = color
        line.lineWidth = width
        return line
    }

    private static func createPolygon(sides: Int, radius: CGFloat) -> SKShapeNode {
        let path = CGMutablePath()

        for i in 0...sides {
            let angle = CGFloat(i) / CGFloat(sides) * .pi * 2 - .pi / 2
            let x = cos(angle) * radius
            let y = sin(angle) * radius
            let point = CGPoint(x: x, y: y)

            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return SKShapeNode(path: path)
    }

    enum AuraStyle {
        case circle
        case hexagon
        case octagon
        case triangle
    }

    // MARK: - Energy Core Effect

    /// Creates a pulsing 3D energy core (for bosses and powerful enemies)
    /// - Parameters:
    ///   - radius: Size of the core
    ///   - color: Primary color
    ///   - layers: Number of concentric layers
    /// - Returns: Animated energy core node
    static func createEnergyCore(radius: CGFloat, color: UIColor, layers: Int = 3) -> SKNode {
        let container = SKNode()
        container.name = "energyCore"

        // Create multiple concentric rotating spheres
        for layer in 0..<layers {
            let layerRadius = radius * (1.0 - CGFloat(layer) * 0.25)
            let sphere = createWireframeSphere(radius: layerRadius, color: color, segments: 8)
            sphere.alpha = 0.7 - CGFloat(layer) * 0.2

            // Each layer rotates differently
            let rotationDuration = 2.0 + Double(layer) * 0.5
            let direction = layer % 2 == 0 ? 1.0 : -1.0
            let rotate = SKAction.rotate(byAngle: .pi * 2 * CGFloat(direction), duration: rotationDuration)
            sphere.run(SKAction.repeatForever(rotate))

            container.addChild(sphere)
        }

        // Central bright point
        let core = SKShapeNode(circleOfRadius: 4)
        core.fillColor = .white
        core.strokeColor = color
        core.lineWidth = 2
        core.glowWidth = 6

        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.5, duration: 0.6),
            SKAction.scale(to: 1.0, duration: 0.6)
        ])
        core.run(SKAction.repeatForever(pulse))
        container.addChild(core)

        return container
    }

    // MARK: - Wireframe Sphere

    private static func createWireframeSphere(radius: CGFloat, color: UIColor, segments: Int) -> SKNode {
        let container = SKNode()

        // Horizontal circles (latitudes)
        for i in 0...segments {
            let lat = CGFloat(i) / CGFloat(segments) * .pi
            let y = cos(lat) * radius
            let circleRadius = sin(lat) * radius

            let circle = SKShapeNode(circleOfRadius: circleRadius)
            circle.strokeColor = color
            circle.lineWidth = 1
            circle.fillColor = .clear
            circle.position = CGPoint(x: 0, y: y)
            circle.alpha = 0.5
            container.addChild(circle)
        }

        // Vertical circles (longitudes)
        for i in 0..<4 {
            let angle = CGFloat(i) * .pi / 2
            let ellipse = createRotatedCircle(radius: radius, angle: angle, color: color)
            container.addChild(ellipse)
        }

        return container
    }

    private static func createRotatedCircle(radius: CGFloat, angle: CGFloat, color: UIColor) -> SKShapeNode {
        let path = CGMutablePath()
        let segments = 30

        for i in 0...segments {
            let t = CGFloat(i) / CGFloat(segments) * 2 * .pi
            let x = cos(t) * radius * cos(angle)
            let y = sin(t) * radius
            let z = cos(t) * radius * sin(angle)

            let point = CGPoint(x: x, y: y - z * 0.3)

            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        let circle = SKShapeNode(path: path)
        circle.strokeColor = color
        circle.lineWidth = 1
        circle.fillColor = .clear
        circle.alpha = 0.5
        return circle
    }

    // MARK: - Rotating Cannon Barrels

    /// Creates rotating 3D cannon barrels visualization
    /// - Parameters:
    ///   - count: Number of barrels
    ///   - radius: Distance from center
    ///   - color: Barrel color
    /// - Returns: Animated cannon array
    static func createRotatingCannons(count: Int, radius: CGFloat, color: UIColor) -> SKNode {
        let container = SKNode()
        container.name = "rotatingCannons"

        for i in 0..<count {
            let angle = CGFloat(i) / CGFloat(count) * .pi * 2
            let x = cos(angle) * radius
            let y = sin(angle) * radius

            let barrel = SKShapeNode(rectOf: CGSize(width: 4, height: 15), cornerRadius: 2)
            barrel.fillColor = color
            barrel.strokeColor = color.withAlphaComponent(0.6)
            barrel.lineWidth = 1
            barrel.position = CGPoint(x: x, y: y)
            barrel.zRotation = angle + .pi / 2

            // Muzzle flash indicator
            let muzzle = SKShapeNode(circleOfRadius: 2)
            muzzle.fillColor = .white.withAlphaComponent(0.8)
            muzzle.strokeColor = .clear
            muzzle.position = CGPoint(x: 0, y: 7.5)
            barrel.addChild(muzzle)

            container.addChild(barrel)
        }

        // Rotate entire cannon array
        let rotate = SKAction.rotate(byAngle: .pi * 2, duration: 4.0)
        container.run(SKAction.repeatForever(rotate))

        return container
    }

    // MARK: - Force Field Effect

    /// Creates a force field with animated lines
    /// - Parameters:
    ///   - radius: Field radius
    ///   - color: Field color
    /// - Returns: Animated force field
    static func createForceField(radius: CGFloat, color: UIColor) -> SKNode {
        let container = SKNode()
        container.name = "forceField"

        // Create radial lines
        let lineCount = 16
        for i in 0..<lineCount {
            let angle = CGFloat(i) / CGFloat(lineCount) * .pi * 2
            let endX = cos(angle) * radius
            let endY = sin(angle) * radius

            let line = createLine(
                from: .zero,
                to: CGPoint(x: endX, y: endY),
                color: color,
                width: 1.5
            )
            line.alpha = 0.4
            container.addChild(line)
        }

        // Outer ring
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.strokeColor = color
        ring.lineWidth = 2
        ring.fillColor = .clear
        ring.glowWidth = 2
        container.addChild(ring)

        // Pulse animation
        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.8),
            SKAction.fadeAlpha(to: 0.7, duration: 0.8)
        ])
        container.run(SKAction.repeatForever(pulse))

        // Rotation
        let rotate = SKAction.rotate(byAngle: .pi * 2, duration: 6.0)
        container.run(SKAction.repeatForever(rotate))

        return container
    }

    // MARK: - Charge Up Effect

    /// Creates charging energy effect (for attacks)
    /// - Parameters:
    ///   - position: Center position
    ///   - color: Energy color
    ///   - duration: Charge duration
    /// - Returns: Self-removing charge effect
    static func createChargeEffect(at position: CGPoint, color: UIColor, duration: TimeInterval = 1.0) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = "chargeEffect"

        // Create converging particles
        let particleCount = 20
        for i in 0..<particleCount {
            let angle = CGFloat(i) / CGFloat(particleCount) * .pi * 2
            let distance: CGFloat = 60
            let startX = cos(angle) * distance
            let startY = sin(angle) * distance

            let particle = SKShapeNode(circleOfRadius: 2)
            particle.fillColor = color
            particle.strokeColor = .white
            particle.lineWidth = 1
            particle.position = CGPoint(x: startX, y: startY)
            particle.glowWidth = 2

            // Move toward center
            let move = SKAction.move(to: .zero, duration: duration)
            move.timingMode = .easeIn
            let fade = SKAction.fadeOut(withDuration: duration)
            let group = SKAction.group([move, fade])
            particle.run(SKAction.sequence([group, SKAction.removeFromParent()]))

            container.addChild(particle)
        }

        // Central glow
        let glow = SKShapeNode(circleOfRadius: 5)
        glow.fillColor = color
        glow.strokeColor = .white
        glow.lineWidth = 2
        glow.glowWidth = 8
        glow.alpha = 0

        let appear = SKAction.fadeIn(withDuration: duration)
        let scale = SKAction.scale(to: 2.0, duration: duration)
        glow.run(SKAction.group([appear, scale]))
        container.addChild(glow)

        // Self-destruct
        container.run(SKAction.sequence([
            SKAction.wait(forDuration: duration + 0.5),
            SKAction.removeFromParent()
        ]))

        return container
    }

    // MARK: - Radar Sweep

    /// Creates a radar sweep effect (for detection)
    /// - Parameters:
    ///   - radius: Sweep radius
    ///   - color: Sweep color
    /// - Returns: Animated radar sweep
    static func createRadarSweep(radius: CGFloat, color: UIColor) -> SKNode {
        let container = SKNode()
        container.name = "radarSweep"

        // Radar circle
        let circle = SKShapeNode(circleOfRadius: radius)
        circle.strokeColor = color
        circle.lineWidth = 2
        circle.fillColor = .clear
        circle.alpha = 0.5
        container.addChild(circle)

        // Sweep line
        let sweepLine = createLine(
            from: .zero,
            to: CGPoint(x: 0, y: radius),
            color: color.withAlphaComponent(0.9),
            width: 3
        )
        sweepLine.glowWidth = 2
        container.addChild(sweepLine)

        // Sweep animation
        let rotate = SKAction.rotate(byAngle: .pi * 2, duration: 2.0)
        sweepLine.run(SKAction.repeatForever(rotate))

        // Pulse rings
        for i in 1...3 {
            let ring = SKShapeNode(circleOfRadius: radius * 0.3 * CGFloat(i))
            ring.strokeColor = color
            ring.lineWidth = 1
            ring.fillColor = .clear
            ring.alpha = 0.3
            container.addChild(ring)

            let pulse = SKAction.sequence([
                SKAction.wait(forDuration: Double(i) * 0.3),
                SKAction.scale(to: 1.2, duration: 0.5),
                SKAction.fadeOut(withDuration: 0.5),
                SKAction.run {
                    ring.setScale(1.0)
                    ring.alpha = 0.3
                }
            ])
            ring.run(SKAction.repeatForever(pulse))
        }

        return container
    }

    // MARK: - Energy Beam Charger

    /// Creates charging beam effect (before laser fires)
    /// - Parameters:
    ///   - length: Beam length
    ///   - color: Beam color
    /// - Returns: Charging beam effect
    static func createBeamCharger(length: CGFloat, color: UIColor) -> SKNode {
        let container = SKNode()
        container.name = "beamCharger"

        // Multiple converging lines
        for i in 0..<8 {
            let offset = CGFloat(i - 4) * 3
            let line = createLine(
                from: CGPoint(x: offset, y: 0),
                to: CGPoint(x: 0, y: -length),
                color: color,
                width: 2
            )
            line.alpha = 0.6
            container.addChild(line)

            // Animated particles moving down the line
            let particle = SKShapeNode(circleOfRadius: 1.5)
            particle.fillColor = .white
            particle.strokeColor = .clear
            particle.position = CGPoint(x: offset, y: 0)
            particle.glowWidth = 2

            let move = SKAction.moveTo(y: -length, duration: 0.5)
            let fade = SKAction.fadeOut(withDuration: 0.5)
            let reset = SKAction.run {
                particle.position.y = 0
                particle.alpha = 1.0
            }
            let sequence = SKAction.sequence([
                SKAction.group([move, fade]),
                reset
            ])
            particle.run(SKAction.repeatForever(sequence))
            container.addChild(particle)
        }

        return container
    }

    // MARK: - Orbital Defense

    /// Creates orbiting defense nodes (for tank/heavy enemies)
    /// - Parameters:
    ///   - count: Number of orbital nodes
    ///   - radius: Orbital radius
    ///   - color: Node color
    /// - Returns: Orbital defense system
    static func createOrbitalDefense(count: Int, radius: CGFloat, color: UIColor) -> SKNode {
        let container = SKNode()
        container.name = "orbitalDefense"

        for i in 0..<count {
            let angle = CGFloat(i) / CGFloat(count) * .pi * 2
            let x = cos(angle) * radius
            let y = sin(angle) * radius

            // Defense node
            let node = SKShapeNode(circleOfRadius: 4)
            node.fillColor = color
            node.strokeColor = .white
            node.lineWidth = 2
            node.position = CGPoint(x: x, y: y)
            node.glowWidth = 2

            // Small orbit trail
            let trail = SKShapeNode(circleOfRadius: radius)
            trail.strokeColor = color.withAlphaComponent(0.2)
            trail.lineWidth = 1
            trail.fillColor = .clear
            container.addChild(trail)

            container.addChild(node)
        }

        // Rotate entire system
        let rotate = SKAction.rotate(byAngle: .pi * 2, duration: 3.0)
        container.run(SKAction.repeatForever(rotate))

        return container
    }
}
