//
//  OverdriveSystem.swift
//  jetshot
//

import SpriteKit

/// Owns the Overdrive meter and the round gauge that reports it.
///
/// The rule lives in `OverdriveRules`; this type holds the state and draws it. What an
/// overdrive *does* — cancelling the screen, the golden guns, the slow-motion beat — is
/// the scene's business and stays in `GameScene`, for the same reason the overheat
/// lockout lives in `WeaponHeatSystem` but the guns it silences live in the scene.
///
/// A collaborator rather than an extension for the reason `WeaponHeatSystem` spells out.
final class OverdriveSystem {

    // MARK: - State

    /// 0...1. Fills from shards and grazes; spent all at once.
    private(set) var charge: Double = 0

    private(set) var isActive: Bool = false

    /// Gameplay-clock instant the current overdrive ends.
    private var endsAt: TimeInterval = 0

    /// How many times the meter has filled this level (this run, in endless), so the
    /// "how to use it" hint goes with the first fill only.
    ///
    /// A count rather than the `hasBeenReady` flag it replaces, which `add(_:)` had
    /// already set by the time the scene could ask whether this fill was the first.
    /// Nothing read it, and the hint showed on every fill.
    private(set) var timesFilled: Int = 0

    var isReady: Bool {
        return !isActive && OverdriveRules.isFull(charge)
    }

    /// Seconds left of an active overdrive, for the gauge.
    private var remainingFraction: Double = 0

    // MARK: - HUD

    /// Name of the tappable gauge. Not private: `GameScene.touchesBegan` hit-tests it.
    static let buttonName = "overdriveButton"

    private var gauge: SKNode?
    private var ring: SKShapeNode?
    private var halo: SKSpriteNode?
    private var icon: SKShapeNode?
    private var caption: SKLabelNode?
    private var drawnFraction: Double = -1
    private var drawnMode: Int = -1

    static let radius: CGFloat = 24
    static let chargingColor = ShardSystem.color
    static let activeColor = ProjectileFX.overdriveBolt

    // MARK: - Rule

    /// Adds charge. Ignored while an overdrive is running — the meter is being spent,
    /// and refilling it from the shards the overdrive itself produces would chain one
    /// into the next.
    ///
    /// Returns true on the call that tops the meter up, so the scene can announce it.
    @discardableResult
    func add(_ amount: Double) -> Bool {
        guard !isActive else { return false }
        let wasFull = OverdriveRules.isFull(charge)
        charge = OverdriveRules.charge(charge, adding: amount)
        refreshHUD()
        let nowFull = OverdriveRules.isFull(charge)
        if nowFull && !wasFull {
            timesFilled += 1
            return true
        }
        return false
    }

    /// Length of the overdrive in progress, for the gauge's countdown.
    private var activeDuration: TimeInterval = OverdriveRules.duration

    /// Spends a full meter. Returns false, and changes nothing, if it is not full.
    ///
    /// `duration` is the rules' default, lengthened by the endless run's SUSTAIN perk.
    func activate(currentTime: TimeInterval, duration: TimeInterval = OverdriveRules.duration) -> Bool {
        guard isReady else { return false }
        isActive = true
        charge = 0
        activeDuration = max(0.1, duration)
        endsAt = currentTime + activeDuration
        remainingFraction = 1
        refreshHUD()
        return true
    }

    /// Advances an active overdrive. Returns true on the frame it ends.
    func update(currentTime: TimeInterval) -> Bool {
        guard isActive else { return false }
        let remaining = endsAt - currentTime
        remainingFraction = max(0, remaining / activeDuration)
        refreshHUD()
        if remaining <= 0 {
            isActive = false
            remainingFraction = 0
            refreshHUD()
            return true
        }
        return false
    }

    /// Ends an overdrive early, for teardown and the end of a level.
    func cancel() {
        isActive = false
        remainingFraction = 0
        refreshHUD()
    }

    #if DEBUG
    /// Fills the meter without the shards, for the screenshot harness and tests.
    func debugFill() {
        add(1.0)
    }
    #endif

    // MARK: - HUD

    func removeHUD() {
        gauge?.removeFromParent()
        gauge = nil
        ring = nil
        halo = nil
        icon = nil
        caption = nil
        drawnFraction = -1
        drawnMode = -1
    }

