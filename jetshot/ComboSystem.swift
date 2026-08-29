//
//  ComboSystem.swift
//  jetshot
//

import SpriteKit

/// Chain-kill scoring: the rule that turns "shoot things until the wave ends" into a
/// run the player is actively trying not to drop.
///
/// Before this existed every kill paid a flat `EnemyType.points`, so a clean level and a
/// sloppy one that took three hits scored the same. Nothing on screen escalated, nothing
/// was at stake between one kill and the next, and the only progression signal in a level
/// was the coin-pickup star rating handed out after it ended. The chain fixes the shape of
/// the moment-to-moment loop: kills close together pay more and more, one hit throws it
/// all away, and the meter draining in the corner is a visible reason to push forward into
/// the next enemy rather than hang back at the bottom of the screen.
///
/// `nonisolated`, and split from the node work below, for the reason `GameRules` gives:
/// the tier table and the decay window are pure arithmetic, they are the part worth
/// pinning down in tests, and the `jetshotTests` target cannot reach main-actor state.
nonisolated enum ComboRules {

    /// Chain length at which each multiplier step unlocks, and what it pays.
    ///
    /// The first tier deliberately sits at 3 rather than 2: two kills happen by accident
    /// in any wave, so unlocking there would leave the meter permanently on and mean
    /// nothing. Three in a window is already a small deliberate act.
    ///
    /// The top of the table is spaced much wider than the bottom (25 → 40 for the last
    /// step, against 3 → 6 for the first) because early tiers exist to teach the mechanic
    /// and late tiers exist to be chased. x8 is reachable, but only on a level the player
    /// already knows.
    static let tiers: [(chain: Int, multiplier: Int)] = [
        (3, 2),
        (6, 3),
        (10, 4),
        (15, 5),
        (25, 6),
        (40, 8)
    ]

    /// Longest a chain can idle before it drops, in seconds.
    static let baseWindow: TimeInterval = 3.0

    /// How much each kill shortens the window.
    static let windowDecayPerKill: TimeInterval = 0.05

    /// Floor on the window, so a long chain stays hard rather than impossible.
    ///
    /// 1.8 s is tuned against spawn density: enemy waves land roughly one enemy per
    /// 0.6–1.0 s once `LevelManager`'s pacing pass has tightened them, so holding a
    /// 40-chain demands that the player keep up with the spawner but never that they
    /// out-run it.
    static let minWindow: TimeInterval = 1.8

    /// Score multiplier for a chain of `chain` kills. 1 below the first tier.
    static func multiplier(forChain chain: Int) -> Int {
        var result = 1
        for tier in tiers where chain >= tier.chain {
            result = tier.multiplier
        }
        return result
    }

    /// Zero below the first tier, then 1...tiers.count. Used to decide when the meter
    /// has actually stepped up, which is what earns a sound and a haptic.
    static func tierIndex(forChain chain: Int) -> Int {
        var index = 0
        for (offset, tier) in tiers.enumerated() where chain >= tier.chain {
            index = offset + 1
        }
        return index
    }

    /// How long the chain survives without a kill, at its current length.
    static func window(forChain chain: Int) -> TimeInterval {
        let decayed = baseWindow - windowDecayPerKill * TimeInterval(chain)
        return max(minWindow, decayed)
    }

    /// Chain length that unlocks the next tier, or nil at the top of the table.
    /// Drives the "3 MORE" hint under the meter.
    static func nextTierChain(forChain chain: Int) -> Int? {
        return tiers.first(where: { chain < $0.chain })?.chain
    }
}

/// Owns the chain state and the meter that reports it.
///
/// A collaborator rather than a `GameScene` extension, for the reason spelled out on
/// `WeaponHeatSystem`: `private` is file-scoped in Swift, so an extension would have
/// forced the chain counter, the deadline, the tier index and the four HUD nodes to
/// widen to `internal` for the whole module. Same trade the other managers make.
final class ComboSystem {

    // MARK: - State

    /// Kills in the current chain. Public so `GameScene` can surface the best run of a
    /// level on the completion screen.
    private(set) var chain: Int = 0

    /// What the chain currently pays. `GameScene.addScore` folds this into every award.
    private(set) var multiplier: Int = 1

    /// Longest chain reached this level, for the level-complete screen. Deliberately not
    /// reset by `breakChain()` — it is a high-water mark for the whole level.
    private(set) var bestChain: Int = 0

    /// Gameplay-clock instant the chain lapses at. Nil when there is no chain.
    private var deadline: TimeInterval?

    /// Tier last announced, so a step up fires its cue exactly once.
    private var announcedTier: Int = 0

    /// Whether the meter is currently shown.
    ///
    /// Tracked explicitly rather than inferred from `meterNode.alpha`, which is what
    /// `refreshHUD` first did — and `refreshHUD` runs every frame. Testing `alpha < 1`
    /// there was true on every frame of the fade itself, so the fade was torn down and
    /// restarted from its own partial progress sixty times a second: the meter crept in
    /// over about two thirds of a second instead of appearing in 0.15 s, and never quite
    /// reached full opacity. A flag answers "is it up?" without asking a value that is
    /// mid-animation.
    private var isMeterVisible: Bool = false

