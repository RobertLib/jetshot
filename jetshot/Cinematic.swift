//
//  Cinematic.swift
//  jetshot
//
//  The story films' frame and type, for the moments the game itself stops to say
//  something: a level's title card, a boss's warning.
//
//  Everything here is built from SKActions on the returned nodes, so it runs on
//  whatever clock it is parented to — the level card's node, which the debug harness
//  fast-forwards by raising its speed, or `gameContentNode`, which a pause freezes.
//

import SpriteKit

enum Cinematic {

    // MARK: - Frame

    /// Black bars that close over the top and bottom of the screen, hold, and open.
    static func letterbox(size: CGSize, depth: CGFloat, delay: TimeInterval = 0,
                          hold: TimeInterval, close: TimeInterval = 0.45, open: TimeInterval = 0.4) -> SKNode {
        let node = SKNode()
        for top in [true, false] {
            let bar = SKSpriteNode(color: .black, size: CGSize(width: size.width + 40, height: depth))
            bar.anchorPoint = CGPoint(x: 0.5, y: top ? 0 : 1)
            let outside = CGPoint(x: size.width / 2, y: top ? size.height : 0)
            let inside = CGPoint(x: size.width / 2, y: top ? size.height - depth : depth)
            bar.position = outside
            let closing = SKAction.move(to: inside, duration: close)
            closing.timingMode = .easeOut
            let opening = SKAction.move(to: outside, duration: open)
            opening.timingMode = .easeIn
            bar.run(.sequence([.wait(forDuration: delay), closing, .wait(forDuration: hold), opening]))
            node.addChild(bar)

            // The hairline on the bar's inner edge, the frame of the picture.
            let edge = SKSpriteNode(color: StoryPalette.cyan, size: CGSize(width: size.width, height: 1))
            edge.alpha = 0.22
            edge.blendMode = .add
            edge.position = CGPoint(x: 0, y: top ? 0 : 0)
            bar.addChild(edge)
        }
        return node
    }

    /// The viewfinder's corner brackets, inset in `rect`.
    static func viewfinder(in rect: CGRect, color: UIColor, arm: CGFloat = 16, inset: CGFloat = 14) -> SKNode {
        let node = SKNode()
        let r = rect.insetBy(dx: inset, dy: inset)
        for (corner, dx, dy) in [(CGPoint(x: r.minX, y: r.minY), 1, 1), (CGPoint(x: r.maxX, y: r.minY), -1, 1),
                                 (CGPoint(x: r.minX, y: r.maxY), 1, -1), (CGPoint(x: r.maxX, y: r.maxY), -1, -1)]
            as [(CGPoint, CGFloat, CGFloat)] {
            node.addChild(LightSprite.tube(from: corner, to: CGPoint(x: corner.x + arm * dx, y: corner.y), width: 1.1, color: color))
            node.addChild(LightSprite.tube(from: corner, to: CGPoint(x: corner.x, y: corner.y + arm * dy), width: 1.1, color: color))
        }
        return node
    }

    /// A soft dark pool behind text, so it reads over a busy picture without a box.
    static func shade(size: CGSize, alpha: CGFloat = 0.6) -> SKSpriteNode {
        let sprite = SKSpriteNode(texture: NeonFX.radialGlow(radius: 1, color: .black, softness: 0.8, additive: false).texture,
                                  size: size)
        sprite.alpha = alpha
        return sprite
    }

    // MARK: - Type

    private static func monoFont(_ size: CGFloat) -> UIFont {
        UIFont(name: UITheme.Typography.fontNumeric, size: size) ?? UIFont.monospacedSystemFont(ofSize: size, weight: .bold)
    }

    private static func displayFont(_ size: CGFloat) -> UIFont {
        UIFont(name: UITheme.Typography.fontBold, size: size) ?? UIFont.systemFont(ofSize: size, weight: .heavy)
    }

