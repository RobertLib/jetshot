//
//  GameRulesTests.swift
//  jetshotTests
//

import XCTest
@testable import jetshot

/// Covers the two rules extracted in `GameRules.swift`. Both were previously private
/// expressions inside an `SKScene`, and both had shipped a real bug.
final class StarRatingTests: XCTestCase {

    func testNoCoinsInLevelAlwaysAwardsThreeStars() {
        // Nothing to collect, so there is nothing to rate — and rating it would
        // divide by zero.
        XCTAssertEqual(StarRating.stars(coinsCollected: 0, totalCoins: 0), 3)
    }

    func testThresholdBoundariesAreInclusive() {
        // Exactly 70% earns three, exactly 40% earns two. A player landing precisely
        // on a threshold should get the better rating, not the worse one.
        XCTAssertEqual(StarRating.stars(coinsCollected: 7, totalCoins: 10), 3)
        XCTAssertEqual(StarRating.stars(coinsCollected: 4, totalCoins: 10), 2)
    }

    func testJustBelowThresholdsDropARating() {
        XCTAssertEqual(StarRating.stars(coinsCollected: 69, totalCoins: 100), 2)
        XCTAssertEqual(StarRating.stars(coinsCollected: 39, totalCoins: 100), 1)
    }

    func testMissingEverythingStillEarnsOneStar() {
        // The level was completed, so it is never worth zero.
        XCTAssertEqual(StarRating.stars(coinsCollected: 0, totalCoins: 18), 1)
    }

    func testPerfectRunEarnsThree() {
        XCTAssertEqual(StarRating.stars(coinsCollected: 18, totalCoins: 18), 3)
    }

    func testRatingNeverDecreasesAsMoreCoinsAreCollected() {
        let total = 18
        var previous = 0
        for collected in 0...total {
            let stars = StarRating.stars(coinsCollected: collected, totalCoins: total)
            XCTAssertGreaterThanOrEqual(stars, previous, "rating went down at \(collected)/\(total)")
            XCTAssertTrue((1...3).contains(stars))
            previous = stars
        }
    }
}

final class ShieldArcTests: XCTestCase {

    func testShotStraightIntoTheShieldIsBlocked() {
        XCTAssertTrue(ShieldArc.isBlocking(bulletAngle: 0, shieldAngle: 0))
    }

    /// The regression this extraction exists for.
    ///
    /// A shot arriving from the left of an enemy whose shield faces right must get
    /// through. The old implementation normalised the shield angle into 0...2π and
    /// compared it against `atan2`'s -π...π, which made the widest separations wrap
    /// negative and register as blocked.
    func testShotFromBehindTheShieldIsNotBlocked() {
        XCTAssertFalse(ShieldArc.isBlocking(bulletAngle: .pi, shieldAngle: 0))
        XCTAssertFalse(ShieldArc.isBlocking(bulletAngle: -.pi, shieldAngle: 0))
        XCTAssertFalse(ShieldArc.isBlocking(bulletAngle: 0, shieldAngle: .pi))
    }

    func testBlockingIsUnaffectedByFullTurnsOnEitherAngle() {
        let twoPi = CGFloat.pi * 2
        for turns in [-3, -1, 0, 1, 4] {
            let offset = CGFloat(turns) * twoPi
            XCTAssertTrue(
                ShieldArc.isBlocking(bulletAngle: offset, shieldAngle: 0),
                "head-on shot misread after \(turns) turns on the bullet angle"
            )
            XCTAssertFalse(
                ShieldArc.isBlocking(bulletAngle: .pi + offset, shieldAngle: 0),
                "rear shot misread after \(turns) turns on the bullet angle"
            )
            XCTAssertTrue(
                ShieldArc.isBlocking(bulletAngle: 0, shieldAngle: offset),
                "head-on shot misread after \(turns) turns on the shield angle"
            )
        }
    }

    func testCoverageEdgeIsSymmetric() {
        let halfWidth = ShieldArc.defaultCoverage / 2

        // Just inside either edge blocks; just outside does not.
        for sign in [CGFloat(1), -1] {
            XCTAssertTrue(ShieldArc.isBlocking(bulletAngle: sign * (halfWidth - 0.01), shieldAngle: 0))
            XCTAssertFalse(ShieldArc.isBlocking(bulletAngle: sign * (halfWidth + 0.01), shieldAngle: 0))
        }
    }

    func testBlockingFollowsTheShieldAsItSweeps() {
        // The shield rotates around the enemy; a shot tracking with it stays blocked
        // whatever absolute angle the pair happen to be at.
        for step in 0..<24 {
            let shield = CGFloat(step) * .pi / 12
            XCTAssertTrue(ShieldArc.isBlocking(bulletAngle: shield, shieldAngle: shield))
            XCTAssertFalse(ShieldArc.isBlocking(bulletAngle: shield + .pi, shieldAngle: shield))
        }
    }

    func testSignedDeltaStaysInRange() {
        for step in -40...40 {
            let delta = ShieldArc.signedDelta(from: 0, to: CGFloat(step) * 0.37)
            XCTAssertLessThanOrEqual(delta, .pi + 1e-6)
            XCTAssertGreaterThan(delta, -CGFloat.pi - 1e-6)
        }
    }
}
