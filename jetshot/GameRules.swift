//
//  GameRules.swift
//  jetshot
//

import CoreGraphics

/// Pure rules pulled out of the scenes that used to inline them.
///
/// Both of these were previously private expressions buried in a `SKScene` subclass,
/// which meant they could only be exercised by playing the game — and both had shipped
/// bugs (see the notes on each). Free functions over plain numbers are testable, so
/// `jetshotTests` pins them down.

// MARK: - Star Rating

nonisolated enum StarRating {

    /// Fraction of a level's coins needed for each rating.
    static let threeStarThreshold = 0.70
    static let twoStarThreshold = 0.40

    /// Stars earned for a level, from coin pickup rate.
    ///
    /// A level that spawned no coins always awards three: there is nothing to collect,
    /// so rating on it would be meaningless (and would divide by zero).
    static func stars(coinsCollected: Int, totalCoins: Int) -> Int {
        guard totalCoins > 0 else { return 3 }

        let fraction = Double(coinsCollected) / Double(totalCoins)
        if fraction >= threeStarThreshold { return 3 }
        if fraction >= twoStarThreshold { return 2 }
        return 1
    }
}

// MARK: - Shield Arc

nonisolated enum ShieldArc {

    /// Angular width of a shielded enemy's cover, centred on where it faces.
    static let defaultCoverage: CGFloat = .pi / 1.5

    /// Whether a shot arriving from `bulletAngle` is stopped by a shield facing
    /// `shieldAngle`. Both angles are in radians, measured the way `atan2` reports them.
    ///
    /// Wrapping the *difference* into (-π, π] is the only way to do this safely. An
    /// earlier version normalised `shieldAngle` into 0...2π and compared it against
    /// `atan2`'s -π...π, so the raw difference ranged over (-3π, π] — and `2π - diff`
    /// then went *negative* for the widest separations, sailing through a
    /// `< coverage / 2` test. A shot arriving from the left of an enemy whose shield
    /// faced right was reported as blocked.
    static func isBlocking(
        bulletAngle: CGFloat,
        shieldAngle: CGFloat,
        coverage: CGFloat = defaultCoverage
    ) -> Bool {
        return abs(signedDelta(from: shieldAngle, to: bulletAngle)) < coverage / 2
    }

    /// Smallest signed rotation carrying `from` onto `to`, in (-π, π].
    static func signedDelta(from: CGFloat, to: CGFloat) -> CGFloat {
        var delta = (to - from).truncatingRemainder(dividingBy: .pi * 2)
        if delta > .pi { delta -= .pi * 2 }
        if delta < -.pi { delta += .pi * 2 }
        return delta
    }
}
