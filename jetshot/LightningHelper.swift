//
//  LightningHelper.swift
//  jetshot
//
//  Created by Robert Libšanský on 27.10.2025.
//

import SpriteKit

class LightningHelper {

    /// Creates a procedurally generated lightning bolt from start to end point
    static func createLightningBolt(from startPoint: CGPoint, to endPoint: CGPoint, segments: Int = 8, displacement: CGFloat = 15) -> SKShapeNode {
        let container = SKNode()

        // Generate lightning path
        let points = generateLightningPoints(from: startPoint, to: endPoint, segments: segments, displacement: displacement)

        // Create main lightning bolt
        let mainBolt = createBoltShape(points: points, color: UIColor(red: 0.8, green: 0.6, blue: 1.0, alpha: 1.0), width: 4)
        container.addChild(mainBolt)

        // Create bright core
        let coreBolt = createBoltShape(points: points, color: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9), width: 2)
        coreBolt.zPosition = 1
        container.addChild(coreBolt)

        // Create outer glow
        let glowBolt = createBoltShape(points: points, color: UIColor(red: 0.6, green: 0.3, blue: 1.0, alpha: 0.3), width: 8)
        glowBolt.zPosition = -1
        container.addChild(glowBolt)

        // Add random branches for more realistic lightning
        let branchCount = Int.random(in: 1...3)
        for _ in 0..<branchCount {
            if let branch = createRandomBranch(from: points) {
                container.addChild(branch)
            }
        }

        // Create wrapper SKShapeNode to return
        let wrapper = SKShapeNode()
        wrapper.addChild(container)