    /// A line of monospaced type that writes itself out, a block cursor at its head,
    /// the way the films tag what they show.
    /// Shrinks to fit `maxWidth` once fully typed, so it never types itself off screen.
    static func typewriter(_ text: String, fontSize: CGFloat, color: UIColor, tracking: CGFloat = 3,
                           delay: TimeInterval = 0, duration: TimeInterval = 0.6,
                           maxWidth: CGFloat = .greatestFiniteMagnitude) -> SKLabelNode {
        let label = SKLabelNode()
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.blendMode = .add
        var size = fontSize
        func width(at size: CGFloat) -> CGFloat {
            NSAttributedString(string: text, attributes: [.font: monoFont(size), .kern: tracking]).size().width
        }
        while width(at: size) > maxWidth && size > 8 { size -= 1 }
        let font = monoFont(size)
        // Takes the label rather than capturing it: the actions below live on the
        // label, and a closure holding it strongly would never let it go.
        func show(_ target: SKLabelNode, _ count: Int, cursor: Bool) {
            let shown = String(text.prefix(count)) + (cursor ? "▌" : (count < text.count ? " " : ""))
            target.attributedText = NSAttributedString(string: shown, attributes: [
                .font: font, .foregroundColor: color, .kern: tracking
            ])
        }
        show(label, 0, cursor: false)
        let total = text.count
        let typing = SKAction.customAction(withDuration: duration) { node, elapsed in
            guard let target = node as? SKLabelNode else { return }
            let t = CGFloat(elapsed) / CGFloat(max(0.01, duration))
            let count = min(total, Int(CGFloat(total) * t + 0.5))
            let cursorOn = Int(elapsed * 14) % 2 == 0
            show(target, count, cursor: count < total && cursorOn)
        }
        let finish = SKAction.customAction(withDuration: 0) { node, _ in
            guard let target = node as? SKLabelNode else { return }
            show(target, total, cursor: false)
        }
        label.run(.sequence([.wait(forDuration: delay), typing, finish]))
        return label
    }

    /// Display lettering, tracked out, with a real blurred bloom behind it — the
    /// films' title treatment. Shrinks to fit `maxWidth` on one line.
    static func title(_ text: String, fontSize: CGFloat, color: UIColor, glow: UIColor,
                      tracking: CGFloat, maxWidth: CGFloat, minimumSize: CGFloat = 24) -> SKLabelNode {
        let label = SKLabelNode()
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        var size = fontSize
        func lettering(_ c: UIColor) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [.font: displayFont(size), .foregroundColor: c,
                                                          .kern: tracking * size / fontSize])
        }
        var main = lettering(color)
        while main.size().width > maxWidth && size > minimumSize {
            size -= 2
            main = lettering(color)
        }
        label.attributedText = main
        StoryOverlay.addBloom(to: label, glow: lettering(glow), blur: 16, intensity: 0.85)
        return label
    }

    /// A hairline that draws out from its centre.
    static func rule(width: CGFloat, color: UIColor, delay: TimeInterval, duration: TimeInterval = 0.6) -> SKSpriteNode {
        let rule = SKSpriteNode(color: color, size: CGSize(width: width, height: 1))
        rule.blendMode = .add
        rule.xScale = 0.01
        let draw = SKAction.scaleX(to: 1, duration: duration)
        draw.timingMode = .easeOut
        rule.run(.sequence([.wait(forDuration: delay), draw]))
        return rule
    }

    /// Lock-on brackets closing from `from` to `to` half-size around a point.
    static func lockOn(at point: CGPoint, from: CGFloat, to: CGFloat, color: UIColor, duration: TimeInterval) -> SKNode {
        let node = SKNode()
        node.position = point
        let arm: CGFloat = 14
        for (sx, sy) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] as [(CGFloat, CGFloat)] {
            let corner = SKNode()
            corner.position = CGPoint(x: from * sx, y: from * sy)
            corner.addChild(LightSprite.tube(from: .zero, to: CGPoint(x: -arm * sx, y: 0), width: 1.4, color: color))
            corner.addChild(LightSprite.tube(from: .zero, to: CGPoint(x: 0, y: -arm * sy), width: 1.4, color: color))
            let close = SKAction.move(to: CGPoint(x: to * sx, y: to * sy), duration: duration)
            close.timingMode = .easeOut
            corner.run(close)
            node.addChild(corner)
        }
        return node
    }
}
