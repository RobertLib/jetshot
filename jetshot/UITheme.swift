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
        static let panelBoxBackground = UIColor(red: 0.15, green: 0.2, blue: 0.3, alpha: 1.0)
        static let panelBoxBorder = UIColor(red: 0.5, green: 0.7, blue: 1.0, alpha: 1.0)

        // Text colors
        static let textPrimary = UIColor.white
        static let textSecondary = UIColor(red: 0.7, green: 0.8, blue: 0.9, alpha: 1.0)
        static let textLabel = UIColor(red: 0.95, green: 0.95, blue: 1.0, alpha: 1.0)
        static let textLabelInactive = UIColor(red: 0.4, green: 0.4, blue: 0.45, alpha: 1.0)
        static let textOnButton = UIColor.black

        // Highlight colors
        static let highlightWhite = UIColor(white: 1.0, alpha: 0.15)
        static let highlightWhiteStrong = UIColor(white: 1.0, alpha: 0.2)
        static let highlightWhiteLight = UIColor(white: 1.0, alpha: 0.3)

        // Button colors
        static let buttonMenu = UIColor(red: 0.4, green: 0.4, blue: 0.5, alpha: 1.0)
        static let buttonLevels = UIColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1.0)

        // Accent colors
        static let accentGreen = UIColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1.0)

        // Shadow colors
        static let shadowBlack = UIColor.black
    }

    // MARK: - Typography

    struct Typography {
        static let fontRegular = "Arial"
        static let fontBold = "Arial-BoldMT"

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
        static let lineWidthGlow: CGFloat = 6
        static let lineWidthGlowStrong: CGFloat = 8

        // Button sizes
        static let buttonHeight: CGFloat = 50
        static let buttonWidthSmall: CGFloat = 125
        static let buttonWidthMedium: CGFloat = 160
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
        static let spacingSmall: CGFloat = 30
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
        static let alphaFadedMedium: CGFloat = 0.5
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
        button.addChild(label)

        return button
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
