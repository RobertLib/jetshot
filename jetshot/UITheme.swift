//
//  UITheme.swift
//  jetshot
//
//  Created by Robert Libšanský on 26.10.2025.
//

import SpriteKit

/// Centralized theme system for all UI elements in the game.
///
/// The screens around the game are drawn in the story films' language — see `FilmUI`
/// for the frame, the lettering and the light geometry. This type holds the shared
/// constants and the measuring that layout depends on.
struct UITheme {

    // MARK: - Colors

    struct Colors {
        // The story films' near-black: every screen has their 3D world behind it,
        // drawn in light, and light needs a dark to read against.
        static let sceneBackground = UIColor(red: 0.004, green: 0.006, blue: 0.02, alpha: 1.0)

        static let primaryCyan = UIColor.cyan
        static let primaryCyanLight = UIColor(red: 0.6, green: 1.0, blue: 1.0, alpha: 1.0)
        static let primaryGold = UIColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)
        static let primaryGoldLight = UIColor(red: 1.0, green: 0.95, blue: 0.3, alpha: 1.0)
        static let dangerRed = UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1.0)

        /// A figure that improved on what came before: a new record, a medal won.
        static let improvement = UIColor(red: 0.45, green: 1.0, blue: 0.6, alpha: 1.0)

        static let textSecondary = UIColor(red: 0.7, green: 0.8, blue: 0.9, alpha: 1.0)
        /// Body copy: the films' subtitle white, a touch off pure so it sits back from
        /// the lit type around it.
        static let textBody = UIColor(white: 0.9, alpha: 1.0)

        // Entity colours are deliberately *not* here. `EnemyType.color` /
        // `.strokeColor` in Enemy.swift and `PowerUpType.color` in PowerUp.swift own
        // them, keyed by the case they belong to, which is the only place that can stay
        // exhaustive — there are 27 enemy types and 13 power-ups, and the compiler
        // checks a switch over an enum but cannot check a list of loose constants.
        //
        // A partial copy of both lists used to sit here: nine enemy types, eight
        // power-ups, referenced by nothing. It had also drifted, so it was actively
        // misleading rather than merely dead — its `powerUpMagnet` was yellow against
        // the real purple-blue, and its `powerUpMultiShot` was teal against the real
        // yellow. Adding a colour here means maintaining two sources; add it to the
        // enum instead.
    }

    // MARK: - Typography

    struct Typography {
        // Condensed grotesque: reads as arcade signage instead of a system
        // dialog, and being narrower than Arial it also gives existing layouts
        // more breathing room rather than less.
        static let fontRegular = "AvenirNextCondensed-DemiBold"
        static let fontBold = "AvenirNextCondensed-Heavy"
        /// Fixed-width digits, so counters don't jitter as they tick up. Also the films'
        /// tag face, for anything that reads as data.
        static let fontNumeric = "Menlo-Bold"
    }

    // MARK: - Dimensions

    struct Dimensions {
        /// A primary button, and the height `createButton` falls back to for one.
        static let buttonHeight: CGFloat = 50
        /// Every other button.
        static let buttonHeightSecondary: CGFloat = 44

        /// START and ENDLESS on the menu.
        static let buttonWidthLarge: CGFloat = 250
        /// The menu's SETTINGS, and the settings panel's CLOSE.
        static let buttonWidthSmall: CGFloat = 170
        /// The one action a results screen or the pause menu is asking for, and the
        /// full width of the column under it.
        static let buttonWidthXLarge: CGFloat = 280
        /// Gap between the two buttons of a pair.
        static let buttonPairGap: CGFloat = 12
        /// One of a pair side by side: LEVELS / MENU, BACK / RESET, NO / YES — half the
        /// primary column, less the gap between them.
        static let buttonWidthHalf: CGFloat = (buttonWidthXLarge - buttonPairGap) / 2

        /// Widest a results column or a modal grows, so an iPad does not stretch the
        /// lines out of reach of each other.
        static let columnWidthMax: CGFloat = 340
    }

    // MARK: - Buttons

    /// Name of the tint inside a button's glass, which the press animation flashes.
    static let buttonWashName = "buttonWash"

    /// Creates a button in the films' style: dark glass inside a hairline frame, a
    /// bracket of light on each corner, and tracked lettering in the button's colour.
    ///
    /// These were rounded, colour-filled pills with a drop shadow — a mobile-app control
    /// dropped in front of a picture that is otherwise drawn entirely in light. A frame
    /// with lit corners is the films' own viewfinder at button size, so a button now
    /// reads as part of the HUD rather than as something stuck on top of it.
    ///
    /// The root stays an `SKShapeNode` whose path is exactly the button's outline: every
    /// scene hit-tests that path, and the layout tests measure it. Decoration hangs off
    /// it as *direct* children only — see `FilmUI.addBrackets(to:)`.
    ///
    /// - Parameter primary: the one action a screen is asking for. Its glass carries
    ///   more of the colour, its brackets are heavier and breathe, and its type is
    ///   larger, so it leads without having to be a different shape.
    static func createButton(
        text: String,
        color: UIColor,
        width: CGFloat,
        name: String,
        height: CGFloat? = nil,
        primary: Bool = false
    ) -> SKShapeNode {
        let buttonHeight = height ?? (primary ? Dimensions.buttonHeight : Dimensions.buttonHeightSecondary)
        let size = CGSize(width: width, height: buttonHeight)

        let button = SKShapeNode(rectOf: size)
        button.name = name
        button.fillColor = FilmUI.glass.withAlphaComponent(primary ? 0.8 : 0.66)
        button.strokeColor = color.withAlphaComponent(primary ? 0.42 : 0.24)
        button.lineWidth = 1

        // The colour, washed thinly over the glass.
        let wash = SKSpriteNode(color: color, size: CGSize(width: width - 2, height: buttonHeight - 2))
        let washAlpha: CGFloat = primary ? 0.13 : 0.045
        wash.alpha = washAlpha
        wash.userData = ["rest": washAlpha]
        wash.name = buttonWashName
        wash.zPosition = 0.5
        button.addChild(wash)

        let arm = min(10, buttonHeight * 0.24)
        let brackets = FilmUI.addBrackets(to: button, size: size, arm: arm, color: color,
                                          width: primary ? 1.5 : 1.2)
        for tube in brackets {
            tube.zPosition = 1
            tube.alpha = primary ? 1 : 0.7
            if primary {
                let dim = SKAction.fadeAlpha(to: 0.5, duration: 1.1)
                dim.timingMode = .easeInEaseOut
                let lift = SKAction.fadeAlpha(to: 1, duration: 1.1)
                lift.timingMode = .easeInEaseOut
                tube.run(.repeatForever(.sequence([dim, lift])))
            }
        }

        let label = FilmUI.label(
            text,
            size: primary ? 19 : 16,
            color: StoryPalette.mix(color, .white, primary ? 0.45 : 0.38),
            tracking: primary ? 3.5 : 2.5,
            maxWidth: width - 28,
            minimumSize: 11
        )
        label.zPosition = 2
        // Size first, then centre: the cap band is measured at the size it settled on.
        centerOnCapBand(label)
        button.addChild(label)

        return button
    }

    /// A button press: the glass flashes, the frame gives a little, and `completion`
    /// runs once it has sprung back.
    ///
    /// The give is relative to the scale the button rests at — on a wide screen the
    /// menu's buttons are drawn larger, and pressing one must not snap it back to its
    /// phone size.
    static func createButtonPressAnimation(completion: @escaping () -> Void) -> SKAction {
        let flash = SKAction.customAction(withDuration: 0) { node, _ in
            guard let wash = node.childNode(withName: buttonWashName) else { return }
            let rest = wash.userData?["rest"] as? CGFloat ?? wash.alpha
            wash.removeAction(forKey: "press")
            wash.run(.sequence([
                .fadeAlpha(to: 0.45, duration: 0.05),
                .fadeAlpha(to: rest, duration: 0.3)
            ]), withKey: "press")
        }
        let duration: CGFloat = 0.17
        let give = SKAction.customAction(withDuration: TimeInterval(duration)) { node, elapsed in
            if node.userData == nil { node.userData = [:] }
            let rest = node.userData?["restScale"] as? CGFloat ?? node.xScale
            node.userData?["restScale"] = rest
            // In over the first 40%, back out over the rest.
            let t = min(1, elapsed / duration)
            let depth: CGFloat = t < 0.4 ? t / 0.4 : 1 - (t - 0.4) / 0.6
            node.setScale(rest * (1 - 0.05 * depth))
        }
        return .sequence([.group([flash, give]), .run(completion)])
    }

    /// Centres a label on its **cap band** rather than on its full glyph box, and
    /// returns the resulting y so callers can offset from it.
    ///
    /// `verticalAlignmentMode = .center` centres the box SpriteKit measures, and that
    /// box grows upwards for accented capitals: at 20pt in this font "SETTINGS" reports
    /// 18pt tall while Czech "NASTAVENÍ" reports 22pt, because the acute on the Í sits
    /// above the cap line. Centring the taller box pushes the letters themselves 2pt
    /// down, so every button whose translation carries a diacritic sat visibly low while
    /// the English original looked right — which is why this only ever showed up in
    /// Czech.
    ///
    /// The fix is what a typesetter would do: ignore the accents and centre the caps.
    /// `.baseline` puts the baseline at the label's own origin, so the cap band can be
    /// measured directly off a diacritic-stripped copy of the same string, at the same
    /// font and size, and its midpoint moved to `centerY`.
    ///
    /// A no-op in effect for unaccented text: "SETTINGS" comes out at exactly the y
    /// `.center` gave it, so this changes no English layout anywhere.
    ///
    /// Assumes the single-line, all-caps text every button and HUD caption in the game
    /// uses. Lowercase descenders would want the descender counted too, and none of the
    /// callers have any.
    /// Stays on `.center` alignment and corrects the *position* instead of switching to
    /// `.baseline`, which would be the obvious way to do this and is a trap: several of
    /// these labels carry `SKAction.scale` entrances and pulses, and those scale about
    /// the node's origin. On `.baseline` the origin is the baseline, so a pulse would
    /// grow the text upwards out of its slot instead of breathing about its middle.
    ///
    /// With `.center` the origin stays the box centre, and the whole correction is the
    /// half-difference between the box SpriteKit measures and the cap band inside it —
    /// which is zero for unaccented text, hence no change to any English layout.
    @discardableResult
    static func centerOnCapBand(_ label: SKLabelNode, centerY: CGFloat = 0) -> CGFloat {
        label.verticalAlignmentMode = .center
        let correction = (label.frame.height - capBandHeight(of: label)) / 2
        let y = centerY + correction
        label.position = CGPoint(x: label.position.x, y: y)
        return y
    }

    /// Stacks `rows` downwards inside `container`, centred on its origin, and returns
    /// the block's height for the caller's own stack maths.
    ///
    /// Gaps here are **ink to ink**: the space actually left between the glyphs of one
    /// row and the next, accents included. Spacing by the cap band instead — which is
    /// what a single label in a box wants, see `centerOnCapBand` — makes the gaps
    /// *measure* equal and *look* unequal, because an accent eats into the space above
    /// its own row by however far it happens to reach. In the level-complete figures
    /// that came out as 16pt of cap-band gap either side of the record line rendering
    /// as 13pt above it and 14.5pt below: the acute on `NOVÝ` overhangs its caps by
    /// 3.5pt while the caron on `NEJDELŠÍ` overhangs by 2.
    ///
    /// So rows are spaced, and centred, on the box SpriteKit actually draws. There is no
    /// per-row cap-band correction: inside a stack a row has no slot of its own to be
    /// centred in, and the only thing a reader can judge is the air between the lines.
    @discardableResult
    static func stackLabels(
        _ rows: [(label: SKLabelNode, gapAbove: CGFloat)],
        in container: SKNode
    ) -> CGFloat {
        var y: CGFloat = 0
        var placed: [(label: SKLabelNode, centerY: CGFloat)] = []

        for (index, row) in rows.enumerated() {
            // `.center` centres the drawn box on the node's position, which is what
            // makes the arithmetic below symmetric — and what keeps any scale pulse on
            // one of these rows breathing about its middle.
            row.label.verticalAlignmentMode = .center
            let height = row.label.frame.height
            y -= (index == 0 ? 0 : row.gapAbove) + height / 2
            placed.append((row.label, y))
            y -= height / 2
        }

        // `y` is the bottom of the block, so -y is its height and -y/2 lifts it back
        // onto the container's origin. Callers place the container by its centre.
        let blockHeight = -y
        for entry in placed {
            entry.label.position = CGPoint(
                x: entry.label.position.x,
                y: entry.centerY + blockHeight / 2
            )
            container.addChild(entry.label)
        }
        return blockHeight
    }

    /// How tall a label reads, accents excluded — the height to stack it by.
    ///
    /// Using `frame.height` instead would make a row's height depend on whether its
    /// translation happens to carry a diacritic, so the same layout would breathe
    /// differently in Czech than in English for no reason the reader can see.
    static func capBandHeight(of label: SKLabelNode) -> CGFloat {
        return capBand(of: label).height
    }

    /// The label's glyph box with diacritics folded away, measured from its baseline.
    ///
    /// Tracked labels carry their font in an attributed string — `FilmUI.label` sets
    /// one — and the probe has to be built the same way, or it would measure the
    /// plain-text default font instead of the one on screen.
    private static func capBand(of label: SKLabelNode) -> CGRect {
        let fold: (String) -> String = {
            $0.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        }
        let probe = SKLabelNode(fontNamed: label.fontName ?? Typography.fontBold)
        if let attributed = label.attributedText, attributed.length > 0 {
            let attributes = attributed.attributes(at: 0, effectiveRange: nil)
            probe.attributedText = NSAttributedString(string: fold(attributed.string), attributes: attributes)
        } else {
            probe.text = fold(label.text ?? "")
            probe.fontSize = label.fontSize
        }
        probe.verticalAlignmentMode = .baseline
        probe.horizontalAlignmentMode = label.horizontalAlignmentMode
        return probe.frame
    }

    // MARK: - Results Panel Rhythm

    /// Vertical rhythm shared by the three results panels — game over, level complete
    /// and victory.
    ///
    /// One set of gaps for all three, because they are the same screen with different
    /// words: an emblem, a title, a block of figures, a primary button and a secondary
    /// row. All three used to hand-place every row at an offset from the panel's
    /// half-height, with the *same* magic numbers copied between them (`- 65`,
    /// `- spacing - 10`, `- 75`, `-46`, `-68`, `+125`, `- 65`). Two things came out of
    /// that: the figures ended up on a 22pt pitch — tighter than anything around them,
    /// which is what made them read as mashed together — while the panel kept ~40pt of
    /// dead space above the emblem and ~35pt below the buttons.
    ///
    /// Gaps are edge-to-edge between what you actually see, so a row's own height never
    /// leaks into the gap below it. `PanelStack` turns them into positions and sizes the
    /// panel to what it ends up holding, so there is no dead space left to tune.
    ///
    /// `nonisolated` for the reason `GameRules` and `ComboRules` give: constants and
    /// arithmetic over plain numbers, with no reason to be bound to the main actor just
    /// because the rest of `UITheme` touches UIKit.
    nonisolated struct PanelRhythm {
        /// Panel edge to the first and last row.
        static let edge: CGFloat = 30

        /// Emblem — the icon or the star row — to the title.
        static let emblemToTitle: CGFloat = 24

        /// Above *and* below the figure block, so it sits centred between the title and
        /// the button rather than merely somewhere between them.
        ///
        /// Deliberately one constant used on both sides instead of two that happen to be
        /// close. The block's height changes with what there is to report — two lines on
        /// a plain defeat, four when a personal best and a chain are worth calling out —
        /// and with separate gaps the centre drifts with it, differently on every screen.
        /// One value makes "centred" true by construction, whatever it ends up holding.
        static let aroundFigures: CGFloat = 30

        /// A caption to the number it labels, ink to ink. Deliberately the tightest gap
        /// in the set: the pair has to read as one thing.
        static let captionToValue: CGFloat = 6

        /// Between two figure lines, ink to ink — see `stackLabels`.
        ///
        /// 14 rather than 16 because the number changed meaning: as a cap-band gap it
        /// rendered as 13–14.5pt depending on which accents the row carried, and 14
        /// keeps the block at the density it already had while making every gap in it
        /// identical.
        static let figureLine: CGFloat = 14


        /// Primary button to the secondary row.
        static let buttonRow: CGFloat = 16

        /// Between body copy lines, which the victory screen has instead of figures.
        static let bodyLine: CGFloat = 14
    }

    /// Turns a list of row heights and the gaps above them into centre positions, and
    /// reports the height the panel needs to hold them.
    ///
    /// Two-pass on purpose: `height` is what the panel is built with, and `next(_:_:)`
    /// then walks the same rows down from that panel's top edge. Placing rows first and
    /// choosing a panel height afterwards is what left the old layouts lopsided.
    ///
    /// `nonisolated` on the same terms as `PanelRhythm`: it is a running total.
    nonisolated struct PanelStack {
        private var rows: [(gapAbove: CGFloat, height: CGFloat)] = []
        private var cursor: CGFloat = 0

        /// Records a row. Call once per row, top to bottom, before reading `height`.
        mutating func add(gapAbove: CGFloat, height: CGFloat) {
            rows.append((gapAbove, height))
        }

        /// Panel height that fits every recorded row.
        ///
        /// The top margin comes from the first row's own `gapAbove` — callers pass
        /// `PanelRhythm.edge` there — so only the bottom one is added here.
        var height: CGFloat {
            let content = rows.reduce(0) { $0 + $1.gapAbove + $1.height }
            return content + PanelRhythm.edge
        }

        /// Begins the placement pass at the top edge of a panel of `panelHeight`.
        mutating func start(panelHeight: CGFloat) {
            cursor = panelHeight / 2
        }

        /// Centre y of the next row down, given the same gap and height it was added
        /// with. Panel-relative, so it is what a child of the panel wants.
        mutating func next(gapAbove: CGFloat, height: CGFloat) -> CGFloat {
            cursor -= gapAbove + height / 2
            let center = cursor
            cursor -= height / 2
            return center
        }
    }

    /// Shrinks a label's point size until its text fits `maxWidth`.
    ///
    /// Every button in the game is laid out at a width chosen against English copy, and
    /// translations do not respect that width — Czech "NASTAVENÍ" is a third longer than
    /// "SETTINGS", "NEKONEČNÁ HRA" more than half again "ENDLESS" — while an `SKLabelNode`
    /// on one line has nothing to reflow and simply draws past its button's stroke.
    /// Widening every button to the longest language would cost the English layout for
    /// nothing, so the label gives up point size instead, down to a floor where it still
    /// reads as the same UI as its neighbours.
    ///
    /// A no-op whenever the text already fits, which is the English case throughout.
    static func fitLabel(_ label: SKLabelNode, toWidth maxWidth: CGFloat, minimumFontSize: CGFloat = 11) {
        guard maxWidth > 0 else { return }

        // Text width scales linearly with point size, so one division lands on the right
        // answer; the loop only exists to absorb the rounding that kerning and hinting
        // add back. It is bounded because the `minimumFontSize` clamp can otherwise leave
        // an over-long label reporting the same excess width forever.
        var size = label.fontSize
        for _ in 0..<4 {
            let width = label.frame.width
            guard width > maxWidth, width > 0 else { return }

            let fitted = max(minimumFontSize, size * maxWidth / width)
            guard fitted < size else { return }

            size = fitted
            label.fontSize = size
        }
    }

    /// Soft top-down scrim so HUD instrumentation stays legible over any
    /// background. Cached, since it only depends on the screen size.
    private static var scrimCache: [String: SKTexture] = [:]

    /// Drops the cache. Called from `GameScene.handleMemoryWarning()` alongside the
    /// other texture caches; the next request re-renders on demand.
    ///
    /// This was the one texture cache that warning did not reach, while
    /// `ParallaxBackgroundHelper`, `ParticleTexture`, `NeonFX` and `SurfaceFX` were all
    /// swept. Small in practice — the key is the screen size, so a phone only ever holds
    /// one entry — but "every texture cache is cleared under pressure" is easier to keep
    /// true than a list with one silent exception on it.
    static func clearCaches() {
        scrimCache.removeAll()
    }

    static func topScrimTexture(width: CGFloat, height: CGFloat) -> SKTexture {
        let key = "\(Int(width))x\(Int(height))"
        if let cached = scrimCache[key] { return cached }

        let size = CGSize(width: max(width, 1), height: max(height, 1))
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let stops: [(CGFloat, CGFloat)] = [(0.0, 0.72), (0.55, 0.34), (1.0, 0.0)]
            let base = UIColor(red: 0.01, green: 0.02, blue: 0.07, alpha: 1.0)
            let colors = stops.map { base.withAlphaComponent($0.1).cgColor } as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: stops.map { $0.0 }
            ) {
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }
        }

        let texture = SKTexture(image: image)
        scrimCache[key] = texture
        return texture
    }
}
