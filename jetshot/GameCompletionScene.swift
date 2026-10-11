//
//  GameCompletionScene.swift
//  jetshot
//
//  Created by Robert Libšanský on 27.10.2025.
//

import SpriteKit

class GameCompletionScene: SKScene {

    /// Shared vertical rhythm for the results screens. See `UITheme.PanelRhythm`.
    private typealias Rhythm = UITheme.PanelRhythm

    private let totalScore: Int
    private var isInitialized = false
    /// Every button here leaves the screen, once. See `FilmUI.Exit`.
    private let exit = FilmUI.Exit()

    init(size: CGSize, totalScore: Int) {
        self.totalScore = totalScore
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The victory screen, shown once the ending film has played.
    ///
    /// `didMove(to:)` used to immediately present `StoryScene(type: .ending)` and return,
    /// which left this entire scene unreachable: `setupUI()` is only called from
    /// `didChangeSize`, and that is gated on `isInitialized`, which nothing ever set.
    /// So the trophy, the total score and all three buttons never rendered, and beating
    /// level 50 dropped the player from the crawl straight back to the level select.
    /// The ending film now runs *before* this scene — see `LevelCompleteScene` and
    /// `StoryScene`'s `.ending` case — and this is the terminal screen.
    override func didMove(to view: SKView) {
        backgroundColor = UITheme.Colors.sceneBackground
        buildScene()
        isInitialized = true

        SoundManager.shared.startBackgroundMusic()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Only handle resize after initial setup
        guard isInitialized else { return }
        // Not while leaving: the rebuild would take the pressed button, and the press
        // animation whose completion is the way out, with it — stranding the screen with
        // its input already switched off.
        guard !exit.isTaken else { return }

        // Remove and recreate all elements
        removeAllChildren()
        buildScene()
    }

    private func buildScene() {
        GameBackdrop.attachAmbient(to: self, look: BackdropLook(theme: .epicentre, variant: 0)).pulse()
        NeonFX.attachGrade(to: self, zPosition: -5)
        setupUI()
    }

    override func willMove(from view: SKView) {
        // Clean up all resources before scene is removed
        removeAllActions()
        removeAllChildren()
    }

    private func setupUI() {
        addCelebration()
        let card = ResultsCard(sceneWidth: size.width)
        let gold = StoryPalette.gold

        // The ending film's own title, carried over as the tag: this screen is its last
        // frame.
        let tag = card.tag(L10n.Story.endingTitle, color: StoryPalette.mix(gold, .white, 0.3), delay: 0.2)
        card.add(tag, gapAbove: Rhythm.edge, height: 14, reveal: false)

        let emblem = createSingularity()
        card.add(emblem, gapAbove: 18, height: 56, reveal: false)

        let title = FilmUI.title(L10n.Completion.title, size: 40, color: UITheme.Colors.primaryGold,
                                 glow: gold, tracking: 9, maxWidth: card.width, bloom: 1.0)
        title.alpha = 0
        title.setScale(1.12)
        let settle = SKAction.scale(to: 1, duration: 1.0)
        settle.timingMode = .easeOut
        title.run(.sequence([.wait(forDuration: 0.5), .group([.fadeIn(withDuration: 0.4), settle])]))
        card.add(title, gapAbove: 16, height: title.frame.height, reveal: false)

        let rule = FilmUI.drawnRule(width: min(card.width, 260), color: UITheme.Colors.primaryGold,
                                    alpha: 0.7, delay: 0.8, duration: 0.9)
        card.add(rule, gapAbove: 14, height: 1, reveal: false)

        let congrats = FilmUI.label(L10n.Completion.congratulations.uppercased(), size: 20, color: .white,
                                    tracking: 3, maxWidth: card.width)
        card.add(congrats, gapAbove: 22, height: congrats.frame.height)

        let success = createMultilineText(L10n.Completion.success, width: card.width)
        card.add(success.node, gapAbove: 12, height: success.height)

        let thanks = createMultilineText(L10n.Completion.thanks, width: card.width)
        card.add(thanks.node, gapAbove: Rhythm.bodyLine, height: thanks.height)

        let figures = createScoreDisplay(card: card)
        card.add(figures.node, gapAbove: Rhythm.aroundFigures, height: figures.height)

        let playAgainButton = UITheme.createButton(text: L10n.Completion.playAgain, color: gold,
                                                   width: card.primaryButtonWidth, name: "playAgainButton",
                                                   primary: true)
        let levelsButton = UITheme.createButton(text: L10n.Common.levels, color: FilmUI.neutral,
                                                width: card.pairButtonWidth, name: "levelsButton")
        let menuButton = UITheme.createButton(text: L10n.Common.menu, color: FilmUI.neutral,
                                              width: card.pairButtonWidth, name: "menuButton")
        card.addButtons(primary: playAgainButton, pair: (levelsButton, menuButton), gapAbove: Rhythm.aroundFigures)

        card.install(in: self, accent: gold,
                     safeTop: GameConfiguration.safeAreaTop(in: view),
                     safeBottom: GameConfiguration.safeAreaBottom(in: view),
                     revealFrom: 1.1, revealStep: 0.15, shade: 0.8)
    }

    /// A block of body copy, one label per line, centred on the returned node's origin.
    ///
    /// Line pitch comes from the rhythm rather than from the font, so a block of copy
    /// breathes the same as every other stack on the results screens.
    private func createMultilineText(_ text: String, width: CGFloat) -> (node: SKNode, height: CGFloat) {
        let container = SKNode()

        let rows = text.components(separatedBy: "\n").enumerated().map { index, line -> (label: SKLabelNode, gapAbove: CGFloat) in
            let label = FilmUI.label(line, font: UITheme.Typography.fontRegular, size: 17,
                                     color: UITheme.Colors.textBody, tracking: 0.4, maxWidth: width, minimumSize: 12)
            return (label, index == 0 ? 0 : Rhythm.bodyLine)
        }

        let height = UITheme.stackLabels(rows, in: container)
        return (container, height)
    }

    /// The caption and the total, as one tight pair. See `UITheme.PanelRhythm`.
    ///
    /// The total does not count up: it is the sum of fifty levels the player has already
    /// watched land one at a time, and here it is simply the number.
    private func createScoreDisplay(card: ResultsCard) -> (node: SKNode, height: CGFloat) {
        let container = SKNode()

        let caption = card.caption(L10n.Completion.totalScore)
        let value = card.figure(totalScore, color: UITheme.Colors.primaryGoldLight, size: 42)
        NeonFX.addTextBloom(to: value, color: StoryPalette.gold, blur: 12, intensity: 0.9)

        // Named so `ResultsPanelCentringTests` can find the block it is asserting on;
        // nothing looks it up at runtime. Structural matching would not do on this
        // screen — the two body-copy blocks above are label-only containers too.
        container.name = "figureBlock"

        let height = UITheme.stackLabels([
            (caption, 0),
            (value, Rhythm.captionToValue)
        ], in: container)
        return (container, height)
    }

    /// The new singularity the ending film lights: a point of light in a ring, with the
    /// anamorphic streak the films put through every bright source.
    private func createSingularity() -> SKNode {
        let node = SKNode()
        node.alpha = 0
        node.setScale(0.4)

        let glow = NeonFX.radialGlow(radius: 60, color: StoryPalette.gold)
        glow.alpha = 0.35
        node.addChild(glow)

        let flare = LightSprite.flare(length: 220, thickness: 7, color: StoryPalette.sun)
        flare.alpha = 0.8
        node.addChild(flare)

        let ring = LightSprite.ring(radius: 22, color: StoryPalette.gold)
        node.addChild(ring)

        let core = LightSprite.star(size: 46, color: .white)
        node.addChild(core)

        let open = SKAction.scale(to: 1, duration: 0.7)
        open.timingMode = .easeOut
        node.run(.sequence([.wait(forDuration: 0.25), .group([.fadeIn(withDuration: 0.3), open])]))

        let breathe = SKAction.sequence([.scale(to: 1.15, duration: 1.4), .scale(to: 1.0, duration: 1.4)])
        breathe.timingMode = .easeInEaseOut
        ring.run(.repeatForever(breathe))
        flare.run(.repeatForever(.sequence([.fadeAlpha(to: 0.45, duration: 1.4), .fadeAlpha(to: 0.85, duration: 1.4)])))
        return node
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !exit.isTaken, let touch = touches.first else { return }
        let location = touch.location(in: self)

        guard let button = FilmUI.button(at: location, under: self,
                                         names: ["playAgainButton", "levelsButton", "menuButton"]),
              exit.take() else { return }
        HapticManager.shared.lightTap()
        SoundManager.shared.playButtonClickSound(on: self)

        let action: () -> Void
        switch button.name {
        case "playAgainButton": action = { [weak self] in self?.startNewGame() }
        case "levelsButton": action = { [weak self] in self?.goToLevelSelect() }
        default: action = { [weak self] in self?.goToMenu() }
        }
        button.run(UITheme.createButtonPressAnimation(completion: action))
    }

    private func startNewGame() {
        exit.present(from: self) { size in
            let gameScene = GameScene(size: size)
            gameScene.currentLevel = 1
            return gameScene
        }
    }

    private func goToLevelSelect() {
        // Show the last page with all completed levels
        exit.present(from: self) { LevelSelectScene(size: $0, startLevel: LevelManager.shared.totalLevels) }
    }

    private func goToMenu() {
        exit.present(from: self) { MenuScene(size: $0) }
    }

    // MARK: - Visual Effects

    /// Fireworks drawn in light: every so often a ring of light opens somewhere in the
    /// picture and throws sparks, in the films' palette. The confetti squares this
    /// replaces were the only solid, coloured, spinning things anywhere in the game.
    private func addCelebration() {
        let palette = [StoryPalette.gold, StoryPalette.sun, StoryPalette.cyan, StoryPalette.violet, StoryPalette.magenta]
        let burst = SKAction.run { [weak self] in
            guard let self = self else { return }
            let point = CGPoint(x: CGFloat.random(in: self.size.width * 0.12...self.size.width * 0.88),
                                y: CGFloat.random(in: self.size.height * 0.15...self.size.height * 0.85))
            let color = palette.randomElement() ?? StoryPalette.gold
            let ring = NeonFX.shockwave(at: point, startRadius: 4, endRadius: CGFloat.random(in: 50...90),
                                        color: color, lineWidth: 2, duration: 0.8)
            ring.zPosition = 2
            self.addChild(ring)
            let sparks = NeonFX.sparks(at: point, count: 16, color: color, speed: 120, length: 8, lifetime: 0.7)
            sparks.zPosition = 2
            self.addChild(sparks)
        }
        run(.sequence([
            .wait(forDuration: 0.6),
            .repeatForever(.sequence([burst, .wait(forDuration: 0.55, withRange: 0.5)]))
        ]), withKey: "celebration")
    }
}
