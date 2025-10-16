//
//  PlanetHelper.swift
//  jetshot
//
//  Created by Robert Libšanský on 08.11.2025.
//

import SpriteKit

class PlanetHelper {

    // Planet types with different color palettes
    enum PlanetType {
        case rocky      // Rocky planets - brown/gray
        case gasGiant   // Gas giants - orange/yellow
        case ice        // Ice planets - blue/white
        case desert     // Desert planets - yellow-brown
        case toxic      // Toxic planets - green

        var colors: [UIColor] {
            switch self {
            case .rocky:
                return [
                    UIColor(red: 0.25, green: 0.20, blue: 0.18, alpha: 1.0),
                    UIColor(red: 0.30, green: 0.25, blue: 0.22, alpha: 1.0),
                    UIColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 1.0)
                ]
            case .gasGiant:
                return [
                    UIColor(red: 0.55, green: 0.35, blue: 0.20, alpha: 1.0),
                    UIColor(red: 0.60, green: 0.40, blue: 0.25, alpha: 1.0),
                    UIColor(red: 0.50, green: 0.30, blue: 0.22, alpha: 1.0)
                ]
            case .ice:
                return [
                    UIColor(red: 0.35, green: 0.42, blue: 0.55, alpha: 1.0),
                    UIColor(red: 0.40, green: 0.48, blue: 0.60, alpha: 1.0),
                    UIColor(red: 0.32, green: 0.38, blue: 0.50, alpha: 1.0)
                ]
            case .desert:
                return [
                    UIColor(red: 0.50, green: 0.38, blue: 0.22, alpha: 1.0),
                    UIColor(red: 0.45, green: 0.35, blue: 0.20, alpha: 1.0),
                    UIColor(red: 0.48, green: 0.40, blue: 0.25, alpha: 1.0)
                ]
            case .toxic:
                return [
                    UIColor(red: 0.22, green: 0.35, blue: 0.25, alpha: 1.0),
                    UIColor(red: 0.25, green: 0.38, blue: 0.28, alpha: 1.0),
                    UIColor(red: 0.20, green: 0.32, blue: 0.23, alpha: 1.0)
                ]
            }
        }