    /// Builds the gauge centred on `position`.
    func installHUD(on parent: SKNode, at position: CGPoint, caption text: String) {
        removeHUD()

        let root = SKNode()
        root.name = Self.buttonName
        root.position = position
        root.zPosition = 120
        parent.addChild(root)
        gauge = root

        let r = Self.radius

        // White light tinted per mode, so one texture serves charging and active.
        let haloNode = NeonFX.radialGlow(radius: r * 2.1, color: .white)
        haloNode.colorBlendFactor = 1
        haloNode.color = Self.chargingColor
        haloNode.alpha = 0
        haloNode.zPosition = -2
        root.addChild(haloNode)
        halo = haloNode

        // The hit target is the disc, and it is generous: the gauge is meant to be
        // hit by a thumb that is mostly watching the ship.
        let disc = SKShapeNode(circleOfRadius: r + 6)
        disc.name = Self.buttonName
        disc.fillColor = UIColor(red: 0.02, green: 0.04, blue: 0.1, alpha: 0.62)
        disc.strokeColor = UIColor(white: 1.0, alpha: 0.14)
        disc.lineWidth = 1
        disc.zPosition = -1
        root.addChild(disc)

        let track = SKShapeNode(circleOfRadius: r)
        track.name = Self.buttonName
        track.fillColor = .clear
        track.strokeColor = UIColor(white: 1.0, alpha: 0.12)
        track.lineWidth = 4
        root.addChild(track)

        let arc = SKShapeNode()
        arc.name = Self.buttonName
        arc.lineWidth = 4
        arc.lineCap = .round
        arc.fillColor = .clear
        arc.zPosition = 1
        root.addChild(arc)
        ring = arc

        let iconNode = SKShapeNode(path: Self.chevronPath())
        iconNode.name = Self.buttonName
        iconNode.fillColor = .clear
        iconNode.lineWidth = 2.6
        iconNode.lineCap = .round
        iconNode.lineJoin = .round
        iconNode.zPosition = 2
        root.addChild(iconNode)
        icon = iconNode

        let label = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        label.text = text
        label.fontSize = 8
        label.fontColor = UIColor(white: 1.0, alpha: 0.6)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: r + 13)
        label.zPosition = 2
        root.addChild(label)
        caption = label

        refreshHUD()
    }

    /// Whether `node` is part of the tappable gauge.
    static func isButton(_ node: SKNode) -> Bool {
        return node.name == buttonName || node.parent?.name == buttonName
    }

    /// Redraws the arc only when what it shows has actually changed.
    private func refreshHUD() {
        guard let ring = ring, let icon = icon, let halo = halo, let root = gauge else { return }

        // 0 charging, 1 ready, 2 active
        let mode = isActive ? 2 : (isReady ? 1 : 0)
        let fraction = isActive ? remainingFraction : charge

        if abs(fraction - drawnFraction) > 0.004 || mode != drawnMode {
            let r = Self.radius
            let path = CGMutablePath()
            if fraction > 0.001 {
                // Clockwise from twelve o'clock.
                let start = CGFloat.pi / 2
                let end = start - CGFloat(fraction) * .pi * 2
                path.addArc(center: .zero, radius: r, startAngle: start, endAngle: end, clockwise: true)
            }
            ring.path = path
            drawnFraction = fraction
        }

        guard mode != drawnMode else { return }
        drawnMode = mode

        root.removeAction(forKey: "readyPulse")
        halo.removeAllActions()
        root.setScale(1)

        switch mode {
        case 1:
            ring.strokeColor = Self.chargingColor
            icon.strokeColor = .white
            halo.color = Self.chargingColor
            halo.alpha = 0.55
            caption?.fontColor = Self.chargingColor
            let pulse = SKAction.sequence([
                .scale(to: 1.09, duration: 0.32),
                .scale(to: 1.0, duration: 0.32)
            ])
            root.run(.repeatForever(pulse), withKey: "readyPulse")
            halo.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.85, duration: 0.32),
                .fadeAlpha(to: 0.4, duration: 0.32)
            ])))
        case 2:
            ring.strokeColor = Self.activeColor
            icon.strokeColor = Self.activeColor
            halo.color = Self.activeColor
            halo.alpha = 0.5
            caption?.fontColor = Self.activeColor
        default:
            ring.strokeColor = Self.chargingColor.withAlphaComponent(0.85)
            icon.strokeColor = UIColor(white: 1.0, alpha: 0.35)
            halo.alpha = 0
            caption?.fontColor = UIColor(white: 1.0, alpha: 0.55)
        }
    }

    /// Two stacked upward chevrons — "boost".
    private static func chevronPath() -> CGPath {
        let path = CGMutablePath()
        for offset in [-4.5, 4.5] as [CGFloat] {
            path.move(to: CGPoint(x: -7, y: offset - 3.5))
            path.addLine(to: CGPoint(x: 0, y: offset + 3.5))
            path.addLine(to: CGPoint(x: 7, y: offset - 3.5))
        }
        return path
    }
}
