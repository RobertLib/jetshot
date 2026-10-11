//
//  UILayeringTests.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Draw order on the modals.
///
/// The view sets `ignoresSiblingOrder`, so SpriteKit draws strictly by accumulated
/// z and in no defined order among nodes that share one — tree order counts for
/// nothing. Two things followed. Glows and blooms hang one step *below* the node they
/// light, and with each modal's glass on the same z as its type they drew under the
/// glass: the settings lamps lost their halo and the dialog titles their bloom. And the
/// perk picker put its scrim, every card's glass and every card's type on one z, so
/// which covered which was up to the renderer.
@MainActor
final class UILayeringTests: XCTestCase {

    // MARK: - Settings

    func testEverythingOnTheSettingsPanelDrawsOverItsGlass() throws {
        let overlay = SettingsOverlay(sceneSize: CGSize(width: 390, height: 844))
        let panel = try XCTUnwrap(overlay.childNode(withName: "settingsPanel"))
        let glass = try XCTUnwrap(overlay.childNode(withName: "//settingsGlass"))
        let scrim = try XCTUnwrap(overlay.childNode(withName: "settingsScrim"))

        XCTAssertLessThan(z(scrim, in: overlay), z(glass, in: overlay), "the scrim draws over the panel's glass")
        for node in descendants(of: panel) where node !== glass {
            XCTAssertGreaterThan(z(node, in: overlay), z(glass, in: overlay),
                                 "\(describe(node)) draws under the settings panel's glass")
        }
    }

    // MARK: - Perk picker

    func testThePerkPickersLayersHaveADefinedOrder() throws {
        let picker = PerkPickOverlay(sceneSize: CGSize(width: 390, height: 844),
                                     perks: [.fireRate, .coolant, .armor],
                                     stacks: [.fireRate: 1], round: 3) { _ in }
        let scrim = try XCTUnwrap(picker.childNode(withName: "perkScrim"))
        let scrimZ = z(scrim, in: picker)

        for node in descendants(of: picker) where node !== scrim {
            XCTAssertGreaterThan(z(node, in: picker), scrimZ, "\(describe(node)) draws under the picker's scrim")
        }

        for index in 0..<3 {
            let card = try XCTUnwrap(picker.childNode(withName: "//\(PerkPickOverlay.cardName(index))"))
            let glass = try XCTUnwrap(card.childNode(withName: "perkGlass"))
            let wash = try XCTUnwrap(card.childNode(withName: "perkWash"))
            let glassZ = z(glass, in: picker), washZ = z(wash, in: picker)

            XCTAssertLessThan(glassZ, washZ, "card \(index)'s tint is not over its glass")
            for node in descendants(of: card) where node !== glass && node !== wash {
                XCTAssertGreaterThan(z(node, in: picker), washZ,
                                     "\(describe(node)) on card \(index) shares a z with, or sits under, its glass")
            }
        }
    }

    // MARK: - Reset confirmation

    func testEverythingOnTheResetDialogDrawsOverItsGlassAndTheGlassOverTheScrim() throws {
        let harness = GameplayHarness()
        defer { harness.teardown() }

        let scene = LevelSelectScene(size: harness.view.bounds.size)
        harness.present(scene, settle: 0.6)
        scene.debugShowResetDialog()
        harness.spin(0.3)

        let scrim = try XCTUnwrap(scene.childNode(withName: "confirmationOverlay"))
        let dialog = try XCTUnwrap(scene.childNode(withName: "confirmationDialog"))
        let glass = try XCTUnwrap(dialog.childNode(withName: "confirmationGlass"))

        XCTAssertLessThan(z(scrim, in: scene), z(glass, in: scene), "the dialog's glass draws under the scrim")
        for node in descendants(of: dialog) where node !== glass {
            XCTAssertGreaterThan(z(node, in: scene), z(glass, in: scene),
                                 "\(describe(node)) draws under the reset dialog's glass")
        }
    }

    // MARK: - Helpers

    /// A node's z as the renderer sees it: its own plus every ancestor's up to `root`.
    private func z(_ node: SKNode, in root: SKNode) -> CGFloat {
        var total: CGFloat = 0
        var current: SKNode? = node
        while let step = current, step !== root {
            total += step.zPosition
            current = step.parent
        }
        return total
    }

    private func descendants(of node: SKNode) -> [SKNode] {
        node.children.flatMap { [$0] + descendants(of: $0) }
    }

    private func describe(_ node: SKNode) -> String {
        let kind = String(describing: type(of: node))
        if let name = node.name { return "\(kind) '\(name)'" }
        if let label = node as? SKLabelNode {
            return "\(kind) '\(label.attributedText?.string ?? label.text ?? "")'"
        }
        return kind
    }
}
