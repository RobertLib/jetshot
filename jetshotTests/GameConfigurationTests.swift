//
//  GameConfigurationTests.swift
//  jetshotTests
//

import XCTest
import UIKit
@testable import jetshot

final class GameConfigurationTests: XCTestCase {

    func testTopMarginClearsTheSensorHousing() {
        // The score used to sit at 40pt dead centre, directly underneath the Dynamic
        // Island, where it was invisible on every notched iPhone. The margin has to
        // grow with the inset, never sit inside it.
        for inset in [CGFloat(0), 20, 44, 47, 59, 62] {
            let margin = GameConfiguration.topMargin(safeAreaTop: inset)
            XCTAssertGreaterThan(margin, inset, "margin \(margin) sits inside a \(inset)pt inset")
            XCTAssertGreaterThanOrEqual(margin, GameConfiguration.minTopMargin)
        }
    }

    func testTopMarginIsMonotonic() {
        var previous = GameConfiguration.topMargin(safeAreaTop: 0)
        for inset in stride(from: CGFloat(1), through: 80, by: 1) {
            let margin = GameConfiguration.topMargin(safeAreaTop: inset)
            XCTAssertGreaterThanOrEqual(margin, previous)
            previous = margin
        }
    }

    func testIPadGetsFewerParticles() {
        XCTAssertLessThan(
            GameConfiguration.particleMultiplier(for: .pad),
            GameConfiguration.particleMultiplier(for: .phone)
        )
        // Never zero, or explosions vanish entirely on iPad.
        XCTAssertGreaterThan(GameConfiguration.particleMultiplier(for: .pad), 0)
    }

    func testOverheatIsActuallyReachableButNotPunishing() {
        // At the original 0.005 heat per shot it took 200 shots to overheat — 60s of
        // unbroken fire — which made the whole gauge and its OVERHEATED state dead
        // weight. Bound the shot count from both sides so it stays a real trade-off.
        let shotsToOverheat = Int((GameConfiguration.maxHeat / GameConfiguration.heatPerShot).rounded(.up))
        XCTAssertTrue(
            (10...60).contains(shotsToOverheat),
            "\(shotsToOverheat) shots to overheat is outside the range that makes the gauge meaningful"
        )
    }

    func testFullHeatBarDrainsInAPlayableTime() {
        // Both directions matter. Too fast and the gauge never constrains anything;
        // too slow and a single sustained burst benches the player for most of a wave.
        let fullCooldown = Double(GameConfiguration.maxHeat / GameConfiguration.cooldownRate)
        XCTAssertTrue(
            (1.0...6.0).contains(fullCooldown),
            "a full heat bar takes \(fullCooldown)s to drain"
        )
    }

    func testSustainedFireBuysMoreThanOverheatingCosts() {
        // At the baseline fire rate, holding the trigger from cold to overheat has to
        // earn more trigger time than the lockout then takes away — otherwise the
        // weapon spends more of the level disabled than firing.
        let shots = Double(GameConfiguration.maxHeat / GameConfiguration.heatPerShot)
        let fireTime = shots * GameConfiguration.defaultShootInterval

        XCTAssertGreaterThan(fireTime, GameConfiguration.overheatCooldownTime)
    }

    func testOverheatLockoutIsPositive() {
        // A zero lockout would make triggering the overheat a free heat reset.
        XCTAssertGreaterThan(GameConfiguration.overheatCooldownTime, 0)
        XCTAssertGreaterThan(GameConfiguration.cooldownRate, 0)
    }

    func testRapidFireIsFasterThanNormalFire() {
        XCTAssertLessThan(GameConfiguration.rapidFireInterval, GameConfiguration.defaultShootInterval)
        XCTAssertGreaterThan(GameConfiguration.rapidFireInterval, 0)
    }

    func testLivesConfigurationIsConsistent() {
        XCTAssertGreaterThan(GameConfiguration.defaultLives, 0)
        // An extra-life pickup would be permanently unusable if the two were equal.
        XCTAssertGreaterThan(GameConfiguration.maxLives, GameConfiguration.defaultLives)
    }

    func testFrameDeltaClampIsAboveAPlayableFrameTime() {
        // The clamp exists so a resumed pause cannot arrive as one enormous frame, but
        // it must not throttle real 30fps frames either.
        XCTAssertGreaterThanOrEqual(GameConfiguration.maxFrameDelta, 1.0 / 30.0)
        XCTAssertLessThan(GameConfiguration.maxFrameDelta, 0.5)
    }

    func testCoinBoundsAreSane() {
        XCTAssertGreaterThan(GameConfiguration.minCoinsPerLevel, 0)
        // `Int.random(in: min...max)` traps on an inverted range.
        XCTAssertLessThanOrEqual(GameConfiguration.minCoinsPerLevel, GameConfiguration.maxCoinsPerLevel)
        XCTAssertTrue((0...1).contains(GameConfiguration.coinSpawnProbability))
    }

    func testCleanupRunsMoreOftenOnIPad() {
        XCTAssertLessThan(GameConfiguration.cleanupIntervalPad, GameConfiguration.cleanupIntervalPhone)
        XCTAssertGreaterThan(GameConfiguration.cleanupIntervalPad, 0)
    }

    func testShakeIntensityIncreasesWithExplosionSize() {
        let ladder = [
            GameConfiguration.shakeIntensitySmall,
            GameConfiguration.shakeIntensityNormal,
            GameConfiguration.shakeIntensityLarge,
            GameConfiguration.shakeIntensityHuge
        ]
        XCTAssertEqual(ladder, ladder.sorted(), "camera shake does not grow with blast size")
    }

    func testStrikersSweepHarderThanZigzags() {
        // What separates the two descent patterns: a striker reaches further sideways
        // and oscillates more times on the way down. These four numbers were
        // unreachable `private var`s on `Enemy` before they moved here, so nothing could
        // check that the distinction actually held.
        XCTAssertGreaterThan(GameConfiguration.strikerAmplitude, GameConfiguration.zigzagAmplitude)
        XCTAssertGreaterThan(GameConfiguration.strikerFrequency, GameConfiguration.zigzagFrequency)
    }

    func testMovementSweepsAreNonDegenerate() {
        // A zero amplitude or frequency collapses the sine sweep into a straight drop,
        // which is the `.basic` movement pattern — the enemy type stops being itself.
        for value in [
            GameConfiguration.zigzagAmplitude, GameConfiguration.zigzagFrequency,
            GameConfiguration.strikerAmplitude, GameConfiguration.strikerFrequency
        ] {
            XCTAssertGreaterThan(value, 0)
        }
    }
}
