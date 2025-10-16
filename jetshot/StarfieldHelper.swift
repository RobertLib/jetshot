//
//  StarfieldHelper.swift
//  jetshot
//
//  Created by Robert Libšanský on 18.10.2025.
//

import SpriteKit

class StarfieldHelper {

    static func createStarfield(for scene: SKScene) -> SKEmitterNode {
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
        starfield.particleBirthRate = 3
        starfield.particleLifetime = 25
        starfield.particleLifetimeRange = 5
        starfield.particlePositionRange = CGVector(dx: scene.size.width, dy: 0)
        starfield.particleSpeed = 50
        starfield.particleSpeedRange = 30
        starfield.emissionAngle = .pi * 1.5 // downward
        starfield.emissionAngleRange = 0
        starfield.particleScale = 0.3
        starfield.particleScaleRange = 0.2
        starfield.particleScaleSpeed = -0.001
        starfield.particleAlpha = 0.8
        starfield.particleAlphaRange = 0.3
        starfield.particleAlphaSpeed = -0.01
        starfield.particleColor = .white
        starfield.particleColorBlendFactor = 1.0
        starfield.particleBlendMode = .alpha
        starfield.position = CGPoint(x: scene.size.width / 2, y: scene.size.height + 10)
        starfield.zPosition = -10

        // Calculate time needed to fill entire screen: height / speed
        // With speed 50 and height ~900, we need ~18 seconds minimum
        let fillTime = TimeInterval(scene.size.height / 50) + 5
        starfield.advanceSimulationTime(fillTime)

        return starfield
    }
}
