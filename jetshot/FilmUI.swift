//
//  FilmUI.swift
//  jetshot
//
//  The films' frame and lettering, for every screen around the game itself: the menu,
//  the level grid, the results, and the modals.
//
//  The story films and the in-game title cards set a look — the picture letterboxed,
//  viewfinder corners, monospaced tags that type themselves out, tracked display type
//  with a real bloom behind it, and every line drawn as light. The screens between the
//  levels were still rounded, filled panels with chunky pill buttons, which read as a
//  different game. This is the vocabulary they are rebuilt from instead, so a player
//  goes from the menu into the film into a level and out to the results without the
//  picture ever changing style.
//

import SpriteKit

enum FilmUI {

    // MARK: - Colour

    /// The ways back and the quiet options — LEVELS, MENU, SETTINGS — and anything
    /// locked: a cool grey-blue, so they never read as the way on. Everything else is
    /// lit in the films' own palette (`StoryPalette`): cyan to go on, gold for reward,
    /// red for loss and anything destructive.
    static let neutral = UIColor(red: 0.52, green: 0.6, blue: 0.74, alpha: 1)

    /// How much larger the UI is drawn on a wide screen — the films' own `typeScale`,
    /// so a menu on an iPad keeps the weight the same menu has on a phone instead of
    /// shrinking to a strip in the middle of the glass. 1 on every phone.
    static func uiScale(for size: CGSize) -> CGFloat {
        min(1.45, max(1, size.width / 430))
    }

    /// Dark glass: what sits inside a frame, so the world behind stays visible but
    /// never competes with the type in front of it.
    static let glass = UIColor(red: 0.006, green: 0.012, blue: 0.035, alpha: 1)

    // MARK: - Type

