//
//  ResultsCard.swift
//  jetshot
//

import SpriteKit

/// The column the three results screens — game over, level complete and victory — are
/// built as: a typed tag, an emblem, a tracked title with its hairline, a block of
/// figures, the one action the screen is asking for and a pair of ways out.
///
/// They are the same screen with different words, so they are laid out by the same
/// code, on `UITheme.PanelRhythm`, and framed the same way the level card is: the
/// picture letterboxed, the world still flying behind, and only a soft pool of shade
/// behind the type rather than a box around it.
final class ResultsCard {

    /// What the card's node answers to, for the tests that measure it.
    static let nodeName = "resultsCard"

    let node = SKNode()
    /// The column's width: the primary button's, and the measure every line is fitted to.
    let width: CGFloat

    private var rows: [(nodes: [SKNode], gap: CGFloat, height: CGFloat, reveal: Bool)] = []

    init(sceneWidth: CGFloat) {
        width = min(sceneWidth - 48, UITheme.Dimensions.buttonWidthXLarge + 40, UITheme.Dimensions.columnWidthMax)
        node.name = Self.nodeName
    }

    /// Records a row, top to bottom. `reveal` gives it the shared entrance — a fade and
    /// a short rise into place — for rows that do not run one of their own.
    func add(_ row: SKNode, gapAbove: CGFloat, height: CGFloat, reveal: Bool = true) {
        rows.append(([row], gapAbove, height, reveal))
    }

    /// The primary action, and the pair of ways out underneath it.
    func addButtons(primary: SKShapeNode, pair: (SKShapeNode, SKShapeNode), gapAbove: CGFloat) {
        // Measured on the outlines: a shape's frame counts its stroke as well.
        let outline = { (button: SKShapeNode) in button.path?.boundingBoxOfPath.size ?? button.frame.size }
        add(primary, gapAbove: gapAbove, height: outline(primary).height)
        let offset = (outline(pair.0).width + UITheme.Dimensions.buttonPairGap) / 2
        pair.0.position.x = -offset
        pair.1.position.x = offset
        rows.append(([pair.0, pair.1], UITheme.PanelRhythm.buttonRow, outline(pair.0).height, true))
    }

    /// The width a pair button gets beside its twin under the primary one.
    var pairButtonWidth: CGFloat {
        (primaryButtonWidth - UITheme.Dimensions.buttonPairGap) / 2
    }

    var primaryButtonWidth: CGFloat {
        min(width, UITheme.Dimensions.buttonWidthXLarge)
    }

    /// Places every row and installs the card in `scene`, centred in the picture —
    /// drawn larger on a wide screen, and scaled down if a short one cannot hold it.
    ///
    /// - Parameters:
    ///   - revealFrom: when the first revealed row starts its entrance; each one after
    ///     it follows `revealStep` later.
    ///   - shade: how dark the pool behind the column is — deeper where the world
    ///     behind it is brighter.
    @discardableResult
    func install(in scene: SKScene, accent: UIColor, safeTop: CGFloat, safeBottom: CGFloat,
                 revealFrom: TimeInterval, revealStep: TimeInterval = 0.1,
                 shade shadeAlpha: CGFloat = 0.72) -> FilmUI.Letterbox {
        let size = scene.size
        let depths = FilmUI.Letterbox.depths(size: size, safeTop: safeTop, safeBottom: safeBottom)
        let frame = FilmUI.Letterbox(size: size, top: depths.top, bottom: depths.bottom, accent: accent)
        frame.zPosition = 40
        scene.addChild(frame)

        // Two passes, so the card is sized to what it holds — see `UITheme.PanelStack`.
        var stack = UITheme.PanelStack()
        for row in rows { stack.add(gapAbove: row.gap, height: row.height) }
        let height = stack.height
        stack.start(panelHeight: height)

        var delay = revealFrom
        for row in rows {
            let y = stack.next(gapAbove: row.gap, height: row.height)
            for item in row.nodes {
                item.position.y = y
                if item.parent == nil { node.addChild(item) }
                guard row.reveal else { continue }
                let rise: CGFloat = 8
                item.position.y -= rise
                item.alpha = 0
                let lift = SKAction.moveBy(x: 0, y: rise, duration: 0.35)
                lift.timingMode = .easeOut
                item.run(.sequence([.wait(forDuration: delay), .group([.fadeIn(withDuration: 0.3), lift])]))
            }
            if row.reveal { delay += revealStep }
        }

        let picture = frame.picture
        node.position = CGPoint(x: size.width / 2, y: picture.midY)
        node.setScale(min(FilmUI.uiScale(for: size), (picture.height - 28) / height))
        node.zPosition = 10
        scene.addChild(node)

        // Pools of shade down the column rather than one: a single radial pool is dark
        // only in its middle, and on a tall card the tag and the buttons sit out where
        // it has already faded.
        let scaled = height * node.yScale
        let pools = max(1, Int((scaled / 260).rounded()))
        for index in 0..<pools {
            let shade = Cinematic.shade(size: CGSize(width: size.width * 1.6, height: scaled * 1.5 / CGFloat(pools) + 160),
                                        alpha: shadeAlpha)
            let t = pools == 1 ? 0.5 : CGFloat(index) / CGFloat(pools - 1)
            shade.position = CGPoint(x: node.position.x, y: node.position.y + scaled * (0.36 - 0.72 * t))
            shade.zPosition = 5
            scene.addChild(shade)
        }

        return frame
    }

    // MARK: - Pieces

    /// The typed tag over the title, the way the level card names its sector.
    func tag(_ text: String, color: UIColor, delay: TimeInterval) -> SKLabelNode {
        Cinematic.typewriter(text, fontSize: 12, color: color, tracking: 2.5,
                             delay: delay, duration: 0.55, maxWidth: width)
    }

    /// A caption over a figure: small, monospaced, tracked wide.
    func caption(_ text: String) -> SKLabelNode {
        FilmUI.mono(text, size: 11, color: UITheme.Colors.textSecondary.withAlphaComponent(0.85),
                    tracking: 3, maxWidth: width)
    }

    /// The figure itself. Plain text, not tracked, so `FilmUI.countUp` can tick it.
    func figure(_ value: Int, color: UIColor, size: CGFloat = 40) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: UITheme.Typography.fontNumeric)
        label.text = value.formatted()
        label.fontSize = size
        label.fontColor = color
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        UITheme.fitLabel(label, toWidth: width, minimumFontSize: 20)
        return label
    }

    /// A line of data under the figure.
    func line(_ text: String, color: UIColor) -> SKLabelNode {
        FilmUI.mono(text, size: 12, color: color, tracking: 1, maxWidth: width)
    }
}