        // Add flicker animation
        let flicker = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.7, duration: 0.05),
            SKAction.fadeAlpha(to: 1.0, duration: 0.05)
        ])
        wrapper.run(SKAction.repeat(flicker, count: 2))

        // Add glow effect
        GlowHelper.addEnhancedGlow(
            to: wrapper,
            color: UIColor(red: 0.7, green: 0.4, blue: 1.0, alpha: 1.0),
            intensity: 1.5
        )

        return wrapper
    }

    /// Generates points for lightning path using recursive subdivision
    private static func generateLightningPoints(from start: CGPoint, to end: CGPoint, segments: Int, displacement: CGFloat) -> [CGPoint] {
        var points = [start]

        // Calculate direction
        let dx = (end.x - start.x) / CGFloat(segments)
        let dy = (end.y - start.y) / CGFloat(segments)

        // Generate intermediate points with random displacement
        for i in 1..<segments {
            let baseX = start.x + dx * CGFloat(i)
            let baseY = start.y + dy * CGFloat(i)

            // Add perpendicular displacement
            let perpX = -dy
            let perpY = dx
            let length = sqrt(perpX * perpX + perpY * perpY)

            if length > 0 {
                let normalizedPerpX = perpX / length
                let normalizedPerpY = perpY / length

                // Random displacement decreases towards the end
                let progress = CGFloat(i) / CGFloat(segments)
                let currentDisplacement = displacement * (1 - progress * 0.5)
                let offset = CGFloat.random(in: -currentDisplacement...currentDisplacement)

                let x = baseX + normalizedPerpX * offset
                let y = baseY + normalizedPerpY * offset

                points.append(CGPoint(x: x, y: y))
            } else {
                points.append(CGPoint(x: baseX, y: baseY))
            }
        }

        points.append(end)
        return points
    }

    /// Creates a shape node from points
    private static func createBoltShape(points: [CGPoint], color: UIColor, width: CGFloat) -> SKShapeNode {
        guard points.count >= 2 else {
            return SKShapeNode()
        }

        let path = CGMutablePath()
        path.move(to: points[0])

        for i in 1..<points.count {
            path.addLine(to: points[i])
        }

        let shape = SKShapeNode(path: path)
        shape.strokeColor = color
        shape.lineWidth = width
        shape.lineCap = .round
        shape.lineJoin = .round
        shape.fillColor = .clear
        shape.blendMode = .add

        return shape
    }

    /// Creates a random branch from the main lightning bolt
    private static func createRandomBranch(from points: [CGPoint]) -> SKNode? {
        guard points.count > 2 else { return nil }

        // Pick random point from the middle section
        let startIndex = Int.random(in: 1...(points.count - 2))
        let startPoint = points[startIndex]

        // Create branch endpoint
        let branchLength = CGFloat.random(in: 20...40)
        let branchAngle = CGFloat.random(in: -.pi/3 ... .pi/3)

        // Calculate direction from previous to next point
        let prevPoint = points[max(0, startIndex - 1)]
        let nextPoint = points[min(points.count - 1, startIndex + 1)]
        let mainAngle = atan2(nextPoint.y - prevPoint.y, nextPoint.x - prevPoint.x)

        let finalAngle = mainAngle + branchAngle + .pi / 2
        let endPoint = CGPoint(
            x: startPoint.x + cos(finalAngle) * branchLength,
            y: startPoint.y + sin(finalAngle) * branchLength
        )

        // Generate branch points
        let branchPoints = generateLightningPoints(
            from: startPoint,
            to: endPoint,
            segments: 3,
            displacement: 8
        )

        let container = SKNode()

        // Main branch
        let mainBranch = createBoltShape(points: branchPoints, color: UIColor(red: 0.8, green: 0.6, blue: 1.0, alpha: 0.7), width: 3)
        container.addChild(mainBranch)

        // Branch core
        let coreBranch = createBoltShape(points: branchPoints, color: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.6), width: 1.5)
        coreBranch.zPosition = 1
        container.addChild(coreBranch)

        return container
    }

    /// Creates multiple lightning bolts that fill the screen
    static func createScreenWideLightning(at position: CGPoint, sceneSize: CGSize, count: Int = 5) -> SKNode {
        let container = SKNode()
        container.position = position

        // Create multiple bolts spreading across the screen
        for i in 0..<count {
            let startPoint = CGPoint(x: 0, y: 0)

            // Calculate end point distributed across screen width
            let spacing = sceneSize.width / CGFloat(count + 1)
            let targetX = spacing * CGFloat(i + 1) - position.x
            let targetY = sceneSize.height - position.y + 50 // Beyond top of screen

            // Add some randomness
            let randomOffsetX = CGFloat.random(in: -30...30)
            let randomOffsetY = CGFloat.random(in: -20...20)

            let endPoint = CGPoint(x: targetX + randomOffsetX, y: targetY + randomOffsetY)

            // Create lightning bolt
            let bolt = createLightningBolt(
                from: startPoint,
                to: endPoint,
                segments: Int.random(in: 10...15),
                displacement: CGFloat.random(in: 12...20)
            )

            // Stagger the animation slightly
            bolt.alpha = 0
            let delay = Double(i) * 0.02
            let fadeIn = SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.fadeIn(withDuration: 0.05)
            ])
            bolt.run(fadeIn)

            container.addChild(bolt)
        }

        // Add screen flash effect
        let flash = SKShapeNode(rectOf: sceneSize)
        flash.fillColor = UIColor(red: 0.8, green: 0.6, blue: 1.0, alpha: 0.2)
        flash.strokeColor = .clear
        flash.position = CGPoint(x: sceneSize.width / 2 - position.x, y: sceneSize.height / 2 - position.y)
        flash.zPosition = -2
        flash.blendMode = .add

        let flashAnimation = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.4, duration: 0.05),
            SKAction.fadeAlpha(to: 0.0, duration: 0.15)
        ])
        flash.run(flashAnimation)
        container.addChild(flash)

        // Remove after animation
        let removeAction = SKAction.sequence([
            SKAction.wait(forDuration: 0.3),
            SKAction.removeFromParent()
        ])
        container.run(removeAction)

        return container
    }
}
