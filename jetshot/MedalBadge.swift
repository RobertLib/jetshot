//
//  MedalBadge.swift
//  jetshot
//

import SpriteKit

/// How a medal looks, wherever it is shown: the full badge on the results panel and the
/// level intro, and the small pip on a level-select tile.
///
/// Each medal has its own colour and glyph so the three read apart at a glance — and
/// none of the colours is the stars' gold, which belongs to the coin rating.
enum MedalBadge {

    static func color(for medal: MedalSet) -> UIColor {
        switch medal {
        case .untouched: return UIColor(red: 0.35, green: 0.9, blue: 1.0, alpha: 1.0)
        case .chain: return UIColor(red: 0.85, green: 0.45, blue: 1.0, alpha: 1.0)
        default: return UIColor(red: 1.0, green: 0.55, blue: 0.25, alpha: 1.0)
        }
    }

    /// The medal's name as the player reads it, with this level's numbers in it.
    static func label(for medal: MedalSet, level: Int) -> String {
        switch medal {
        case .untouched: return L10n.Medal.untouched
        case .chain: return L10n.Medal.chain(MedalRules.chainTargetMultiplier(forLevel: level))
        default: return L10n.Medal.hunter(Int((MedalRules.hunterFraction * 100).rounded()))
        }
    }

    private static let locked = UIColor(red: 0.32, green: 0.34, blue: 0.42, alpha: 1.0)

    /// A hexagonal badge with the medal's glyph, lit when earned and a dim outline when
    /// not. `radius` is the hexagon's circumradius.
    ///
    /// `glow: false` leaves out the halo, for layouts that measure their contents: the
    /// halo is twice the badge's size and would be counted as part of it.
    static func badge(for medal: MedalSet, earned: Bool, radius: CGFloat, level: Int, glow: Bool = true) -> SKNode {
        let node = SKNode()
        let tint = earned ? color(for: medal) : locked

        if earned && glow {
            let glow = NeonFX.radialGlow(radius: radius * 2.0, color: tint)
            glow.alpha = 0.45
            glow.zPosition = -2
            glow.name = "medalGlow"
            node.addChild(glow)
        }

        let hexagon = SKShapeNode(path: hexagonPath(radius: radius))
        hexagon.fillColor = earned ? tint.withAlphaComponent(0.22) : UIColor(white: 0, alpha: 0.35)
        hexagon.strokeColor = tint.withAlphaComponent(earned ? 1.0 : 0.7)
        hexagon.lineWidth = earned ? 2 : 1.4
        node.addChild(hexagon)

        let glyph = glyphNode(for: medal, radius: radius * 0.5, level: level)
        glyph.alpha = earned ? 1.0 : 0.55
        glyph.zPosition = 1
        node.addChild(glyph)

        if let shape = glyph as? SKShapeNode {
            shape.strokeColor = earned ? .white : tint
        } else if let text = glyph as? SKLabelNode {
            text.fontColor = earned ? .white : tint
        }
        return node
    }

    /// A small diamond for a level-select tile: filled in the medal's colour when held,
    /// a faint outline when not.
    static func pip(for medal: MedalSet, earned: Bool) -> SKShapeNode {
        let path = CGMutablePath()
        let r: CGFloat = 4
        path.move(to: CGPoint(x: 0, y: r))
        path.addLine(to: CGPoint(x: r * 0.8, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -r))
        path.addLine(to: CGPoint(x: -r * 0.8, y: 0))
        path.closeSubpath()
        let pip = SKShapeNode(path: path)
        let tint = color(for: medal)
        pip.fillColor = earned ? tint : .clear
        pip.strokeColor = earned ? UIColor.white.withAlphaComponent(0.8) : tint.withAlphaComponent(0.45)
        pip.lineWidth = 1
        return pip
    }

    // MARK: - Glyphs

    private static func glyphNode(for medal: MedalSet, radius r: CGFloat, level: Int) -> SKNode {
        switch medal {
        case .untouched:
            // A shield: flat top, pointed foot.
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -r * 0.85, y: r * 0.8))
            path.addLine(to: CGPoint(x: r * 0.85, y: r * 0.8))
            path.addLine(to: CGPoint(x: r * 0.85, y: 0))
            path.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: r * 0.7, y: -r * 0.7))
            path.addQuadCurve(to: CGPoint(x: -r * 0.85, y: 0), control: CGPoint(x: -r * 0.7, y: -r * 0.7))
            path.closeSubpath()
            let shield = SKShapeNode(path: path)
            shield.fillColor = .clear
            shield.lineWidth = 2
            shield.lineJoin = .round
            return shield

        case .chain:
            let text = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
            text.text = "x\(MedalRules.chainTargetMultiplier(forLevel: level))"
            text.fontSize = r * 1.6
            text.verticalAlignmentMode = .center
            text.horizontalAlignmentMode = .center
            return text

        default:
            // A crosshair.
            let path = CGMutablePath()
            path.addEllipse(in: CGRect(x: -r * 0.62, y: -r * 0.62, width: r * 1.24, height: r * 1.24))
            for angle in stride(from: 0, to: CGFloat.pi * 2, by: .pi / 2) {
                path.move(to: CGPoint(x: cos(angle) * r * 0.35, y: sin(angle) * r * 0.35))
                path.addLine(to: CGPoint(x: cos(angle) * r * 1.05, y: sin(angle) * r * 1.05))
            }
            let crosshair = SKShapeNode(path: path)
            crosshair.fillColor = .clear
            crosshair.lineWidth = 2
            crosshair.lineCap = .round
            return crosshair
        }
    }

    private static func hexagonPath(radius r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3 + .pi / 6
            let point = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
