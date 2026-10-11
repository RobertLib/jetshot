//
//  StarfieldHelper.swift
//  jetshot
//
//  Created by Robert Libšanský on 18.10.2025.
//
//  What is left of the old particle sky. The emitters, gradient, galaxies, nebulae
//  and planets that used to sit behind every screen are now `GameBackdrop`, the
//  story films' 3D world; only the menu's speed streaks remain.
//

import SpriteKit

class StarfieldHelper {

    // MARK: - Speed streaks

    static let speedStreaksName = "speedStreaks"

    /// Long, faint streaks rushing past — the fastest layer of the sky.
    ///
    /// A trickle, so there is always a sense of travel behind the menu's hero ship.
    static func createSpeedStreaks(for scene: SKScene) -> SKEmitterNode {
        let streaks = SKEmitterNode()
        streaks.name = speedStreaksName
        streaks.particleTexture = streakTexture()
        streaks.particleBirthRate = cruiseStreakRate
        streaks.particleLifetime = 2.0
        streaks.particlePositionRange = CGVector(dx: scene.size.width, dy: 0)
        streaks.particleSpeed = 760
        streaks.particleSpeedRange = 220
        streaks.emissionAngle = .pi * 1.5
        streaks.emissionAngleRange = 0
        streaks.particleScale = 0.9
        streaks.particleScaleRange = 0.5
        streaks.particleAlpha = 0.16
        streaks.particleAlphaRange = 0.08
        streaks.particleColor = UIColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 1.0)
        streaks.particleColorBlendFactor = 1
        streaks.particleBlendMode = .add
        streaks.position = CGPoint(x: scene.size.width / 2, y: scene.size.height + 40)
        streaks.zPosition = -9
        return streaks
    }

    private static let cruiseStreakRate: CGFloat = 1.6

    private static var cachedStreakTexture: SKTexture?

    /// A thin vertical line, bright at the head and fading along its tail.
    private static func streakTexture() -> SKTexture {
        if let texture = cachedStreakTexture { return texture }
        let size = CGSize(width: 3, height: 64)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let colors = [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            ctx.cgContext.addRect(CGRect(x: 0.75, y: 0, width: 1.5, height: size.height))
            ctx.cgContext.clip()
            // The head is at the bottom of the sprite: the streak falls down the screen.
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        let texture = SKTexture(image: image)
        cachedStreakTexture = texture
        return texture
    }
}
