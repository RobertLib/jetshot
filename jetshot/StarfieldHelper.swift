//
//  StarfieldHelper.swift
//  jetshot
//
//  Created by Robert Libšanský on 18.10.2025.
//

import SpriteKit

class StarfieldHelper {

    static func createStarfield(for scene: SKScene) -> SKEmitterNode {
        // Create gradient background
        let gradientSize = CGSize(width: 1, height: scene.size.height)
        UIGraphicsBeginImageContextWithOptions(gradientSize, false, 0)
        if let context = UIGraphicsGetCurrentContext() {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [
                UIColor(red: 0.05, green: 0.02, blue: 0.15, alpha: 1.0).cgColor,
                UIColor(red: 0.02, green: 0.05, blue: 0.12, alpha: 1.0).cgColor,
                UIColor(red: 0.01, green: 0.02, blue: 0.08, alpha: 1.0).cgColor,
                UIColor(red: 0.0, green: 0.0, blue: 0.03, alpha: 1.0).cgColor
            ] as CFArray

            let locations: [CGFloat] = [0.0, 0.3, 0.7, 1.0]

            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
                context.drawLinearGradient(gradient,
                                           start: CGPoint(x: 0, y: gradientSize.height),
                                           end: CGPoint(x: 0, y: 0),
                                           options: [])

                let image = UIGraphicsGetImageFromCurrentImageContext()!
                UIGraphicsEndImageContext()

                let texture = SKTexture(image: image)
                let gradientSprite = SKSpriteNode(texture: texture, size: scene.size)
                gradientSprite.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
                gradientSprite.zPosition = -20
                gradientSprite.name = "gradientBackground"
                scene.addChild(gradientSprite)
            } else {
                UIGraphicsEndImageContext()
            }
        }

        scene.backgroundColor = UIColor(red: 0.01, green: 0.02, blue: 0.08, alpha: 1.0)

        // Add distant galaxies and nebulae (static background)
        addDistantGalaxies(to: scene)
        addNebulae(to: scene)

