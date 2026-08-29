//
//  WeaponHeatSystem.swift
//  jetshot
//

import SpriteKit

/// Owns the weapon overheat rule and the HEAT gauge that reports it.
///
/// Split out of `GameScene`, which had grown past 4 300 lines and carried this whole
/// mechanic — eight stored properties, four tuning constants and the four HUD nodes —
/// inline. Extracting it as a collaborator rather than as a `GameScene` extension is
/// deliberate: `private` in Swift is file-scoped, so an extension in another file would
/// have forced every one of those properties to widen to `internal`. This codebase
/// documents each non-private member with the reason it had to be exposed (see
/// `GameScene.bossManager` and `activeEnemyCount`), and quietly opening a dozen more to
/// the whole module to buy a file split would run against that. A type that owns its own
/// state keeps them private *and* shrinks the scene — the same trade the existing
/// `EnemyManager` / `BossManager` / `CoinManager` already make.
///
/// The scene reference is `weak` and the audio/haptic cues are played through it, which
/// is exactly the arrangement the other managers use.
final class WeaponHeatSystem {

    // MARK: - Tuning

    private let maxHeat: CGFloat = GameConfiguration.maxHeat
    private let heatPerShot: CGFloat = GameConfiguration.heatPerShot
    private let cooldownRate: CGFloat = GameConfiguration.cooldownRate
    private let overheatCooldownTime: TimeInterval = GameConfiguration.overheatCooldownTime

    // MARK: - State

    /// 0.0 to 1.0. Private: the gauge is the only thing that reads the raw level, and it
    /// lives in here too.
    private var heat: CGFloat = 0.0

    /// Whether the guns are locked out. Read by `GameScene.shoot()`, which is the one
    /// caller outside this type, so this is the only piece of state that leaves it.
    private(set) var isOverheated: Bool = false

    private var overheatStartTime: TimeInterval = 0

    // MARK: - HUD

    private var heatBar: SKShapeNode?
    /// Left-anchored host for `heatBar`, and the node the fill level is scaled on.
    /// See `installHUD(on:sceneWidth:)` for why the shape cannot be scaled directly.
    private var heatBarFillContainer: SKNode?
    private var heatBarBackground: SKShapeNode?
    private var heatBarLabel: SKLabelNode?

    private weak var scene: SKScene?

    init(scene: SKScene) {
        self.scene = scene
    }

    // MARK: - HUD Lifecycle

    /// Detaches the gauge from the HUD, ahead of a rebuild.
    ///
    /// The container, not `heatBar` — the shape is its child, and detaching only the
    /// shape would strand an empty container in the HUD layer on every re-layout.
    func removeHUD() {
        heatBarFillContainer?.removeFromParent()
        heatBarBackground?.removeFromParent()
        heatBarLabel?.removeFromParent()
    }

    /// Builds the gauge into `parent`.
    ///
    /// Took a `topMargin` argument in its previous life as `GameScene.setupHeatBar` and
    /// never read it — the gauge is pinned to the bottom of the screen. Dropped rather
    /// than carried over.
    func installHUD(on parent: SKNode, sceneWidth: CGFloat) {
        let barWidth: CGFloat = 120
        let barHeight: CGFloat = 8
        let bottomMargin: CGFloat = 30 // Low enough to clear the player's start position

        // Background bar
        let background = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 4)
        background.fillColor = UIColor(white: 0.2, alpha: 0.6)
        background.strokeColor = UIColor(white: 0.4, alpha: 0.8)
        background.lineWidth = 1
        background.position = CGPoint(x: sceneWidth / 2, y: bottomMargin)
        background.zPosition = 100
        background.alpha = 0.0 // Hidden initially
        parent.addChild(background)
        heatBarBackground = background

        // Heat bar (foreground) - using full width, will scale down.
        //
        // The fill hangs off a container pinned to the *left* edge of the track, and
        // that container is what gets scaled. Scaling the shape node directly does not
        // work: `SKShapeNode(rectOf:)` centres its path on the node's origin, so an
        // xScale of 0.5 left a 60pt fill floating in the middle of the 120pt track with
        // a 30pt gap at each end instead of a bar half-filled from the left. Same
        // arrangement the power-up countdown bars use in `showPowerUpTimer`.
        let fillContainer = SKNode()
        fillContainer.position = CGPoint(x: sceneWidth / 2 - barWidth / 2, y: bottomMargin)
        fillContainer.xScale = 0.0  // Start with zero width
        fillContainer.zPosition = 101
        parent.addChild(fillContainer)
        heatBarFillContainer = fillContainer