    static func font(_ name: String, _ size: CGFloat) -> UIFont {
        UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: .heavy)
    }

    /// Text set with letter-spacing, the films' way with every line of type.
    ///
    /// The tracking is left off the final character. Kerning is space added *after* a
    /// glyph, so applied to all of them it hangs an invisible gap off the end of the
    /// line — and a centred label then sits half that gap left of centre, which at the
    /// title's 10pt of tracking is visibly off.
    static func tracked(_ text: String, font name: String, size: CGFloat, color: UIColor,
                        tracking: CGFloat) -> NSAttributedString {
        let string = NSMutableAttributedString(string: text, attributes: [
            .font: font(name, size),
            .foregroundColor: color,
            .kern: tracking
        ])
        let length = (text as NSString).length
        if length > 0 {
            string.addAttribute(.kern, value: 0, range: NSRange(location: length - 1, length: 1))
        }
        return string
    }

    /// Sets `label` to tracked text, keeping its plain font properties in step.
    ///
    /// SpriteKit draws the attributed string, but `fontName` and `fontSize` are what
    /// `UITheme.capBand(of:)` and the layout tests read back, so they are kept true.
    static func set(_ label: SKLabelNode, _ text: String, font name: String, size: CGFloat,
                    color: UIColor, tracking: CGFloat) {
        label.fontName = name
        label.fontSize = size
        label.fontColor = color
        label.attributedText = tracked(text, font: name, size: size, color: color, tracking: tracking)
    }

    /// One line of tracked type, centred on its origin, given up in point size until it
    /// fits `maxWidth` — translations do not respect a width chosen against English.
    static func label(_ text: String, font name: String = UITheme.Typography.fontBold, size: CGFloat,
                      color: UIColor, tracking: CGFloat = 0,
                      maxWidth: CGFloat = .greatestFiniteMagnitude, minimumSize: CGFloat = 9) -> SKLabelNode {
        let label = SKLabelNode()
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        var pointSize = size
        set(label, text, font: name, size: pointSize, color: color, tracking: tracking)
        // Width is linear in point size; the loop absorbs the rounding, and the clamp
        // bounds it if the floor still does not fit.
        for _ in 0..<6 where label.frame.width > maxWidth && pointSize > minimumSize {
            let ratio = maxWidth / max(1, label.frame.width)
            pointSize = max(minimumSize, min(pointSize - 0.5, (pointSize * ratio).rounded(.down)))
            set(label, text, font: name, size: pointSize, color: color,
                tracking: tracking * pointSize / size)
        }
        return label
    }

    /// The films' tag type: monospaced, tracked, for anything that reads as data.
    static func mono(_ text: String, size: CGFloat, color: UIColor, tracking: CGFloat = 2,
                     maxWidth: CGFloat = .greatestFiniteMagnitude) -> SKLabelNode {
        label(text, font: UITheme.Typography.fontNumeric, size: size, color: color,
              tracking: tracking, maxWidth: maxWidth, minimumSize: 8)
    }

    /// Display lettering, tracked out, with a genuine blurred bloom behind it — the
    /// treatment the films give a title and the level card gives a level.
    static func title(_ text: String, size: CGFloat, color: UIColor, glow: UIColor, tracking: CGFloat,
                      maxWidth: CGFloat, minimumSize: CGFloat = 18, bloom: CGFloat = 0.85) -> SKLabelNode {
        let label = self.label(text, size: size, color: color, tracking: tracking,
                               maxWidth: maxWidth, minimumSize: minimumSize)
        let glowText = tracked(text, font: UITheme.Typography.fontBold, size: label.fontSize, color: glow,
                               tracking: tracking * label.fontSize / size)
        StoryOverlay.addBloom(to: label, glow: glowText, blur: 14, intensity: bloom)
        return label
    }

    // MARK: - Light

    /// A line of light — the films' light tube — between two points.
    static func tube(_ a: CGPoint, _ b: CGPoint, width: CGFloat = 1.3, color: UIColor) -> SKSpriteNode {
        LightSprite.tube(from: a, to: b, width: width, color: color)
    }

    /// Four corner brackets round a `size` box centred on the origin, added straight to
    /// `node` and returned.
    ///
    /// Added as direct children on purpose: the pause menu's touch dispatch matches a
    /// node's own name or its parent's, so decoration one level down still resolves to
    /// the button it belongs to, and two levels down would not.
    @discardableResult
    static func addBrackets(to node: SKNode, size: CGSize, arm: CGFloat, color: UIColor,
                            width: CGFloat = 1.3, inset: CGFloat = 0) -> [SKSpriteNode] {
        let hx = size.width / 2 - inset, hy = size.height / 2 - inset
        var tubes: [SKSpriteNode] = []
        for (sx, sy) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] as [(CGFloat, CGFloat)] {
            let corner = CGPoint(x: hx * sx, y: hy * sy)
            tubes.append(tube(corner, CGPoint(x: corner.x - arm * sx, y: corner.y), width: width, color: color))
            tubes.append(tube(corner, CGPoint(x: corner.x, y: corner.y - arm * sy), width: width, color: color))
        }
        tubes.forEach(node.addChild)
        return tubes
    }

    /// A one-point hairline, additive, `width` long and centred on its origin.
    static func hairline(width: CGFloat, color: UIColor, alpha: CGFloat) -> SKSpriteNode {
        let rule = SKSpriteNode(color: color, size: CGSize(width: width, height: 1))
        rule.blendMode = .add
        rule.alpha = alpha
        return rule
    }

    /// A hairline that draws itself out from the centre, the way the films underline a
    /// title.
    static func drawnRule(width: CGFloat, color: UIColor, alpha: CGFloat = 0.8,
                          delay: TimeInterval, duration: TimeInterval = 0.6) -> SKSpriteNode {
        let rule = hairline(width: width, color: color, alpha: alpha)
        rule.xScale = 0.01
        let draw = SKAction.scaleX(to: 1, duration: duration)
        draw.timingMode = .easeOut
        rule.run(.sequence([.wait(forDuration: delay), draw]))
        return rule
    }

    /// The five points of a star, outer and inner, from the top clockwise.
    static func starPoints(radius: CGFloat, inner ratio: CGFloat = 0.45) -> [CGPoint] {
        (0..<10).map { i in
            let angle = CGFloat(i) * .pi / 5 + .pi / 2
            let r = i % 2 == 0 ? radius : radius * ratio
            return CGPoint(x: cos(angle) * r, y: sin(angle) * r)
        }
    }

    static func starPath(radius: CGFloat, inner ratio: CGFloat = 0.45) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: starPoints(radius: radius, inner: ratio))
        path.closeSubpath()
        return path
    }

    /// A star drawn in light: an outline of tubes, filled and glowing when `lit`, a dim
    /// outline when not. Used where a star is large enough for the line to read; the
    /// level tiles' small ones are plain shapes.
    static func lightStar(radius: CGFloat, color: UIColor, lit: Bool) -> SKNode {
        let node = SKNode()
        if lit {
            let glow = NeonFX.radialGlow(radius: radius * 2.2, color: color)
            glow.alpha = 0.4
            glow.zPosition = -2
            glow.name = "starGlow"
            node.addChild(glow)

            let fill = SKShapeNode(path: starPath(radius: radius * 0.94))
            fill.fillColor = color.withAlphaComponent(0.55)
            fill.strokeColor = .clear
            fill.zPosition = -1
            node.addChild(fill)
        }
        let points = starPoints(radius: radius)
        let lineColor = lit ? StoryPalette.mix(color, .white, 0.35) : UIColor(red: 0.42, green: 0.48, blue: 0.6, alpha: 1)
        for (index, point) in points.enumerated() {
            let next = points[(index + 1) % points.count]
            let segment = tube(point, next, width: lit ? 1.5 : 1.1, color: lineColor)
            segment.alpha = lit ? 1 : 0.55
            node.addChild(segment)
        }
        return node
    }

    /// A chevron of light, its tip on the origin.
    static func chevron(pointingLeft: Bool, size: CGFloat, color: UIColor, width: CGFloat = 1.6) -> SKNode {
        let node = SKNode()
        let back = pointingLeft ? size * 0.6 : -size * 0.6
        node.addChild(tube(.zero, CGPoint(x: back, y: size), width: width, color: color))
        node.addChild(tube(.zero, CGPoint(x: back, y: -size), width: width, color: color))
        return node
    }

    /// A padlock in line, for a level that is not open yet. Replaces the 🔒 emoji, which
    /// was the one full-colour bitmap in a picture drawn entirely in light.
    static func padlock(height: CGFloat, color: UIColor) -> SKShapeNode {
        let w = height * 0.78, body = height * 0.56
        let path = CGMutablePath()
        path.addRect(CGRect(x: -w / 2, y: -height / 2, width: w, height: body))
        let shackle = w * 0.32
        let top = -height / 2 + body
        path.move(to: CGPoint(x: -shackle, y: top))
        path.addLine(to: CGPoint(x: -shackle, y: top + (height - body - shackle)))
        path.addArc(center: CGPoint(x: 0, y: top + (height - body - shackle)), radius: shackle,
                    startAngle: .pi, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: shackle, y: top))
        let lock = SKShapeNode(path: path)
        lock.strokeColor = color
        lock.fillColor = .clear
        lock.lineWidth = 1.2
        lock.lineJoin = .round
        return lock
    }

    // MARK: - Frame

    /// The letterbox the films are shot in, held on a screen: black bars with a
    /// hairline on their inner edge, viewfinder corners in the picture, and the small
    /// monospaced furniture the films print just above it.
    final class Letterbox: SKNode {

        /// The picture between the bars, in the parent's coordinates.
        let picture: CGRect
        private let accent: UIColor
        private let sceneSize: CGSize
        private var furniture: [SKNode] = []

        /// - Parameters:
        ///   - top, bottom: bar depths. Callers fold the safe area in, so the Dynamic
        ///     Island and the home indicator sit in black rather than over the picture.
        ///   - closing: run the bars in from off screen, as the films' opening does.
        init(size: CGSize, top: CGFloat, bottom: CGFloat, accent: UIColor = StoryPalette.cyan,
             corners: Bool = true, closing: Bool = true) {
            self.picture = CGRect(x: 0, y: bottom, width: size.width, height: size.height - top - bottom)
            self.accent = accent
            self.sceneSize = size
            super.init()
            buildBars(top: top, bottom: bottom, closing: closing)
            if corners { buildCorners(closing: closing) }
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func buildBars(top: CGFloat, bottom: CGFloat, closing: Bool) {
            for isTop in [true, false] {
                let depth = isTop ? top : bottom
                let bar = SKSpriteNode(color: .black, size: CGSize(width: sceneSize.width + 40, height: depth + 2))
                bar.anchorPoint = CGPoint(x: 0.5, y: isTop ? 0 : 1)
                let inside = CGPoint(x: sceneSize.width / 2, y: isTop ? sceneSize.height - depth : depth)
                let outside = CGPoint(x: sceneSize.width / 2, y: isTop ? sceneSize.height : 0)
                bar.position = closing ? outside : inside
                if closing {
                    let close = SKAction.move(to: inside, duration: 0.5)
                    close.timingMode = .easeOut
                    bar.run(close)
                }
                addChild(bar)

                // The frame of the picture: a hairline along the bar's inner edge.
                let edge = SKSpriteNode(color: accent, size: CGSize(width: sceneSize.width, height: 1))
                edge.alpha = 0.24
                edge.blendMode = .add
                bar.addChild(edge)
            }
        }

        private func buildCorners(closing: Bool) {
            let inset: CGFloat = 12, arm: CGFloat = 16
            let r = picture.insetBy(dx: inset, dy: inset)
            let path = CGMutablePath()
            for (corner, dx, dy) in [(CGPoint(x: r.minX, y: r.minY), 1, 1), (CGPoint(x: r.maxX, y: r.minY), -1, 1),
                                     (CGPoint(x: r.minX, y: r.maxY), 1, -1), (CGPoint(x: r.maxX, y: r.maxY), -1, -1)]
                as [(CGPoint, CGFloat, CGFloat)] {
                path.move(to: CGPoint(x: corner.x + arm * dx, y: corner.y))
                path.addLine(to: corner)
                path.addLine(to: CGPoint(x: corner.x, y: corner.y + arm * dy))
            }
            let corners = SKShapeNode(path: path)
            corners.strokeColor = accent.withAlphaComponent(0.4)
            corners.lineWidth = 1
            corners.zPosition = 1
            corners.name = "viewfinder"
            if closing {
                corners.alpha = 0
                corners.run(.sequence([.wait(forDuration: 0.35), .fadeIn(withDuration: 0.4)]))
            }
            addChild(corners)
        }

        /// Monospaced captions just above the picture, the way the films print the
        /// timecode and the shot counter. Returns the left and right labels so callers
        /// can keep them current.
        @discardableResult
        func addFurniture(left: String?, right: String?, recording: Bool = false) -> (left: SKLabelNode?, right: SKLabelNode?) {
            furniture.forEach { $0.removeFromParent() }
            furniture.removeAll()

            let inset: CGFloat = 14
            let y = picture.maxY + 11
            let color = UITheme.Colors.textSecondary.withAlphaComponent(0.7)
            var leftLabel: SKLabelNode?
            var rightLabel: SKLabelNode?

            if let left = left {
                var x = inset
                if recording {
                    let dot = SKShapeNode(circleOfRadius: 3)
                    dot.fillColor = StoryPalette.red
                    dot.strokeColor = .clear
                    dot.position = CGPoint(x: x + 3, y: y)
                    dot.zPosition = 2
                    dot.run(.repeatForever(.sequence([
                        .wait(forDuration: 0.8), .fadeAlpha(to: 0.15, duration: 0.05),
                        .wait(forDuration: 0.45), .fadeAlpha(to: 1, duration: 0.05)
                    ])))
                    addChild(dot)
                    furniture.append(dot)
                    x += 12
                }
                let label = FilmUI.mono(left, size: 10, color: color, tracking: 1.5,
                                        maxWidth: sceneSize.width / 2 - x - 8)
                label.horizontalAlignmentMode = .left
                label.position = CGPoint(x: x, y: y)
                label.zPosition = 2
                addChild(label)
                furniture.append(label)
                leftLabel = label
            }

            if let right = right {
                let label = FilmUI.mono(right, size: 10, color: color, tracking: 1.5,
                                        maxWidth: sceneSize.width / 2 - inset - 8)
                label.horizontalAlignmentMode = .right
                label.position = CGPoint(x: sceneSize.width - inset, y: y)
                label.zPosition = 2
                addChild(label)
                furniture.append(label)
                rightLabel = label
            }

            for node in furniture {
                node.alpha = 0
                node.run(.sequence([.wait(forDuration: 0.4), .fadeIn(withDuration: 0.5)]))
            }
            return (leftLabel, rightLabel)
        }

        /// Bar depths for a screen: deep enough to swallow the safe area with a margin,
        /// and never so thin that they stop reading as a frame.
        static func depths(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
            let top = max(safeTop + 26, size.height * 0.075).rounded()
            let bottom = max(safeBottom + 22, size.height * 0.055).rounded()
            return (top, bottom)
        }

        /// Bar depths over a run in progress: deep enough to close over the HUD's top
        /// row and the instruments along the bottom, so a frame held over the game cuts
        /// cleanly between them instead of through the middle of the lives and the
        /// Overdrive gauge.
        static func depthsOverGameplay(size: CGSize, view: SKView?) -> (top: CGFloat, bottom: CGFloat) {
            let screen = depths(size: size,
                                safeTop: GameConfiguration.safeAreaTop(in: view),
                                safeBottom: GameConfiguration.safeAreaBottom(in: view))
            let hudRow = GameConfiguration.topMargin(in: view) + 30
            let gauge = GameScene.overdriveGaugePosition(safeAreaBottom: GameConfiguration.safeAreaBottom(in: view)).y
                + OverdriveSystem.radius + 24
            return (max(screen.top, hudRow).rounded(), max(screen.bottom, gauge).rounded())
        }
    }

    // MARK: - Hit testing

    /// The first node named one of `names` among `node` and its ancestors.
    ///
    /// Every control here is a named root with unnamed decoration under it, sometimes
    /// two levels deep. `atPoint` reports the deepest node under the finger, so the
    /// name has to be looked for upwards from there.
    static func namedAncestor(of node: SKNode?, where matches: (String) -> Bool) -> SKNode? {
        var current = node
        while let candidate = current {
            if let name = candidate.name, matches(name) { return candidate }
            current = candidate.parent
        }
        return nil
    }

    /// The button among `names`, anywhere under `root`, whose own outline contains
    /// `location` (in `root`'s scene's coordinates).
    ///
    /// Measured against each button's path rather than through `nodes(at:)`: anything
    /// soft and glowing hung off a button reaches well past its edge, and asking which
    /// nodes contain a point hands taps on the neighbour to whichever button glows.
    static func button(at location: CGPoint, under root: SKNode, names: [String], slop: CGFloat = 6) -> SKShapeNode? {
        guard let scene = root.scene else { return nil }
        for name in names {
            guard let button = descendant(of: root, named: name),
                  button.alpha > 0.05, !button.isHidden,
                  let bounds = button.path?.boundingBoxOfPath else { continue }
            let local = scene.convert(location, to: button)
            if bounds.insetBy(dx: -slop, dy: -slop).contains(local) { return button }
        }
        return nil
    }

    /// First `SKShapeNode` named `name` below `node`, depth first. Hand-rolled, because
    /// `childNode(withName:)` either stops at immediate children or, with `//`, searches
    /// from the root of the whole tree.
    static func descendant(of node: SKNode, named name: String) -> SKShapeNode? {
        for child in node.children {
            if child.name == name, let shape = child as? SKShapeNode { return shape }
            if let match = descendant(of: child, named: name) { return match }
        }
        return nil
    }

    // MARK: - Leaving a screen

    /// A screen's way out, taken once.
    ///
    /// Every button that leaves a screen used to present the next one from the end of
    /// its press animation, with nothing to stop a second tap doing the same. What did
    /// stop it was an accident: the first transition pauses the outgoing scene
    /// (`SKTransition.pausesOutgoingScene`), which froze the second press animation
    /// before its completion could run — unless both landed in the same frame. ENDLESS
    /// presents on touch-down with no animation at all, so it had not even that, and
    /// SpriteKit keeps routing touches to the outgoing scene for the whole fade.
    ///
    /// So a screen commits to leaving the moment a tap chooses a way out (`take()`),
    /// ignores input from then on (`isTaken`), and `present` refuses to run twice
    /// whoever calls it.
    final class Exit {
        /// Whether a tap has committed the screen to leaving. Input is ignored from here on.
        private(set) var isTaken = false
        private var hasPresented = false

        /// Commits to leaving. False when something already has, and the tap that asked
        /// should be dropped.
        @discardableResult
        func take() -> Bool {
            guard !isTaken else { return false }
            isTaken = true
            return true
        }

        /// Presents the scene `make` builds — handed the view's size — in place of
        /// `scene`, with its scale mode and a fade. Only the first call does anything.
        func present(from scene: SKScene, fade duration: TimeInterval = 0.5,
                     _ make: (CGSize) -> SKScene) {
            guard !hasPresented, let view = scene.view else { return }
            hasPresented = true
            isTaken = true
            let next = make(view.bounds.size)
            next.scaleMode = scene.scaleMode
            view.presentScene(next, transition: SKTransition.fade(withDuration: duration))
        }
    }

    // MARK: - Motion

    /// A number that counts up to `value`, then lights: the bloom only arrives once the
    /// figure has settled, so the eye is pulled to it the moment it is final.
    static func countUp(_ label: SKLabelNode, to value: Int, delay: TimeInterval, duration: TimeInterval,
                        glow: UIColor) {
        label.text = 0.formatted()
        var lastShown = -1
        let count = SKAction.customAction(withDuration: duration) { node, elapsed in
            guard let target = node as? SKLabelNode else { return }
            let t = Float(elapsed) / Float(max(0.01, duration))
            let shown = Int(Double(value) * Double(easeOut(t)))
            if shown != lastShown {
                lastShown = shown
                target.text = shown.formatted()
            }
        }
        let land = SKAction.run { [weak label] in
            guard let label = label else { return }
            label.text = value.formatted()
            NeonFX.addTextBloom(to: label, color: glow, blur: 12, intensity: 0)
            label.childNode(withName: "textBloom")?.run(.fadeAlpha(to: 0.9, duration: 0.25))
        }
        label.run(.sequence([.wait(forDuration: delay), count, land]))
    }

    /// Hard sideways jitter as a line lands — the films' picture resisting.
    static func glitchIn(_ node: SKNode, delay: TimeInterval, amount: CGFloat = 6) -> SKAction {
        let x = node.position.x
        let jitter = SKAction.sequence((0..<6).map { i in
            SKAction.moveTo(x: x + (i % 2 == 0 ? 1 : -1) * amount * CGFloat(6 - i) / 6, duration: 0.04)
        })
        return .sequence([
            .wait(forDuration: delay),
            .group([.fadeIn(withDuration: 0.12), jitter]),
            .moveTo(x: x, duration: 0)
        ])
    }
}
