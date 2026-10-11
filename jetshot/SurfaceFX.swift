//
//  SurfaceFX.swift
//  jetshot
//
//  Markings for hard-light hardware: caution stripes and running lights.
//
//  This used to shade hulls as lit metal, with a cached ramp for a fill texture
//  and a highlighted edge. Everything solid is now dark glass under a lit edge,
//  the way the story films draw it, and only the markings remain.
//

import SpriteKit

enum SurfaceFX {

    private static var textureCache: [String: SKTexture] = [:]

    static func clearCaches() {
        textureCache.removeAll()
    }

    // MARK: - Hazard markings

    /// Diagonal caution stripes clipped to a rectangle. Reads instantly as
    /// "do not touch", which is exactly the information an obstacle must convey.
    static func hazardStripes(
        size: CGSize,
        cornerRadius: CGFloat,
        color: UIColor = UIColor(red: 1.0, green: 0.78, blue: 0.1, alpha: 1.0),
        alpha: CGFloat = 0.5,
        stripeWidth: CGFloat = 7
    ) -> SKNode {
        // Baked into one cached texture rather than an SKCropNode full of stripe
        // shapes: a crop node costs an offscreen render pass per obstacle, and
        // obstacle-heavy levels put several on screen at once.
        let key = "hazard|\(Int(size.width))x\(Int(size.height))|\(Int(cornerRadius))"
            + "|\(Int(alpha * 100))|\(Int(stripeWidth))"

        let texture: SKTexture
        if let cached = textureCache[key] {
            texture = cached
        } else {
            let format = UIGraphicsImageRendererFormat.preferred()
            format.opaque = false
            let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                let cg = ctx.cgContext
                cg.addPath(CGPath(
                    roundedRect: CGRect(origin: .zero, size: size),
                    cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                    transform: nil
                ))
                cg.clip()

                cg.setFillColor(color.withAlphaComponent(alpha).cgColor)
                cg.setLineWidth(stripeWidth)
                cg.setStrokeColor(color.withAlphaComponent(alpha).cgColor)

                // 45° stripes swept across the diagonal extent of the panel.
                let span = size.width + size.height
                var offset = -span
                while offset < span {
                    cg.move(to: CGPoint(x: offset, y: 0))
                    cg.addLine(to: CGPoint(x: offset + size.height, y: size.height))
                    offset += stripeWidth * 2.4
                }
                cg.strokePath()
            }
            let made = SKTexture(image: image)
            made.filteringMode = .linear
            textureCache[key] = made
            texture = made
        }

        let sprite = SKSpriteNode(texture: texture, size: size)
        sprite.name = "hazardStripes"
        sprite.zPosition = 1
        return sprite
    }

    /// Slow pulsing emissive strip, for hardware that should look powered.
    static func warningLight(
        size: CGSize,
        color: UIColor,
        duration: TimeInterval = 1.1
    ) -> SKNode {
        let strip = SKShapeNode(rectOf: size, cornerRadius: min(size.width, size.height) / 2)
        strip.fillColor = color
        strip.strokeColor = .clear
        strip.blendMode = .add
        strip.alpha = 0.5
        strip.zPosition = 4

        let up = SKAction.fadeAlpha(to: 0.95, duration: duration / 2)
        up.timingMode = .easeInEaseOut
        let down = SKAction.fadeAlpha(to: 0.3, duration: duration / 2)
        down.timingMode = .easeInEaseOut
        strip.run(.repeatForever(.sequence([up, down])))

        return strip
    }
}