        let heatFill = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight - 2), cornerRadius: 3)
        heatFill.fillColor = UIColor(red: 0.0, green: 1.0, blue: 0.8, alpha: 0.9)
        heatFill.strokeColor = .clear
        heatFill.position = CGPoint(x: barWidth / 2, y: 0)
        fillContainer.addChild(heatFill)
        heatBar = heatFill

        // Label
        let label = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
        label.fontSize = 11
        label.fontColor = UIColor(white: 0.8, alpha: 0.9)
        label.text = L10n.HUD.heat
        label.position = CGPoint(x: sceneWidth / 2, y: bottomMargin + 14)
        label.zPosition = 100
        label.alpha = 0.0 // Hidden initially
        parent.addChild(label)
        heatBarLabel = label

        // Re-apply the live heat level. The HUD is rebuilt twice during startup and
        // again on every resize, and a freshly built bar starts empty, so without this
        // a mid-level relayout blanked the gauge.
        updateHeatBar()
    }

    // MARK: - Rule

    /// Records a shot leaving the barrel, tripping the overheat if it tops the gauge out.
    ///
    /// The shot that tips the gauge over still fires: this used to `return` right after
    /// triggering the overheat, so the 25th trigger-pull was silently swallowed — the
    /// player paid for a shot that never left the barrel. Lockout is enforced by the
    /// `isOverheated` check in `GameScene.shoot()`, so blocking here as well is
    /// redundant.
    func registerShot(currentTime: TimeInterval) {
        heat += heatPerShot
        if heat >= maxHeat {
            heat = maxHeat
            triggerOverheat(currentTime: currentTime)
        }
        updateHeatBar()
    }

    /// Advances cooling.
    ///
    /// `isFiring` has to be the real firing condition, not just "is a finger down": an
    /// earlier version tested `!isTouching`, so heat froze while the player held a drag
    /// outside firing range — not shooting, but not cooling either. It is passed in rather
    /// than derived here because it depends on the ship's position relative to the touch,
    /// which is the scene's business — `GameScene.update(_:)` computes it and uses the
    /// same value to decide whether to fire.
    func update(deltaTime: TimeInterval, currentTime: TimeInterval, isFiring: Bool) {
        // If overheated, check if cooldown period is over
        if isOverheated {
            if currentTime - overheatStartTime >= overheatCooldownTime {
                isOverheated = false
                heat = 0.0
                updateHeatBar()

                // Visual feedback - flash green
                if let background = heatBarBackground {
                    let flash = SKAction.sequence([
                        SKAction.run {
                            background.fillColor = UIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 0.8)
                        },
                        SKAction.wait(forDuration: 0.2),
                        SKAction.run {
                            background.fillColor = UIColor(white: 0.2, alpha: 0.6)
                        }
                    ])
                    background.run(flash)
                }

                if let scene = scene {
                    SoundManager.shared.playPowerUpSound(on: scene)
                }
            }
            return
        }

        if !isFiring && heat > 0 {
            heat -= cooldownRate * CGFloat(deltaTime)
            if heat < 0 {
                heat = 0
            }
            updateHeatBar()
        }
    }

    // MARK: - Gauge

    private func updateHeatBar() {
        guard let heatBar = heatBar,
              let fillContainer = heatBarFillContainer,
              let background = heatBarBackground,
              let label = heatBarLabel else { return }

        // Hide heat bar when heat is low (below 15%)
        let shouldShow = heat > 0.15
        background.alpha = shouldShow ? 1.0 : 0.0
        label.alpha = shouldShow ? 1.0 : 0.0

        // Update bar width using xScale (much more efficient than recreating).
        // Scaled on the left-anchored container, so the fill grows rightwards from the
        // start of the track — see `installHUD(on:sceneWidth:)`.
        fillContainer.xScale = heat

        // Color changes based on heat level
        if heat < 0.5 {
            // Green to yellow
            let green = 1.0 - (heat * 2)
            heatBar.fillColor = UIColor(red: heat * 2, green: green, blue: 0.0, alpha: 0.9)
        } else if heat < 0.8 {
            // Yellow to orange
            let progress = (heat - 0.5) / 0.3
            heatBar.fillColor = UIColor(red: 1.0, green: 1.0 - (progress * 0.5), blue: 0.0, alpha: 0.9)
        } else {
            // Orange to red
            let progress = (heat - 0.8) / 0.2
            heatBar.fillColor = UIColor(red: 1.0, green: 0.5 - (progress * 0.5), blue: 0.0, alpha: 0.9)
        }

        // Pulse effect when near overheating.
        //
        // Started only when no pulse is already in flight. This method runs every frame
        // while the weapon cools, so an unguarded `run(pulse)` queued a fresh 0.3 s
        // action on every one of them: coasting down from 0.96 to the 0.85 threshold at
        // `cooldownRate` takes ~0.37 s, which stacked ~22 overlapping scale actions on
        // the same node. `SKAction.scale(to:)` is absolute, so they fought over
        // `background`'s scale and the intended breath came out as a jitter.
        //
        // A plain `withKey:` would not fix it — that restarts the action every frame, so
        // the pulse would never get past its first few milliseconds. Checking the key
        // first lets each pulse play out and the next frame start the following one,
        // which is what makes it breathe continuously while the heat stays up.
        if heat > 0.85 && !isOverheated && background.action(forKey: "heatPulse") == nil {
            let pulse = SKAction.sequence([
                SKAction.scale(to: 1.15, duration: 0.15),
                SKAction.scale(to: 1.0, duration: 0.15)
            ])
            background.run(pulse, withKey: "heatPulse")
        }
    }

    private func triggerOverheat(currentTime: TimeInterval) {
        isOverheated = true
        overheatStartTime = currentTime

        // Visual feedback
        if let background = heatBarBackground, let label = heatBarLabel {
            // Flash red
            let flash = SKAction.sequence([
                SKAction.run {
                    background.fillColor = UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.9)
                    label.text = L10n.HUD.overheated
                    label.fontColor = UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
                },
                SKAction.wait(forDuration: 0.3),
                SKAction.run {
                    background.fillColor = UIColor(white: 0.2, alpha: 0.6)
                },
                SKAction.wait(forDuration: 0.3)
            ])

            let flashSequence = SKAction.repeat(flash, count: 3)
            let reset = SKAction.run {
                label.text = L10n.HUD.heat
                label.fontColor = UIColor(white: 0.8, alpha: 0.9)
            }

            background.run(SKAction.sequence([flashSequence, reset]))
        }

        // Haptic feedback
        HapticManager.shared.heavyTap()

        // Sound effect
        if let scene = scene {
            SoundManager.shared.playExplosionSound(on: scene)
        }
    }
}