    // MARK: - HUD

    private var meterNode: SKNode?
    private var multiplierLabel: SKLabelNode?
    private var chainLabel: SKLabelNode?
    /// Left-anchored host for the decay bar. Scaled instead of the shape itself — see
    /// `WeaponHeatSystem.installHUD(on:sceneWidth:)` for why an `SKShapeNode(rectOf:)`
    /// cannot be scaled directly without the fill drifting to the middle of the track.
    private var decayFillContainer: SKNode?
    private var decayFill: SKShapeNode?

    private static let barWidth: CGFloat = 76

    private weak var scene: GameScene?

    init(scene: GameScene) {
        self.scene = scene
    }

    // MARK: - HUD Lifecycle

    func removeHUD() {
        meterNode?.removeFromParent()
        meterNode = nil
        isMeterVisible = false
        multiplierLabel = nil
        chainLabel = nil
        decayFillContainer = nil
        decayFill = nil
    }

    /// Builds the meter into `parent`.
    ///
    /// Starts hidden (`alpha` 0) and stays that way until the first tier unlocks: an
    /// always-on "x1" would be noise, and the meter appearing at all is itself the
    /// reward signal for reaching three kills.
    ///
    /// It sits under the pause button on the right, mirroring the power-up countdown
    /// stack on the left, rather than under the score capsule in the centre where a
    /// score multiplier would more naturally belong. `PowerUpTimerHUD` lays its bars out
    /// left-aligned at x = 12 and 150pt wide, at almost exactly this height — on a 375pt
    /// screen a centred meter overlapped them by 13 points, and a player running three
    /// power-ups is precisely the player most likely to be holding a long chain.
    ///
    /// The backing panel is for the same reason the power-up bars carry one: this sits
    /// below the HUD scrim, over live playfield, and has to stay readable against a
    /// nebula.
    func installHUD(on parent: SKNode, at position: CGPoint) {
        removeHUD()

        let node = SKNode()
        node.position = position
        node.zPosition = 100
        node.alpha = 0
        parent.addChild(node)
        meterNode = node

        let panel = SKShapeNode(
            rectOf: CGSize(width: Self.barWidth + 14, height: 54),
            cornerRadius: 9
        )
        panel.fillColor = UIColor(white: 0.04, alpha: 0.55)
        panel.strokeColor = UIColor(white: 1.0, alpha: 0.12)
        panel.lineWidth = 1
        panel.zPosition = -1
        node.addChild(panel)

        let multiplierText = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        multiplierText.fontSize = 26
        multiplierText.fontColor = UITheme.Colors.primaryGoldLight
        multiplierText.verticalAlignmentMode = .center
        multiplierText.horizontalAlignmentMode = .center
        multiplierText.position = CGPoint(x: 0, y: 8)
        multiplierText.text = "x1"
        node.addChild(multiplierText)
        multiplierLabel = multiplierText

        let chainText = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
        chainText.fontSize = 10
        chainText.fontColor = UIColor(white: 1.0, alpha: 0.75)
        chainText.verticalAlignmentMode = .center
        chainText.horizontalAlignmentMode = .center
        chainText.position = CGPoint(x: 0, y: -10)
        chainText.text = L10n.Combo.chain(0)
        node.addChild(chainText)
        chainLabel = chainText

        // Decay track. The bar draining is the whole tension of the mechanic, so it sits
        // directly under the number rather than off at a screen edge.
        let track = SKShapeNode(
            rectOf: CGSize(width: Self.barWidth, height: 4),
            cornerRadius: 2
        )
        track.fillColor = UIColor(white: 0.25, alpha: 0.55)
        track.strokeColor = .clear
        track.position = CGPoint(x: 0, y: -20)
        node.addChild(track)

        let fillContainer = SKNode()
        fillContainer.position = CGPoint(x: -Self.barWidth / 2, y: -20)
        node.addChild(fillContainer)
        decayFillContainer = fillContainer

        let fill = SKShapeNode(rectOf: CGSize(width: Self.barWidth, height: 4), cornerRadius: 2)
        fill.fillColor = UITheme.Colors.primaryGold
        fill.strokeColor = .clear
        fill.position = CGPoint(x: Self.barWidth / 2, y: 0)
        fillContainer.addChild(fill)
        decayFill = fill
    }

    // MARK: - Rule

    /// Records a kill and extends the chain.
    ///
    /// Called after the enemy is confirmed destroyed, and *before* the score is awarded,
    /// so the kill that unlocks a tier is paid at the new rate. Paying it at the old rate
    /// reads as the meter lying about itself: the number flips to x3 while a "+20" from
    /// the same explosion floats past.
    func registerKill(currentTime: TimeInterval) {
        chain += 1
        bestChain = max(bestChain, chain)
        multiplier = ComboRules.multiplier(forChain: chain)
        deadline = currentTime + ComboRules.window(forChain: chain)

        let tier = ComboRules.tierIndex(forChain: chain)
        if tier > announcedTier {
            announcedTier = tier
            announceTierUp()
        } else {
            pulseMeter(scale: 1.12, duration: 0.07)
        }

        refreshHUD(currentTime: currentTime)
    }

