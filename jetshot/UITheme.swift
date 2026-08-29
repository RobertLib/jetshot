//
//  UITheme.swift
//  jetshot
//
//  Created by Robert Libšanský on 26.10.2025.
//

import SpriteKit

/// Centralized theme system for all UI elements in the game
/// This ensures consistent styling across all scenes
struct UITheme {

    // MARK: - Colors

    struct Colors {
        // Background colors
        static let sceneBackground = UIColor(red: 0.05, green: 0.05, blue: 0.15, alpha: 1.0)

        // Primary UI colors
        static let primaryCyan = UIColor.cyan
        static let primaryCyanLight = UIColor(red: 0.6, green: 1.0, blue: 1.0, alpha: 1.0)
        static let primaryGold = UIColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)
        static let primaryGoldLight = UIColor(red: 1.0, green: 0.95, blue: 0.3, alpha: 1.0)

        // Status colors
        static let successGreen = UIColor(red: 0.3, green: 0.7, blue: 0.3, alpha: 1.0)
        static let successGreenLight = UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1.0)
        static let dangerRed = UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1.0)
        static let dangerRedLight = UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.5)

        // Level button colors
        static let levelUnlocked = UIColor(red: 0.1, green: 0.3, blue: 0.7, alpha: 1.0)
        static let levelUnlockedBorder = UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 1.0)
        static let levelCompleted = UIColor(red: 0.1, green: 0.5, blue: 0.2, alpha: 1.0)
        static let levelCompletedBorder = UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1.0)
        static let levelLocked = UIColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1.0)
        static let levelLockedBorder = UIColor(red: 0.3, green: 0.3, blue: 0.4, alpha: 1.0)

        // Panel colors
        static let panelBackground = UIColor(red: 0.1, green: 0.15, blue: 0.25, alpha: 0.95)

        // Text colors
        static let textPrimary = UIColor.white
        static let textSecondary = UIColor(red: 0.7, green: 0.8, blue: 0.9, alpha: 1.0)
        static let textLabel = UIColor(red: 0.95, green: 0.95, blue: 1.0, alpha: 1.0)
        static let textLabelInactive = UIColor(red: 0.4, green: 0.4, blue: 0.45, alpha: 1.0)

        // Highlight colors
        static let highlightWhiteStrong = UIColor(white: 1.0, alpha: 0.2)

        // Button colors
        static let buttonMenu = UIColor(red: 0.4, green: 0.4, blue: 0.5, alpha: 1.0)
        static let buttonLevels = UIColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1.0)

        // Shadow colors
        static let shadowBlack = UIColor.black

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
        /// Fixed-width digits, so counters don't jitter as they tick up.
        static let fontNumeric = "Menlo-Bold"

        // Font sizes
        static let sizeHuge: CGFloat = 64
        static let sizeLarge: CGFloat = 32
        static let sizeMedium: CGFloat = 28
        static let sizeRegular: CGFloat = 24
        static let sizeSmall: CGFloat = 20
        static let sizeTiny: CGFloat = 16
    }

    // MARK: - Dimensions

    struct Dimensions {
        // Corner radius
        static let cornerRadiusSmall: CGFloat = 10
        static let cornerRadiusMedium: CGFloat = 12
        static let cornerRadiusLarge: CGFloat = 15
        static let cornerRadiusXLarge: CGFloat = 25

        // Line widths
        static let lineWidthThin: CGFloat = 1.5
        static let lineWidthRegular: CGFloat = 2
        static let lineWidthMedium: CGFloat = 3
        static let lineWidthThick: CGFloat = 3.5
        static let lineWidthExtraThick: CGFloat = 4
        static let lineWidthGlowStrong: CGFloat = 8

        // Button sizes
        static let buttonHeight: CGFloat = 50
        static let buttonWidthSmall: CGFloat = 125
        static let buttonWidthLarge: CGFloat = 200
        static let buttonWidthXLarge: CGFloat = 260

        // Panel sizes
        static let panelWidthMax: CGFloat = 350

        // Star sizes
        static let starOuterRadius: CGFloat = 20
        static let starInnerRadius: CGFloat = 10
        static let starSmallRadius: CGFloat = 6

        // Level button sizes
        static let levelButtonSize: CGFloat = 70
        static let levelButtonSpacing: CGFloat = 30

        // Spacing
        static let spacingMedium: CGFloat = 50
        static let spacingLarge: CGFloat = 60
    }

    // MARK: - Animations

    struct Animations {
        // Durations
        static let durationFast: TimeInterval = 0.1
        static let durationQuick: TimeInterval = 0.2
        static let durationNormal: TimeInterval = 0.3
        static let durationMedium: TimeInterval = 0.4
        static let durationSlow: TimeInterval = 0.5
        static let durationGlowPulse: TimeInterval = 1.0
        static let durationButtonPulse: TimeInterval = 0.8

        // Alpha values
        static let alphaFadedLow: CGFloat = 0.3
        static let alphaFadedHigh: CGFloat = 0.7
        static let alphaInactive: CGFloat = 0.3
        static let alphaFull: CGFloat = 1.0

        // Scale values
        static let scaleSmall: CGFloat = 0.5
        static let scalePressed: CGFloat = 0.9
        static let scaleNormal: CGFloat = 1.0
        static let scalePulsed: CGFloat = 1.1
    }

    // MARK: - Helper Methods

    /// Creates a standard styled button with consistent appearance (outlined style)
    static func createButton(text: String, color: UIColor, width: CGFloat, name: String, height: CGFloat? = nil) -> SKShapeNode {
        let buttonHeight = height ?? Dimensions.buttonHeight
        let button = SKShapeNode(
            rectOf: CGSize(width: width, height: buttonHeight),
            cornerRadius: Dimensions.cornerRadiusMedium
        )
        // Subtle background tint with border color
        button.fillColor = color.withAlphaComponent(0.15)

        // Use the provided color for the stroke
        button.strokeColor = color
        button.lineWidth = Dimensions.lineWidthMedium
        button.name = name

        // Add subtle shadow effect with lower opacity for outlined style
        let shadow = SKShapeNode(
            rectOf: CGSize(width: width, height: buttonHeight),
            cornerRadius: Dimensions.cornerRadiusMedium
        )
        shadow.fillColor = .clear
        shadow.strokeColor = Colors.shadowBlack
        shadow.alpha = Animations.alphaFadedLow
        shadow.lineWidth = Dimensions.lineWidthMedium
        shadow.position = CGPoint(x: 0, y: -2)
        shadow.zPosition = -1
        button.addChild(shadow)

        // Add label with color matching the border
        let label = SKLabelNode(fontNamed: Typography.fontBold)
        label.text = text
        label.fontSize = Typography.sizeSmall
        label.fontColor = color
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = .zero
        label.zPosition = 2
        fitLabel(label, toWidth: width - 20)
        button.addChild(label)

        return button
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

    /// Creates a standard panel with consistent styling
    static func createPanel(width: CGFloat, height: CGFloat, borderColor: UIColor) -> SKShapeNode {
        let panel = SKShapeNode(
            rectOf: CGSize(width: width, height: height),
            cornerRadius: Dimensions.cornerRadiusXLarge
        )
        panel.fillColor = Colors.panelBackground
        panel.strokeColor = borderColor
        panel.lineWidth = Dimensions.lineWidthExtraThick
        return panel
    }

    /// Creates a star shape with consistent appearance
    static func createStar(outerRadius: CGFloat? = nil, innerRadius: CGFloat? = nil) -> SKShapeNode {
        let path = CGMutablePath()
        let points = 5
        let outer = outerRadius ?? Dimensions.starOuterRadius
        let inner = innerRadius ?? Dimensions.starInnerRadius

        for i in 0..<points * 2 {
            let angle = CGFloat(i) * .pi / CGFloat(points)
            let radius = i % 2 == 0 ? outer : inner
            let x = radius * cos(angle - .pi / 2)
            let y = radius * sin(angle - .pi / 2)

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()

        return SKShapeNode(path: path)
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

    /// Creates a glow effect animation
    static func createGlowPulseAnimation(fromAlpha: CGFloat? = nil, toAlpha: CGFloat? = nil) -> SKAction {
        let from = fromAlpha ?? Animations.alphaFadedLow
        let to = toAlpha ?? Animations.alphaFadedHigh
        return SKAction.repeatForever(
            SKAction.sequence([
                SKAction.fadeAlpha(to: from, duration: Animations.durationGlowPulse),
                SKAction.fadeAlpha(to: to, duration: Animations.durationGlowPulse)
            ])
        )
    }

    /// Creates a button pulse animation
    static func createButtonPulseAnimation() -> SKAction {
        return SKAction.repeatForever(
            SKAction.sequence([
                SKAction.scale(to: Animations.scalePulsed, duration: Animations.durationButtonPulse),
                SKAction.scale(to: Animations.scaleNormal, duration: Animations.durationButtonPulse)
            ])
        )
    }

    /// Creates a button press animation
    static func createButtonPressAnimation(completion: @escaping () -> Void) -> SKAction {
        return SKAction.sequence([
            SKAction.scale(to: Animations.scalePressed, duration: Animations.durationFast),
            SKAction.scale(to: Animations.scaleNormal, duration: Animations.durationFast),
            SKAction.run(completion)
        ])
    }
}
