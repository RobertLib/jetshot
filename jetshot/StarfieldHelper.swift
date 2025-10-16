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


        // Create a simple circle texture for stars
        let size = CGSize(width: 8, height: 8)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        let texture = SKTexture(image: image)

        let starfield = SKEmitterNode()
        starfield.particleTexture = texture
        starfield.particleBirthRate = 2  // Reduced from 3 for better performance
        starfield.particleLifetime = 20  // Reduced from 25
        starfield.particleLifetimeRange = 5
        starfield.particlePositionRange = CGVector(dx: scene.size.width, dy: 0)
        starfield.particleSpeed = 50
        starfield.particleSpeedRange = 30
        starfield.emissionAngle = .pi * 1.5 // downward
        starfield.emissionAngleRange = 0
        starfield.particleScale = 0.3
        starfield.particleScaleRange = 0.2
        starfield.particleScaleSpeed = -0.001
        starfield.particleAlpha = 0.5
        starfield.particleAlphaRange = 0.25
        starfield.particleAlphaSpeed = -0.01
        starfield.particleColor = UIColor(white: 0.9, alpha: 1.0)
        starfield.particleColorBlendFactor = 1.0
        starfield.particleBlendMode = .alpha
        starfield.position = CGPoint(x: scene.size.width / 2, y: scene.size.height + 10)
        starfield.zPosition = -10
        starfield.name = "starfield"

        // Calculate time needed to fill entire screen: height / speed
        // With speed 50 and height ~900, we need ~18 seconds minimum
        // Reduced simulation time to avoid initial FPS drop
        let fillTime = TimeInterval(scene.size.height / 50)
        starfield.advanceSimulationTime(fillTime)

        return starfield
    }

    static func updateStarfield(_ starfield: SKEmitterNode, for scene: SKScene) {
        starfield.particlePositionRange = CGVector(dx: scene.size.width, dy: 0)
        starfield.position = CGPoint(x: scene.size.width / 2, y: scene.size.height + 10)
    }
}