        // Create star texture with glow (radial gradient for more realistic look)
        let size = CGSize(width: 16, height: 16)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let context = UIGraphicsGetCurrentContext()!

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            UIColor.white.cgColor,
            UIColor(white: 1.0, alpha: 0.5).cgColor,
            UIColor(white: 1.0, alpha: 0.0).cgColor
        ] as CFArray
        let locations: [CGFloat] = [0.0, 0.5, 1.0]

        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            context.drawRadialGradient(gradient,
                                       startCenter: CGPoint(x: size.width / 2, y: size.height / 2),
                                       startRadius: 0,
                                       endCenter: CGPoint(x: size.width / 2, y: size.height / 2),
                                       endRadius: size.width / 2,
                                       options: [])
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        let texture = SKTexture(image: image)

        let starfield = SKEmitterNode()
        starfield.particleTexture = texture
        starfield.particleBirthRate = 3  // More stars for richer field
        starfield.particleLifetime = 20
        starfield.particleLifetimeRange = 5
        starfield.particlePositionRange = CGVector(dx: scene.size.width, dy: 0)
        starfield.particleSpeed = 50
        starfield.particleSpeedRange = 30
        starfield.emissionAngle = .pi * 1.5 // downward
        starfield.emissionAngleRange = 0

        // Variable star sizes for depth
        starfield.particleScale = 0.2
        starfield.particleScaleRange = 0.4  // Bigger range for variety (tiny to large stars)
        starfield.particleScaleSpeed = -0.001

        // Variable brightness
        starfield.particleAlpha = 0.6
        starfield.particleAlphaRange = 0.3
        starfield.particleAlphaSpeed = -0.01

        // Star color variations (white, blue-white, yellow-white, red-white)
        starfield.particleColor = UIColor(white: 0.95, alpha: 1.0)
        starfield.particleColorBlendFactor = 0.8
        starfield.particleColorRedRange = 0.3
        starfield.particleColorGreenRange = 0.2
        starfield.particleColorBlueRange = 0.4

        starfield.particleBlendMode = .add  // Brighter, glowing stars
        starfield.position = CGPoint(x: scene.size.width / 2, y: scene.size.height + 10)
        starfield.zPosition = -10
        starfield.name = "starfield"

        let fillTime = TimeInterval(scene.size.height / 50)
        starfield.advanceSimulationTime(fillTime)

        return starfield
    }

    // Add distant galaxies to background
    private static func addDistantGalaxies(to scene: SKScene) {
        let galaxyCount = 1

        for i in 0..<galaxyCount {
            let galaxy = createGalaxySprite()
            galaxy.position = CGPoint(
                x: CGFloat.random(in: scene.size.width * 0.2...scene.size.width * 0.8),
                y: CGFloat.random(in: scene.size.height * 0.3...scene.size.height * 0.7)
            )
            galaxy.zPosition = -18
            galaxy.name = "galaxy_\(i)"
            galaxy.alpha = 0.15 + CGFloat.random(in: 0...0.1)
            scene.addChild(galaxy)

            // Slow rotation for galaxies
            let rotation = SKAction.rotate(byAngle: .pi * 2, duration: 120 + Double.random(in: -20...20))
            galaxy.run(SKAction.repeatForever(rotation))
        }
    }

    private static func createGalaxySprite() -> SKSpriteNode {
        let size = CGSize(width: 180, height: 180)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else {
            return SKSpriteNode()
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // Create spiral galaxy with multiple layers
        for layer in 0..<3 {
            let radius = size.width / 2 - CGFloat(layer * 20)
            let alpha = 0.8 - CGFloat(layer) * 0.25

            let colors = [
                UIColor(red: 0.8, green: 0.9, blue: 1.0, alpha: alpha).cgColor,
                UIColor(red: 0.6, green: 0.7, blue: 0.9, alpha: alpha * 0.5).cgColor,
                UIColor(red: 0.3, green: 0.4, blue: 0.6, alpha: alpha * 0.2).cgColor,
                UIColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.0).cgColor
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.3, 0.7, 1.0]

            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
                context.saveGState()
                context.scaleBy(x: 1.0, y: 0.4) // Flatten to create disk shape
                context.drawRadialGradient(gradient,
                                           startCenter: CGPoint(x: size.width / 2, y: size.height / 1.3),
                                           startRadius: 0,
                                           endCenter: CGPoint(x: size.width / 2, y: size.height / 1.3),
                                           endRadius: radius,
                                           options: [])
                context.restoreGState()
            }
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        return SKSpriteNode(texture: SKTexture(image: image))
    }

    // Add nebulae clouds to background
    private static func addNebulae(to scene: SKScene) {
        let nebulaCount = 3

        for i in 0..<nebulaCount {
            let nebula = createNebulaSprite()
            nebula.position = CGPoint(
                x: CGFloat.random(in: 0...scene.size.width),
                y: CGFloat.random(in: scene.size.height * 0.2...scene.size.height * 0.8)
            )
            nebula.zPosition = -17
            nebula.name = "nebula_\(i)"
            nebula.alpha = 0.12 + CGFloat.random(in: 0...0.08)
            scene.addChild(nebula)

            // Very slow pulsing effect
            let pulse = SKAction.sequence([
                SKAction.fadeAlpha(to: nebula.alpha * 1.3, duration: 8 + Double.random(in: -2...2)),
                SKAction.fadeAlpha(to: nebula.alpha * 0.7, duration: 8 + Double.random(in: -2...2))
            ])
            nebula.run(SKAction.repeatForever(pulse))
        }
    }

    private static func createNebulaSprite() -> SKSpriteNode {
        let size = CGSize(width: 1400, height: 1200)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else {
            return SKSpriteNode()
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // Random nebula color (purple, blue, pink, or cyan)
        let colorTypes = [
            // Purple nebula
            [UIColor(red: 0.6, green: 0.3, blue: 0.8, alpha: 1.0),
             UIColor(red: 0.3, green: 0.2, blue: 0.5, alpha: 0.6),
             UIColor(red: 0.2, green: 0.1, blue: 0.3, alpha: 0.0)],
            // Blue nebula
            [UIColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0),
             UIColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 0.6),
             UIColor(red: 0.05, green: 0.15, blue: 0.3, alpha: 0.0)],
            // Pink nebula
            [UIColor(red: 0.9, green: 0.4, blue: 0.7, alpha: 1.0),
             UIColor(red: 0.6, green: 0.2, blue: 0.4, alpha: 0.6),
             UIColor(red: 0.3, green: 0.1, blue: 0.2, alpha: 0.0)],
            // Cyan nebula
            [UIColor(red: 0.3, green: 0.8, blue: 0.9, alpha: 1.0),
             UIColor(red: 0.2, green: 0.5, blue: 0.6, alpha: 0.6),
             UIColor(red: 0.1, green: 0.25, blue: 0.3, alpha: 0.0)]
        ]

        let selectedColors = colorTypes.randomElement()!

        // Draw multiple cloud layers for more organic look
        for _ in 0..<5 {
            let centerX = CGFloat.random(in: size.width * 0.2...size.width * 0.8)
            let centerY = CGFloat.random(in: size.height * 0.2...size.height * 0.8)
            let radius = CGFloat.random(in: 180...350)

            let colors = [
                selectedColors[0].cgColor,
                selectedColors[1].cgColor,
                selectedColors[2].cgColor
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.5, 1.0]

            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
                context.drawRadialGradient(gradient,
                                           startCenter: CGPoint(x: centerX, y: centerY),
                                           startRadius: 0,
                                           endCenter: CGPoint(x: centerX, y: centerY),
                                           endRadius: radius,
                                           options: [])
            }
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        return SKSpriteNode(texture: SKTexture(image: image))
    }

    static func updateStarfield(_ starfield: SKEmitterNode, for scene: SKScene) {
        starfield.particlePositionRange = CGVector(dx: scene.size.width, dy: 0)
        starfield.position = CGPoint(x: scene.size.width / 2, y: scene.size.height + 10)
    }

    static func createShootingStars(for scene: SKScene) -> SKEmitterNode {
        // Create elongated texture for shooting stars/meteors
        let size = CGSize(width: 20, height: 4)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let context = UIGraphicsGetCurrentContext()!

        // Create gradient for meteor trail effect
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            UIColor.white.cgColor,
            UIColor(white: 1.0, alpha: 0.0).cgColor
        ] as CFArray
        let locations: [CGFloat] = [0.0, 1.0]

        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: 0, y: size.height / 2),
                                       end: CGPoint(x: size.width, y: size.height / 2),
                                       options: [])
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        let texture = SKTexture(image: image)

        let shootingStars = SKEmitterNode()
        shootingStars.particleTexture = texture
        shootingStars.particleBirthRate = 0.3  // Rare occurrence for dramatic effect
        shootingStars.particleLifetime = 2.5
        shootingStars.particleLifetimeRange = 1.0
        shootingStars.particlePositionRange = CGVector(dx: scene.size.width * 1.5, dy: 100)
        shootingStars.particleSpeed = 400  // Fast movement
        shootingStars.particleSpeedRange = 200

        // Diagonal downward movement (like real shooting stars)
        shootingStars.emissionAngle = .pi * 1.35  // ~245 degrees (diagonal down-left)
        shootingStars.emissionAngleRange = .pi * 0.15  // Some variation

        shootingStars.particleScale = 0.8
        shootingStars.particleScaleRange = 0.4
        shootingStars.particleScaleSpeed = -0.2

        shootingStars.particleAlpha = 0.8
        shootingStars.particleAlphaRange = 0.2
        shootingStars.particleAlphaSpeed = -0.4  // Fade out

        // Color variations - white to slight blue/yellow tint
        shootingStars.particleColor = UIColor.white
        shootingStars.particleColorBlendFactor = 0.8
        shootingStars.particleColorRedRange = 0.2
        shootingStars.particleColorGreenRange = 0.2
        shootingStars.particleColorBlueRange = 0.3

        shootingStars.particleBlendMode = .add  // Bright, glowing effect
        shootingStars.particleRotation = -.pi / 4  // Angle the streak
        shootingStars.particleRotationRange = .pi / 8

        shootingStars.position = CGPoint(x: scene.size.width * 0.75, y: scene.size.height + 50)
        shootingStars.zPosition = -9  // Just in front of starfield
        shootingStars.name = "shootingStars"

        return shootingStars
    }

    static func createMeteors(for scene: SKScene) -> SKEmitterNode {
        // Create round texture for meteors
        let size = CGSize(width: 12, height: 12)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let context = UIGraphicsGetCurrentContext()!

        // Create radial gradient for meteor
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            UIColor(red: 1.0, green: 0.8, blue: 0.4, alpha: 1.0).cgColor,  // Orange center
            UIColor(red: 0.8, green: 0.4, blue: 0.2, alpha: 1.0).cgColor,  // Darker orange
            UIColor(red: 0.6, green: 0.2, blue: 0.1, alpha: 0.5).cgColor   // Brown edge
        ] as CFArray
        let locations: [CGFloat] = [0.0, 0.6, 1.0]

        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            context.drawRadialGradient(gradient,
                                       startCenter: CGPoint(x: size.width / 2, y: size.height / 2),
                                       startRadius: 0,
                                       endCenter: CGPoint(x: size.width / 2, y: size.height / 2),
                                       endRadius: size.width / 2,
                                       options: [])
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        let texture = SKTexture(image: image)

        let meteors = SKEmitterNode()
        meteors.particleTexture = texture
        meteors.particleBirthRate = 0.5  // More frequent than shooting stars
        meteors.particleLifetime = 3.0
        meteors.particleLifetimeRange = 1.5
        meteors.particlePositionRange = CGVector(dx: scene.size.width * 1.2, dy: 50)
        meteors.particleSpeed = 250
        meteors.particleSpeedRange = 100

        // Steeper angle for meteors
        meteors.emissionAngle = .pi * 1.4  // ~252 degrees
        meteors.emissionAngleRange = .pi * 0.1

        meteors.particleScale = 0.5
        meteors.particleScaleRange = 0.3
        meteors.particleScaleSpeed = -0.1

        meteors.particleAlpha = 0.7
        meteors.particleAlphaRange = 0.2
        meteors.particleAlphaSpeed = -0.3

        meteors.particleColor = UIColor(red: 1.0, green: 0.7, blue: 0.3, alpha: 1.0)
        meteors.particleColorBlendFactor = 1.0

        meteors.particleBlendMode = .add
        meteors.particleRotation = 0
        meteors.particleRotationSpeed = 2.0  // Spinning meteors

        meteors.position = CGPoint(x: scene.size.width * 0.6, y: scene.size.height + 50)
        meteors.zPosition = -8  // In front of shooting stars
        meteors.name = "meteors"

        return meteors
    }

    static func updateShootingStars(_ shootingStars: SKEmitterNode, for scene: SKScene) {
        shootingStars.particlePositionRange = CGVector(dx: scene.size.width * 1.5, dy: 100)
        shootingStars.position = CGPoint(x: scene.size.width * 0.75, y: scene.size.height + 50)
    }

    static func updateMeteors(_ meteors: SKEmitterNode, for scene: SKScene) {
        meteors.particlePositionRange = CGVector(dx: scene.size.width * 1.2, dy: 50)
        meteors.position = CGPoint(x: scene.size.width * 0.6, y: scene.size.height + 50)
    }
}