    /// Drops the chain. Called when the player takes damage — the cost of being hit is
    /// no longer only a life, which is what makes a good run worth protecting.
    func breakChain() {
        // A chain that never reached a tier is not a loss worth announcing; silently
        // resetting avoids a "combo lost" flash every time two stray kills time out.
        let wasScoring = multiplier > 1

        chain = 0
        multiplier = 1
        deadline = nil
        announcedTier = 0

        if wasScoring {
            announceChainLost()
        } else {
            hideMeter()
        }
    }

    /// Expires the chain when its window lapses. Driven from `GameScene.update(_:)` on
    /// the gameplay clock, so a pause does not eat a chain.
    func update(currentTime: TimeInterval) {
        guard let deadline = deadline else { return }

        if currentTime >= deadline {
            breakChain()
            return
        }

        refreshHUD(currentTime: currentTime)
    }

    // MARK: - Presentation

    private func refreshHUD(currentTime: TimeInterval) {
        guard meterNode != nil else { return }

        // Below the first tier the meter stays out of the way entirely.
        guard multiplier > 1, let deadline = deadline else {
            hideMeter()
            return
        }

        showMeter()

        multiplierLabel?.text = "x\(multiplier)"
        multiplierLabel?.fontColor = Self.tierColor(forMultiplier: multiplier)
        decayFill?.fillColor = Self.tierColor(forMultiplier: multiplier)

        if let next = ComboRules.nextTierChain(forChain: chain) {
            chainLabel?.text = L10n.Combo.toNextTier(
                remaining: next - chain,
                multiplier: ComboRules.multiplier(forChain: next)
            )
        } else {
            chainLabel?.text = L10n.Combo.chain(chain)
        }

        let window = ComboRules.window(forChain: chain)
        let remaining = max(0, deadline - currentTime)
        decayFillContainer?.xScale = max(0.001, CGFloat(remaining / window))
    }

    private func announceTierUp() {
        guard let scene = scene else { return }

        SoundManager.shared.playScoreMultiplierSound(on: scene)
        HapticManager.shared.mediumTap()
        pulseMeter(scale: 1.5, duration: 0.12)
    }

    private func announceChainLost() {
        guard let meterNode = meterNode else { return }

        multiplierLabel?.fontColor = UITheme.Colors.dangerRed
        chainLabel?.text = L10n.Combo.lost
        decayFillContainer?.xScale = 0.001

        // Held briefly before it goes, so the player reads what they just lost rather
        // than only noticing the meter is missing.
        isMeterVisible = false
        meterNode.removeAction(forKey: "comboFade")
        meterNode.run(.sequence([
            .wait(forDuration: 0.45),
            .fadeOut(withDuration: 0.2)
        ]), withKey: "comboFade")
    }

    private func showMeter() {
        guard let meterNode = meterNode, !isMeterVisible else { return }
        isMeterVisible = true
        meterNode.removeAction(forKey: "comboFade")
        meterNode.run(.fadeIn(withDuration: 0.15), withKey: "comboFade")
    }

    private func hideMeter() {
        guard let meterNode = meterNode, isMeterVisible else { return }
        isMeterVisible = false
        meterNode.removeAction(forKey: "comboFade")
        meterNode.run(.fadeOut(withDuration: 0.2), withKey: "comboFade")
    }

    private func pulseMeter(scale: CGFloat, duration: TimeInterval) {
        guard let multiplierLabel = multiplierLabel else { return }
        multiplierLabel.removeAction(forKey: "comboPulse")
        let up = SKAction.scale(to: scale, duration: duration)
        up.timingMode = .easeOut
        let down = SKAction.scale(to: 1.0, duration: duration * 2)
        down.timingMode = .easeOut
        multiplierLabel.run(.sequence([up, down]), withKey: "comboPulse")
    }

    /// Heat ramp for the meter: cool at the bottom of the table, white-hot at the top.
    /// The colour is the fastest read the player gets on how much a chain is worth.
    ///
    /// Main-actor like the rest of the type, unlike `ComboRules` above — it reads
    /// `UITheme`, whose palette is main-actor bound.
    static func tierColor(forMultiplier multiplier: Int) -> UIColor {
        switch multiplier {
        case ..<2: return UITheme.Colors.primaryCyanLight
        case 2: return UIColor(red: 0.4, green: 1.0, blue: 0.7, alpha: 1.0)
        case 3: return UITheme.Colors.primaryGoldLight
        case 4: return UIColor(red: 1.0, green: 0.65, blue: 0.2, alpha: 1.0)
        case 5: return UIColor(red: 1.0, green: 0.4, blue: 0.3, alpha: 1.0)
        case 6: return UIColor(red: 1.0, green: 0.3, blue: 0.6, alpha: 1.0)
        default: return UIColor(red: 0.85, green: 0.5, blue: 1.0, alpha: 1.0)
        }
    }
}
