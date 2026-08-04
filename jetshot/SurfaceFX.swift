//
//  SurfaceFX.swift
//  jetshot
//
//  Reusable surface treatments for solid objects: lit metal, hazard markings
//  and edge highlights.
//
//  Flat `fillColor` is what made hardware read as plastic. These helpers produce
//  cached grayscale ramps meant to be used as `SKShapeNode.fillTexture`, which
//  SpriteKit multiplies with `fillColor` — so one texture shades every hull
//  colour in the game.
//

import SpriteKit

enum SurfaceFX {

    private static var textureCache: [String: SKTexture] = [:]

    static func clearCaches() {
        textureCache.removeAll()
    }

    /// The scene's shared light direction, matching `PlanetHelper`: upper-left.
    /// Consistency across planets, hulls and hardware is what makes a set of
    /// unrelated vector shapes look like one world.
    static let lightAngle: CGFloat = .pi * 0.75

    // MARK: - Lit metal

    /// Diagonal brightness ramp with a specular band, for use as a fill texture.
    ///
    /// Grayscale on purpose: multiplied by the node's `fillColor` it shades any
    /// hue, so a single cached texture serves every obstacle and hull.
    static func metalTexture(specular: CGFloat = 1.0) -> SKTexture {
        let key = "metal|\(Int(specular * 100))"
        if let cached = textureCache[key] { return cached }

        let side: CGFloat = 128
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = true

        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let cg = ctx.cgContext

            // Base ramp: lit at the upper-left, falling into shadow bottom-right.
            let stops: [(CGFloat, CGFloat)] = [
                (0.0,  1.00),
                (0.28, 0.82),
                (0.55, 0.62),
                (0.80, 0.46),
                (1.0,  0.38)
            ]
            let colors = stops.map { UIColor(white: $0.1, alpha: 1.0).cgColor } as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: stops.map { $0.0 }
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: side, y: side),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }

            // Specular band across the lit third — the cue that reads as "metal"
            // rather than "coloured paper".
            if specular > 0 {
                cg.saveGState()
                cg.setBlendMode(.screen)
                let bandStops: [(CGFloat, CGFloat)] = [(0.0, 0.0), (0.5, 0.32 * specular), (1.0, 0.0)]
                if let band = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: bandStops.map { UIColor(white: 1.0, alpha: $0.1).cgColor } as CFArray,
                    locations: bandStops.map { $0.0 }
                ) {
                    cg.drawLinearGradient(
                        band,
                        start: CGPoint(x: side * 0.02, y: side * 0.24),
                        end: CGPoint(x: side * 0.42, y: side * 0.64),
                        options: []
                    )
                }
                cg.restoreGState()
            }
        }

        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        textureCache[key] = texture
        return texture
    }

    /// Applies the lit-metal look to a shape, preserving its hue.
    static func applyMetal(to node: SKShapeNode, tint: UIColor, specular: CGFloat = 1.0) {
        node.fillTexture = metalTexture(specular: specular)
        // Brightened, because the ramp darkens most of the surface.
        node.fillColor = tint.lighter(by: 0.30) ?? tint
    }

    // MARK: - Edge highlight

    /// Thin bright inline offset toward the light, so silhouettes read as solid
    /// panels catching a sun rather than as filled outlines.
    static func addEdgeHighlight(
        to node: SKShapeNode,
        color: UIColor = .white,
        alpha: CGFloat = 0.34,
        lineWidth: CGFloat = 1.4,
        offset: CGFloat = 1.2
    ) {
        guard let path = node.path else { return }

        let highlight = SKShapeNode(path: path)
        highlight.name = "edgeHighlight"
        highlight.fillColor = .clear
        highlight.strokeColor = color.withAlphaComponent(alpha)
        highlight.lineWidth = lineWidth
        highlight.position = CGPoint(x: cos(lightAngle) * offset, y: sin(lightAngle) * offset)
        highlight.zPosition = 3
        highlight.blendMode = .add
        node.addChild(highlight)
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
