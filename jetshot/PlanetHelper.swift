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
            // Brighter than the surface albedo you'd expect: the terminator and
            // vignette both darken these considerably by the time they ship.
            case .rocky:
                return [
                    UIColor(red: 0.42, green: 0.35, blue: 0.31, alpha: 1.0),
                    UIColor(red: 0.48, green: 0.41, blue: 0.36, alpha: 1.0),
                    UIColor(red: 0.38, green: 0.37, blue: 0.40, alpha: 1.0)
                ]
            case .gasGiant:
                return [
                    UIColor(red: 0.72, green: 0.48, blue: 0.26, alpha: 1.0),
                    UIColor(red: 0.78, green: 0.54, blue: 0.32, alpha: 1.0),
                    UIColor(red: 0.66, green: 0.41, blue: 0.28, alpha: 1.0)
                ]
            case .ice:
                return [
                    UIColor(red: 0.50, green: 0.60, blue: 0.76, alpha: 1.0),
                    UIColor(red: 0.56, green: 0.67, blue: 0.82, alpha: 1.0),
                    UIColor(red: 0.45, green: 0.54, blue: 0.70, alpha: 1.0)
                ]
            case .desert:
                return [
                    UIColor(red: 0.68, green: 0.52, blue: 0.30, alpha: 1.0),
                    UIColor(red: 0.62, green: 0.48, blue: 0.27, alpha: 1.0),
                    UIColor(red: 0.66, green: 0.55, blue: 0.34, alpha: 1.0)
                ]
            case .toxic:
                return [
                    UIColor(red: 0.32, green: 0.50, blue: 0.36, alpha: 1.0),
                    UIColor(red: 0.36, green: 0.55, blue: 0.40, alpha: 1.0),
                    UIColor(red: 0.29, green: 0.46, blue: 0.33, alpha: 1.0)
                ]
            }
        }

        static func random() -> PlanetType {
            let types: [PlanetType] = [.rocky, .gasGiant, .ice, .desert, .toxic]
            return types.randomElement() ?? .rocky
        }
    }

    /// Direction the star lights every planet from. Shared by all bodies so the
    /// scene has one consistent light source instead of each planet inventing
    /// its own — the single biggest reason the old planets read as flat discs.
    /// Expressed in Core Graphics image space (y grows downward), so this points
    /// at the *upper* left once the texture is drawn, matching `SurfaceFX`.
    private static let lightDirection = CGVector(dx: -0.58, dy: -0.60)

    /// Atmospheric halo colour per type, used for the rim and the outer glow.
    private static func atmosphere(for type: PlanetType) -> UIColor {
        switch type {
        case .rocky:    return UIColor(red: 0.75, green: 0.68, blue: 0.60, alpha: 1.0)
        case .gasGiant: return UIColor(red: 1.00, green: 0.72, blue: 0.42, alpha: 1.0)
        case .ice:      return UIColor(red: 0.62, green: 0.84, blue: 1.00, alpha: 1.0)
        case .desert:   return UIColor(red: 1.00, green: 0.82, blue: 0.52, alpha: 1.0)
        case .toxic:    return UIColor(red: 0.58, green: 1.00, blue: 0.66, alpha: 1.0)
        }
    }

    /// Renders a lit sphere: surface detail first, then a terminator that falls
    /// to near-black, then a thin crescent of rim light on the dark limb. That
    /// last arc is what actually sells "sphere in sunlight" rather than "circle".
    private static func createPlanetTexture(radius: CGFloat, type: PlanetType) -> SKTexture {
        // Render with padding so the atmospheric glow isn't clipped at the edge.
        let pad = radius * 0.28
        let canvas = CGSize(width: (radius + pad) * 2, height: (radius + pad) * 2)
        let centre = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let disc = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)

        let planetColor = type.colors.randomElement() ?? type.colors.first ?? UIColor.gray
        let atmo = atmosphere(for: type)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // Light position on the disc, from the shared direction.
        let lightPoint = CGPoint(
            x: centre.x + lightDirection.dx * radius * 0.62,
            y: centre.y + lightDirection.dy * radius * 0.62
        )

        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false

        return SKTexture(image: UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
            let context = ctx.cgContext

            // --- Outer atmospheric glow (outside the disc) ---
            let glowStops: [(CGFloat, CGFloat)] = [
                (0.0, 0.0), (0.74, 0.0), (0.79, 0.13), (0.87, 0.05), (1.0, 0.0)
            ]
            if let glow = CGGradient(
                colorsSpace: colorSpace,
                colors: glowStops.map { atmo.withAlphaComponent($0.1).cgColor } as CFArray,
                locations: glowStops.map { $0.0 }
            ) {
                context.drawRadialGradient(
                    glow,
                    startCenter: centre, startRadius: 0,
                    endCenter: centre, endRadius: radius + pad,
                    options: []
                )
            }

            context.saveGState()
            context.addEllipse(in: disc)
            context.clip()

            // --- Base surface ---
            context.setFillColor(planetColor.cgColor)
            context.fill(disc)

            // --- Surface detail, drawn before shading so the light affects it ---
            switch type {
            case .gasGiant, .toxic:
                // Latitude bands.
                let bandCount = Int.random(in: 5...8)
                for i in 0..<bandCount {
                    let t = CGFloat(i) / CGFloat(bandCount)
                    let bandHeight = radius * CGFloat.random(in: 0.10...0.22)
                    let y = disc.minY + t * disc.height
                    let shade = Bool.random()
                        ? planetColor.lighter(by: CGFloat.random(in: 0.05...0.13))
                        : planetColor.darker(by: CGFloat.random(in: 0.05...0.13))
                    context.setFillColor((shade ?? planetColor).withAlphaComponent(0.75).cgColor)
                    context.fill(CGRect(x: disc.minX, y: y, width: disc.width, height: bandHeight))
                }
            case .rocky, .desert, .ice:
                // Craters: a dark bowl with a lit lip on the sun-facing side.
                let craterCount = Int.random(in: 5...9)
                for _ in 0..<craterCount {
                    let cr = radius * CGFloat.random(in: 0.07...0.17)
                    let angle = CGFloat.random(in: 0...(.pi * 2))
                    let dist = CGFloat.random(in: 0...(radius * 0.78))
                    let cx = centre.x + cos(angle) * dist
                    let cy = centre.y + sin(angle) * dist

                    context.setFillColor((planetColor.darker(by: 0.12) ?? planetColor).withAlphaComponent(0.55).cgColor)
                    context.fillEllipse(in: CGRect(x: cx - cr, y: cy - cr, width: cr * 2, height: cr * 2))

                    context.setFillColor((planetColor.lighter(by: 0.14) ?? planetColor).withAlphaComponent(0.4).cgColor)
                    context.fillEllipse(in: CGRect(
                        x: cx - cr + lightDirection.dx * cr * 0.32,
                        y: cy - cr + lightDirection.dy * cr * 0.32,
                        width: cr * 1.7, height: cr * 1.7
                    ))
                }
            }

            // --- Terminator: lit side to deep shadow ---
            // Tuned so roughly half the disc stays clearly lit: a background
            // planet that falls to black just reads as a hole in the starfield.
            let lit = planetColor.lighter(by: 0.38) ?? planetColor
            let shadow = UIColor(red: 0.02, green: 0.025, blue: 0.06, alpha: 1.0)
            let shadeStops: [(CGFloat, UIColor)] = [
                (0.0,  lit.withAlphaComponent(0.62)),
                (0.24, lit.withAlphaComponent(0.18)),
                (0.42, planetColor.withAlphaComponent(0.0)),
                (0.70, shadow.withAlphaComponent(0.30)),
                (0.90, shadow.withAlphaComponent(0.60)),
                (1.0,  shadow.withAlphaComponent(0.74))
            ]
            if let shading = CGGradient(
                colorsSpace: colorSpace,
                colors: shadeStops.map { $0.1.cgColor } as CFArray,
                locations: shadeStops.map { $0.0 }
            ) {
                context.drawRadialGradient(
                    shading,
                    startCenter: lightPoint, startRadius: 0,
                    endCenter: lightPoint, endRadius: radius * 1.75,
                    options: [.drawsAfterEndLocation]
                )
            }

            // --- Crescent rim light on the shaded limb ---
            // Drawn as an arc over just the dark limb. (Stroking the full circle
            // and erasing the lit half would take the planet's lit side with it.)
            let darkLimbAngle = atan2(-lightDirection.dy, -lightDirection.dx)
            let rimInset = radius * 0.035
            let rimRadius = radius - rimInset
            context.setLineWidth(max(1.3, radius * 0.06))
            context.setLineCap(.round)
            context.setStrokeColor(atmo.withAlphaComponent(0.55).cgColor)
            context.beginPath()
            context.addArc(
                center: centre,
                radius: rimRadius,
                startAngle: darkLimbAngle - .pi * 0.42,
                endAngle: darkLimbAngle + .pi * 0.42,
                clockwise: false
            )
            context.strokePath()

            // --- Specular sheen where the light hits square on ---
            let sheenStops: [(CGFloat, CGFloat)] = [(0.0, 0.20), (0.55, 0.06), (1.0, 0.0)]
            if let sheen = CGGradient(
                colorsSpace: colorSpace,
                colors: sheenStops.map { UIColor.white.withAlphaComponent($0.1).cgColor } as CFArray,
                locations: sheenStops.map { $0.0 }
            ) {
                context.drawRadialGradient(
                    sheen,
                    startCenter: lightPoint, startRadius: 0,
                    endCenter: lightPoint, endRadius: radius * 0.85,
                    options: []
                )
            }

            context.restoreGState()
        })
    }

    // Creates a planet
    static func createPlanet(for scene: SKScene) -> SKSpriteNode {
        let type = PlanetType.random()
        let radius = CGFloat.random(in: 25...70) // Smaller, more realistic size
        let texture = createPlanetTexture(radius: radius, type: type)

        let planet = SKSpriteNode(texture: texture)
        // The texture is padded for the atmospheric glow, so size to the texture
        // rather than to the disc or the halo gets squashed into the body.
        let pad = radius * 0.28
        planet.size = CGSize(width: (radius + pad) * 2, height: (radius + pad) * 2)
        planet.alpha = 0.72
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

        // Deliberately not rotated: the lighting and terminator are baked into
        // the texture, so spinning the sprite would spin the sun with it.

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

        // Periodic generation of new planets.
        //
        // [weak scene, weak parent]: this repeats forever on `parent`, so strong
        // captures would form parent -> action -> closure -> parent and additionally
        // pin the whole scene. GameScene.willMove() happens to clear this one via an
        // explicit gameContentNode.removeAllActions(), but the action must not depend
        // on that to stay collectable.
        let spawnAction = SKAction.run { [weak scene, weak parent] in
            guard let scene = scene, let parent = parent else { return }
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
