//
//  EndlessRosterTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Which enemies an endless round may put in which kind of wave.
///
/// The roster widens into the formation types (scout, bomber, elite guard, spinner) from
/// tier 2, and the loose wave used to draw from all of it. Those types have no movement
/// of their own, so a loose one parked just above the screen for good — still firing —
/// and a round, which ends only on an empty playfield, never ended. The formation wave
/// had the opposite problem: any roster type, and `FormationManager` never runs a type's
/// own routine, so turrets never docked, bouncers never bounced, teleporters never
/// teleported.
final class EndlessRosterTests: XCTestCase {

    private let rounds = 1...60

    /// The draws are random, so each round is generated several times over.
    private let samples = 12

    @MainActor
    func testLooseWavesNeverDrawFormationOnlyTypes() {
        for _ in 0..<samples {
            for round in rounds {
                for wave in EndlessDirector.waves(forRound: round) where !wave.isFormation {
                    for type in wave.enemies {
                        XCTAssertFalse(type.isFormationOnly, "round \(round) sent a loose \(type), which cannot fly itself")
                    }
                }
            }
        }
    }

    @MainActor
    func testFormationWavesOnlyDrawTypesThatFlyInOne() {
        for _ in 0..<samples {
            for round in rounds {
                for wave in EndlessDirector.waves(forRound: round) where wave.isFormation {
                    for type in wave.enemies {
                        XCTAssertTrue(type.canFlyInFormation, "round \(round) put a \(type) in a formation")
                    }
                }
            }
        }
    }

    @MainActor
    func testEveryUnlockedTypeStillHasSomewhereToAppear() {
        for round in rounds {
            let loose = EndlessDirector.looseRoster(forRound: round)
            let formation = EndlessDirector.formationRoster(forRound: round)
            XCTAssertFalse(loose.isEmpty, "round \(round) has nothing to send loose")
            XCTAssertFalse(formation.isEmpty, "round \(round) has nothing to fly in formation")
            XCTAssertEqual(
                Set(loose).union(formation), Set(EndlessDirector.roster(forRound: round)),
                "round \(round) unlocked a type that can never actually appear"
            )
        }
    }

    @MainActor
    func testALooseFormationTypeDivesInsteadOfParking() {
        // Defence in depth for anything else that spawns one loose: `startMovement` used
        // to `break` for these, leaving them where they spawned, above the top edge.
        let harness = GameplayHarness()
        let scene = harness.startPlaying()
        let spawnY = scene.size.height + 20

        let types: [EnemyType] = [.formation, .scout, .eliteGuard, .bomber, .spinner, .commander]
        let enemies = types.enumerated().map { index, type -> Enemy in
            let enemy = harness.addEnemy(type, at: CGPoint(x: 50 + CGFloat(index) * 55, y: spawnY))
            enemy.startMovement {}
            return enemy
        }

        harness.spin(0.8)

        for enemy in enemies {
            XCTAssertLessThan(enemy.position.y, spawnY - 40, "a loose \(enemy.enemyType) stayed parked above the screen")
        }
    }
}
