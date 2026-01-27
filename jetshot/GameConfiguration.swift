//
//  GameConfiguration.swift
//  jetshot
//
//  Created by Robert Libšanský on 27.01.2026.
//

import Foundation
import CoreGraphics
import UIKit

/// Centralized game configuration to avoid magic numbers throughout the codebase
struct GameConfiguration {

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
    static let heatPerShot: CGFloat = 0.005

    /// Heat removed per second when not shooting
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

    /// Interval for bullet cleanup optimization (in seconds)
    static let bulletCleanupInterval: TimeInterval = 2.0

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
}
