//
//  PowerUpTimerHUD.swift
//  jetshot
//

import SpriteKit

/// The stack of power-up countdown bars in the top-left of the HUD.
///
/// Pulled out of `GameScene` for the reasons recorded on `WeaponHeatSystem`: it owns a
/// piece of state (the ordered bar list) plus the nodes that render it, so it can be a
/// collaborator that keeps that state private instead of an extension that would force
/// the scene's properties open to the module.
///
/// This type is deliberately *only* the HUD. The rule about when a bar may appear at all
/// — bars are suppressed while a boss is on screen, because the boss health bar owns that
/// corner — stays in `GameScene`, which is what knows about bosses.
final class PowerUpTimerHUD {

    private static let barHeight: CGFloat = 28
    private static let barSpacing: CGFloat = 6

    /// Ordered rather than keyed: the slot each bar occupies is its index, so the stack
    /// can be re-flowed when one of them expires.
    private var bars: [(name: String, node: SKNode)] = []

    /// Host for the bars.
    ///
    /// The bars have to sit above the playfield, but they must freeze with the gameplay
    /// clock rather than with the HUD — so they get their own layer whose `isPaused` is
    /// driven by `GameScene.setGameplayPaused(_:)` alongside `gameContentNode`. Parking
    /// them directly on the never-paused HUD node meant a bar drained while the pause
    /// menu was open and the power-up was gone on resume.
    private let layer = SKNode()

    /// Y of the topmost slot, read fresh on every layout.
    ///
    /// A closure rather than a stored number because the anchor moves: it is derived from
    /// the scene height and the current top margin, both of which change on rotation and
    /// on an iPad Split View resize. Caching it would have to be invalidated from every
    /// path that re-lays the HUD, and a missed one leaves the stack floating.
    private let anchorY: () -> CGFloat

    init(anchorY: @escaping () -> CGFloat) {
        self.anchorY = anchorY
        layer.name = "powerUpTimerLayer"
    }

    /// Whether the countdown animations are frozen. Driven by the gameplay clock.
    var isPaused: Bool {
        get { layer.isPaused }
        set { layer.isPaused = newValue }
    }

    func install(on parent: SKNode) {
        layer.removeFromParent()
        parent.addChild(layer)
    }

    // MARK: - Bars

    func show(name: String, duration: TimeInterval, color: UIColor, icon: String) {
        // Remove existing timer for this powerup if any
        remove(named: name)

        // Create container for timer. Its slot is assigned by layout(animated:) from its
        // index in the list, which is also re-run whenever a timer expires — deriving the
        // slot from a live count meant an expiring timer freed its index and the next
        // power-up was stacked directly on top of a still-running bar.
        let container = SKNode()
        container.zPosition = 100
        container.alpha = 0.7 // More subtle
        layer.addChild(container)
        bars.append((name: name, node: container))
        layout(animated: false)

        // Background - minimal and subtle
        let bgWidth: CGFloat = 150
        let background = SKShapeNode(rectOf: CGSize(width: bgWidth, height: Self.barHeight), cornerRadius: 7)
        background.fillColor = UIColor(white: 0.05, alpha: 0.6)
        background.strokeColor = UIColor(white: 0.4, alpha: 0.3)
        background.lineWidth = 1
        background.position = CGPoint(x: bgWidth / 2, y: 0)
        container.addChild(background)

        // Icon label - smaller and more subtle
        let iconLabel = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        iconLabel.text = icon
        iconLabel.fontSize = 12
        iconLabel.fontColor = UIColor(white: 0.9, alpha: 0.9)
        iconLabel.verticalAlignmentMode = .center
        iconLabel.horizontalAlignmentMode = .left
        iconLabel.position = CGPoint(x: 7, y: 0.5)
        container.addChild(iconLabel)

        // Progress bar container (on the right side) - smaller
        let barWidth: CGFloat = 55
        let barHeight: CGFloat = 7
        let barX: CGFloat = bgWidth - barWidth - 6

        // Progress bar background
        let barBackground = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 3)
        barBackground.fillColor = UIColor(white: 0.2, alpha: 0.5)
        barBackground.strokeColor = .clear
        barBackground.position = CGPoint(x: barX + barWidth / 2, y: 0)
        container.addChild(barBackground)

        // Progress bar fill (anchor at left edge for proper scaling)
        let barFillContainer = SKNode()
        barFillContainer.position = CGPoint(x: barX, y: 0)
        container.addChild(barFillContainer)

        let barFill = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 3)
        barFill.fillColor = color.withAlphaComponent(0.8)
        barFill.strokeColor = .clear
        barFill.position = CGPoint(x: barWidth / 2, y: 0)
        barFill.name = "progressFill"
        barFillContainer.addChild(barFill)

        // Animate progress bar from full to empty
        let scaleDown = SKAction.scaleX(to: 0.0, duration: duration)
        let removeSelf = SKAction.run { [weak self] in
            self?.remove(named: name)
        }
        barFillContainer.run(SKAction.sequence([scaleDown, removeSelf]))

        // Fade out near the end
        let waitBeforeFade = SKAction.wait(forDuration: max(0, duration - 1.0))
        let fadeOut = SKAction.fadeAlpha(to: 0.25, duration: 1.0)
        container.run(SKAction.sequence([waitBeforeFade, fadeOut]))
    }

    /// Removes a single power-up timer bar and closes the gap it leaves behind.
    func remove(named name: String) {
        guard let index = bars.firstIndex(where: { $0.name == name }) else { return }

        let entry = bars.remove(at: index)
        entry.node.removeAllActions()
        entry.node.removeFromParent()

        layout(animated: true)
    }

    /// Re-stacks the active timer bars from the top down, one per slot.
    func layout(animated: Bool) {
        let top = anchorY()
        for (index, entry) in bars.enumerated() {
            let target = CGPoint(
                x: 12,
                y: top - CGFloat(index) * (Self.barHeight + Self.barSpacing)
            )

            guard animated, entry.node.position != target else {
                entry.node.removeAction(forKey: "timerReflow")
                entry.node.position = target
                continue
            }

            let slide = SKAction.move(to: target, duration: 0.18)
            slide.timingMode = .easeOut
            entry.node.run(slide, withKey: "timerReflow")
        }
    }

    /// Immediately removes all bars without animation.
    func hideAll() {
        for entry in bars {
            entry.node.removeAllActions()
            entry.node.removeFromParent()
        }
        bars.removeAll()
    }
}
