//
//  GameConfiguration.swift
//  jetshot
//
//  Created by Robert Libšanský on 27.01.2026.
//

import Foundation
import CoreGraphics
import UIKit

/// Centralized game configuration to avoid magic numbers throughout the codebase.
///
/// `nonisolated`: this is constants and pure arithmetic. Left to the project's
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` it would be main-actor bound for no
/// reason, which is both inaccurate and stops a test module reading it.
nonisolated struct GameConfiguration {

    // MARK: - Player Configuration

    /// Default number of lives at game start
    static let defaultLives: Int = 3

    /// Maximum number of lives player can have
    static let maxLives: Int = 4

    /// Duration of invulnerability after taking damage (in seconds)
    static let invulnerabilityDuration: TimeInterval = 2.0

    /// Default player move speed for smooth animations
    static let playerMoveSpeed: TimeInterval = 0.2

    /// Distance threshold for shooting (in points)
    static let shootDistanceThreshold: CGFloat = 50

    // MARK: - Weapon System

    /// Time between shots (in seconds)
    static let defaultShootInterval: TimeInterval = 0.3

    /// Rapid fire shoot interval (in seconds)
    static let rapidFireInterval: TimeInterval = 0.1

    /// Maximum number of bullets player can have
    static let maxBulletCount: Int = 8

    /// Maximum number of side missiles player can have
    static let maxSideMissileCount: Int = 2

    // MARK: - Weapon Overheat System

    /// Heat added per shot (0.0 to 1.0)
    ///
    /// At the previous 0.005 it took 200 shots to overheat — 60 s of unbroken fire,
    /// or 20 s with rapid fire — while a full bar cooled off in 3.3 s and the gauge
    /// stayed hidden for the first 30 shots. Overheating was effectively unreachable,
    /// which made the whole gauge, its colour ramp and the OVERHEATED state dead
    /// weight. 0.04 puts the limit at 25 shots (~7.5 s sustained, 2.5 s rapid fire),
    /// so holding the trigger down is a real trade-off and tapping stays unpunished.
    static let heatPerShot: CGFloat = 0.04

    /// Heat removed per second when not firing
    static let cooldownRate: CGFloat = 0.30

    /// Cooldown time when overheated (in seconds)
    static let overheatCooldownTime: TimeInterval = 3.0

    /// Maximum heat level (1.0 = overheated)
    static let maxHeat: CGFloat = 1.0

    // MARK: - PowerUp Durations

    /// Shield power-up duration (in seconds)
    static let shieldDuration: TimeInterval = 5.0

    /// Lightning weapon duration (in seconds)
    static let lightningDuration: TimeInterval = 7.0

    /// Rapid fire duration (in seconds)
    static let rapidFireDuration: TimeInterval = 8.0

    /// Magnet duration (in seconds)
    static let magnetDuration: TimeInterval = 10.0

    /// Slow motion duration (in seconds)
    static let slowMotionDuration: TimeInterval = 6.0

    /// Score multiplier duration (in seconds)
    static let scoreMultiplierDuration: TimeInterval = 12.0

    /// Barrier duration (in seconds)
    static let barrierDuration: TimeInterval = 8.0

    /// Freeze bomb freeze duration (in seconds)
    static let freezeBombDuration: TimeInterval = 2.5

    // MARK: - Boss System

    /// Boss attack delay range (in seconds)
    static let bossAttackDelayMin: TimeInterval = 1.5
    static let bossAttackDelayMax: TimeInterval = 3.5

    // MARK: - Homing Missiles

    /// Number of homing missiles launched per use
    static let homingMissileCount: Int = 6

    /// Homing missile launch delay between each missile (in seconds)
    static let homingMissileLaunchDelay: TimeInterval = 0.15

    // MARK: - Magnet System

    /// Magnet attraction radius (in points)
    static let magnetRadius: CGFloat = 200

    /// Magnet attraction speed (points per second)
    static let magnetSpeed: CGFloat = 300

    /// Magnet update interval for performance (in seconds)
    static let magnetUpdateInterval: TimeInterval = 0.033 // ~30 FPS

    // MARK: - Vortex System

    /// Vortex gravitational influence radius (in points)
    static let vortexGravityRadius: CGFloat = 150

    /// Vortex pull strength multiplier
    static let vortexPullStrength: CGFloat = 5.0

    // MARK: - Enemy Movement Patterns

    // Both descent patterns are a sine sweep laid over a straight fall: amplitude is
    // the horizontal reach in points, frequency the number of half-cycles completed
    // between the top of the screen and the bottom. They were `private var`s on
    // `Enemy` that nothing ever assigned to, so the four numbers were unreachable
    // from the one place the game's tuning lives.

    /// Zigzag enemies: a moderate weave.
    static let zigzagAmplitude: CGFloat = 80
    static let zigzagFrequency: CGFloat = 2.0

    /// Strikers: wider and faster than a zigzag, which is what makes them strikers.
    static let strikerAmplitude: CGFloat = 120
    static let strikerFrequency: CGFloat = 3.0

    // MARK: - Camera Shake

    /// Base camera shake intensity multiplier for iPad (reduced for comfort)
    static let iPadShakeMultiplier: CGFloat = 0.7

    /// Camera shake intensity for small explosions
    static let shakeIntensitySmall: CGFloat = 3.0

    /// Camera shake intensity for normal explosions
    static let shakeIntensityNormal: CGFloat = 6.0

    /// Camera shake intensity for large explosions
    static let shakeIntensityLarge: CGFloat = 10.0

    /// Camera shake intensity for huge explosions (boss, player)
    static let shakeIntensityHuge: CGFloat = 15.0

    // MARK: - Level System

    /// Delay before level completion after last enemy is destroyed (in seconds)
    static let levelCompletionDelay: TimeInterval = 2.0

    /// Total number of levels in the game
    static let totalLevels: Int = 50

    // MARK: - UI Configuration

    /// Minimum top margin for UI elements (in points)
    static let minTopMargin: CGFloat = 40

    /// Additional spacing for safe area (in points)
    static let safeAreaTopSpacing: CGFloat = 20

    /// Player position above safe area (in points)
    static let playerBottomOffset: CGFloat = 60

    // MARK: - Performance

    /// Particle effect multiplier for iPad (reduce for better performance)
    static let iPadParticleMultiplier: CGFloat = 0.6

    /// Standard particle multiplier for iPhone
    static let iPhoneParticleMultiplier: CGFloat = 1.0

    /// Interval between off-screen cleanup sweeps (in seconds).
    ///
    /// Two values, because iPad runs the sweep more often: it draws more particles per
    /// blast and has more screen for stray bullets to sit in. A single 2.0 constant
    /// used to live here while `GameScene` hardcoded 0.3/0.5 and ignored it entirely.
    static let cleanupIntervalPad: TimeInterval = 0.3
    static let cleanupIntervalPhone: TimeInterval = 0.5

    /// Upper bound on a single frame's delta time (in seconds).
    ///
    /// `SKScene.update(_:)` receives absolute system time, which keeps advancing
    /// while the game is paused or the app is backgrounded. Without a clamp the
    /// first frame after a resume carried the entire pause duration, which yanked
    /// magnet-attracted coins off screen, teleported homing missiles into
    /// nothing, instantly cleared weapon heat and flushed every pending spawn
    /// timer at once. Two frames at 30 FPS is a generous ceiling for a real hitch.
    static let maxFrameDelta: TimeInterval = 1.0 / 30.0 * 2.0

    /// Maximum cached textures in ParallaxBackgroundHelper
    static let maxCachedTextures: Int = 10

    // MARK: - Coin System

    /// Coin spawn interval (in seconds)
    static let coinSpawnInterval: TimeInterval = 5.0

    /// Probability of coin spawn (0.0 to 1.0)
    static let coinSpawnProbability: Double = 0.5

    /// Minimum coins per level
    static let minCoinsPerLevel: Int = 10

    /// Maximum coins per level
    static let maxCoinsPerLevel: Int = 18

    // MARK: - Audio

    /// Default music volume (0.0 to 1.0)
    static let defaultMusicVolume: Float = 0.3

    // MARK: - Helper Methods

    /// Get particle multiplier based on device type
    static func particleMultiplier(for deviceIdiom: UIUserInterfaceIdiom) -> CGFloat {
        return deviceIdiom == .pad ? iPadParticleMultiplier : iPhoneParticleMultiplier
    }

    /// Calculate top margin for UI elements based on safe area
    static func topMargin(safeAreaTop: CGFloat) -> CGFloat {
        return max(safeAreaTop + safeAreaTopSpacing, minTopMargin)
    }

    // MARK: - Safe Area
    //
    // `@MainActor`, unlike everything above it: these touch `UIView`, which is
    // main-actor bound. The same isolation split `ExplosionFX` makes, from the other
    // side — most of that type is main-actor and only its two pure lookups are
    // `nonisolated`.
    //
    // They live here because the insets only ever feed the margins above, and every
    // scene needs the same answer. Seven call sites across four files used to work them
    // out inline, in two different ways — and the weaker of the two could not report a
    // notch at all.

    /// The top safe-area inset for a scene's view.
    ///
    /// Reads the view's own inset first and only falls back to its window's. Asking the
    /// window alone is what `Boss` and `StoryScene` used to do, via
    /// `view.window?.windowScene` and then `windows.first?.safeAreaInsets` — wrong twice
    /// over: `view.window` is still nil while a scene is being presented, so the whole
    /// lookup collapses to 0, and `windows.first` is not necessarily the window the view
    /// is even in. Reporting 0 for a notched iPhone is the bug that once parked the score
    /// under the Dynamic Island.
    @MainActor
    static func safeAreaTop(in view: UIView?) -> CGFloat {
        guard let view = view else { return 0 }
        return max(view.safeAreaInsets.top, view.window?.safeAreaInsets.top ?? 0)
    }

    /// The bottom safe-area inset for a scene's view. See `safeAreaTop(in:)`.
    @MainActor
    static func safeAreaBottom(in view: UIView?) -> CGFloat {
        guard let view = view else { return 0 }
        return max(view.safeAreaInsets.bottom, view.window?.safeAreaInsets.bottom ?? 0)
    }

    /// `topMargin(safeAreaTop:)` for a scene's view, so callers that only want the
    /// margin do not have to route the inset by hand.
    @MainActor
    static func topMargin(in view: UIView?) -> CGFloat {
        return topMargin(safeAreaTop: safeAreaTop(in: view))
    }
}