        static func random() -> PlanetType {
            let types: [PlanetType] = [.rocky, .gasGiant, .ice, .desert, .toxic]
            return types.randomElement()!
        }
    }

    // Creates planet texture
    private static func createPlanetTexture(radius: CGFloat, type: PlanetType) -> SKTexture {
        let size = CGSize(width: radius * 2, height: radius * 2)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return SKTexture()
        }

        // Random color from the palette of the given type
        let planetColor = type.colors.randomElement()!

        // Draw main planet circle
        context.setFillColor(planetColor.cgColor)
        context.fillEllipse(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))

        // Add gradient for 3D sphere effect (lighting)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let lightColor = planetColor.lighter(by: 0.4) ?? planetColor
        let darkColor = planetColor.darker(by: 0.4) ?? planetColor

        let colors = [lightColor.cgColor, planetColor.cgColor, darkColor.cgColor] as CFArray
        let locations: [CGFloat] = [0.0, 0.4, 1.0]

        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            context.saveGState()
            context.addEllipse(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            context.clip()

            // Gradient from top-left corner (sun lighting)
            context.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: radius * 0.4, y: radius * 0.4),
                startRadius: 0,
                endCenter: CGPoint(x: radius, y: radius),
                endRadius: radius * 1.4,
                options: []
            )
            context.restoreGState()
        }

        // Add atmospheric rim light
        context.saveGState()
        context.addEllipse(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        context.clip()

        let rimColor = lightColor.withAlphaComponent(0.2)
        context.setFillColor(rimColor.cgColor)
        context.fillEllipse(in: CGRect(x: radius * 0.1, y: radius * 0.1,
                                      width: radius * 0.6, height: radius * 0.6))
        context.restoreGState()

        // Add surface texture details (craters/spots)
        let spotCount = Int.random(in: 3...7)
        for _ in 0..<spotCount {
            let spotSize = radius * CGFloat.random(in: 0.08...0.18)
            let angle = CGFloat.random(in: 0...(CGFloat.pi * 2))
            let distance = CGFloat.random(in: 0...(radius * 0.7))
            let spotX = radius + cos(angle) * distance
            let spotY = radius + sin(angle) * distance

            let spotColor = planetColor.darker(by: 0.3)?.withAlphaComponent(0.4) ?? planetColor
            context.setFillColor(spotColor.cgColor)
            context.fillEllipse(in: CGRect(x: spotX - spotSize/2, y: spotY - spotSize/2,
                                          width: spotSize, height: spotSize))
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        return SKTexture(image: image)
    }

    // Creates a planet
    static func createPlanet(for scene: SKScene) -> SKSpriteNode {
        let type = PlanetType.random()
        let radius = CGFloat.random(in: 25...70) // Smaller, more realistic size
        let texture = createPlanetTexture(radius: radius, type: type)

        let planet = SKSpriteNode(texture: texture)
        planet.size = CGSize(width: radius * 2, height: radius * 2)
        planet.alpha = 0.5 // Slightly more subtle
        planet.zPosition = -15 // Behind stars but in front of gradient background
        planet.name = "planet"

        // Random X position - allow partial visibility but ensure substantial part is visible
        let minVisiblePortion: CGFloat = 0.4 // At least 40% of planet must be visible
        let minX = -radius * (1 - minVisiblePortion)
        let maxX = scene.size.width + radius * (1 - minVisiblePortion)
        let randomX = CGFloat.random(in: minX...maxX)
        planet.position = CGPoint(x: randomX, y: scene.size.height + radius)

        // Slow downward movement
        let speed = CGFloat.random(in: 10...20) // Even slower for distant feel
        let duration = TimeInterval((scene.size.height + radius * 2) / speed)

        let moveAction = SKAction.moveBy(x: 0, y: -(scene.size.height + radius * 2), duration: duration)
        let removeAction = SKAction.removeFromParent()
        let sequence = SKAction.sequence([moveAction, removeAction])

        planet.run(sequence)

        // Very subtle rotation for realistic effect
        let rotationDuration = TimeInterval.random(in: 80...150)
        let rotationDirection = Bool.random() ? CGFloat.pi * 2 : -CGFloat.pi * 2
        let rotateAction = SKAction.rotate(byAngle: rotationDirection, duration: rotationDuration)
        let rotateForever = SKAction.repeatForever(rotateAction)
        planet.run(rotateForever)

        return planet
    }

    // Starts planet generation
    static func startPlanetGeneration(in scene: SKScene, parentNode: SKNode? = nil) {
        let parent = parentNode ?? scene

        // Initial planets - fewer for more space-like feel
        let initialPlanetCount = Int.random(in: 0...2)
        for _ in 0..<initialPlanetCount {
            let planet = createPlanet(for: scene)
            // Distribute planets across entire screen height
            planet.position.y = CGFloat.random(in: 0...scene.size.height)
            parent.addChild(planet)
        }

        // Periodic generation of new planets
        let spawnAction = SKAction.run {
            // Create new planet with lower probability for realism
            if Double.random(in: 0...1) < 0.2 { // 20% chance - planets are rare
                let planet = createPlanet(for: scene)
                parent.addChild(planet)
            }
        }

        let waitAction = SKAction.wait(forDuration: 12.0) // Check every 12 seconds
        let sequenceAction = SKAction.sequence([spawnAction, waitAction])
        let repeatAction = SKAction.repeatForever(sequenceAction)

        parent.run(repeatAction, withKey: "planetGeneration")
    }

    // Stops planet generation
    static func stopPlanetGeneration() {
        // Note: stopping is now handled by pausing the parent node
    }

    // Removes all planets
    static func removeAllPlanets(from scene: SKScene) {
        scene.enumerateChildNodes(withName: "planet") { node, _ in
            node.removeFromParent()
        }
    }
}

// Extension for lighter/darker colors
extension UIColor {
    func lighter(by percentage: CGFloat = 0.3) -> UIColor? {
        return self.adjust(by: abs(percentage))
    }

    func darker(by percentage: CGFloat = 0.3) -> UIColor? {
        return self.adjust(by: -abs(percentage))
    }

    func adjust(by percentage: CGFloat) -> UIColor? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        if self.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return UIColor(
                red: min(red + percentage, 1.0),
                green: min(green + percentage, 1.0),
                blue: min(blue + percentage, 1.0),
                alpha: alpha
            )
        }
        return nil
    }
}
